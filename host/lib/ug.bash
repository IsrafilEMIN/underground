# shellcheck shell=bash

ug_color_fds=""
if [[ -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
  [[ ! -t 1 ]] || ug_color_fds+="1"
  [[ ! -t 2 ]] || ug_color_fds+="2"
fi

ug_paint() {
  [[ $ug_color_fds == *"$1"* ]] || return 0
  case $2 in
    bold) printf '\e[1m' ;;
    dim) printf '\e[2m' ;;
    green) printf '\e[32m' ;;
    red) printf '\e[31m' ;;
    yellow) printf '\e[33m' ;;
    off) printf '\e[0m' ;;
    *) printf 'ug_paint: unknown color %s\n' "$2" >&2; return 1 ;;
  esac
}

ug_say() {
  local kind=$1 subject=$2 text=$3 color=""
  case $kind in
    same) color=dim ;;
    changed) color=green ;;
    ok) ;;
    *) printf 'ug_say: unknown kind %s\n' "$kind" >&2; return 1 ;;
  esac
  printf '%s%s:%s %s%s%s\n' "$(ug_paint 1 bold)" "$subject" "$(ug_paint 1 off)" "${color:+$(ug_paint 1 "$color")}" "$text" "$(ug_paint 1 off)"
}

ug_pin() { sed -n "s/^$2=//p" "$1"; }

ug_facts_file=${BASH_SOURCE[0]%/*}/../facts

ug_fact() {
  local value
  value=$(ug_pin "$ug_facts_file" "$1") || return 1
  [[ -n $value ]] || { printf 'ug_fact: %s has no %s\n' "$ug_facts_file" "$1" >&2; return 1; }
  printf '%s\n' "$value"
}

ug_services_file=${BASH_SOURCE[0]%/*}/../services

ug_services() {
  local want=${1:-} label name scope user template health log
  while IFS='|' read -r label name scope user template health log || [[ -n $label ]]; do
    [[ -n $label && $label != \#* ]] || continue
    [[ -z $want || $scope == "$want" ]] || continue
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$label" "$name" "$scope" "$user" "$template" "$health" "$log"
  done <"$ug_services_file"
}

ug_as() {
  local login=$1
  shift
  if [[ $login == "$(id -un)" ]]; then
    "$@"
  else
    sudo -n -u "$login" -H "$@"
  fi
}

ug_read_as() {
  ug_as "$1" /bin/cat -- "$2"
}

# shellcheck disable=SC2016
ug_write_as() {
  ug_as "$1" /bin/sh -c 'umask 077 && /bin/cat >"$1" && /bin/chmod 600 "$1"' sh "$2"
}

ug_user_walls() {
  local owner_home=$1 key keys login other target home open=0
  local -a targets
  keys=$(sed -n 's/^\([a-z_]*\)_user=.*/\1/p' "$ug_facts_file")
  for key in $keys; do
    login=$(ug_fact "${key}_user") || return 1
    if ! ug_as "$login" /usr/bin/true >/dev/null 2>&1; then
      printf '%s: sudo does not run as this user, so its walls are not proven\n' "$login"
      open=1
      continue
    fi
    targets=("$owner_home")
    for other in $keys; do
      if [[ $other != "$key" ]]; then
        home=$(ug_fact "${other}_home") || return 1
        targets+=("$home")
      fi
    done
    for target in "${targets[@]}"; do
      if ug_as "$login" /bin/ls "$target" >/dev/null 2>&1; then
        printf '%s can list %s, a home that is not its own\n' "$login" "$target"
        open=1
      fi
    done
  done
  return "$open"
}

ug_service_login() {
  if [[ $1 == root ]]; then printf 'root\n'; else ug_fact "$1"; fi
}

# shellcheck disable=SC2034
ug_service_probe() {
  local scope=$1 label=$2 health kind target domain agent
  health=$(ug_service_expand "$3") || { printf 'cannot expand the health of %s\n' "$label"; return 1; }
  kind=${health%% *}
  target=${health#* }
  domain=system
  [[ $scope == daemon ]] || domain=gui/$UID
  ug_probe=()
  ug_probe_subject="service $label"
  ug_probe_hint="sudo launchctl print $domain/$label"
  [[ $scope == daemon ]] || ug_probe_hint="launchctl print $domain/$label"
  case $scope:$kind in
    *:http) ug_probe=(ug_http_answers "$target") ;;
    *:port) ug_probe=(ug_port_answers "${target%:*}" "${target##*:}") ;;
    *:launchd) ug_probe=(launchctl print "$domain/$label") ;;
    daemon:pf)
      agent=$(ug_fact agent_user) || return 1
      ug_probe=(ug_pf_refuses_listener "$(id -u "$agent")" "$target")
      ug_probe_subject="firewall: $agent cannot be the listener on port $target"
      ug_probe_hint="sudo pfctl -a com.apple/underground -sr"
      ;;
    *) printf 'the service table gives %s the health kind %s, which a job of scope %s cannot use\n' "$label" "$kind" "$scope"; return 1 ;;
  esac
}

ug_service_data() { printf '%s\n' "${UG_DATA:-$HOME/$(ug_fact owner_data)}"; }

ug_service_expand() {
  local text=$1 name value data
  data=$(ug_service_data)
  while [[ $text =~ @([A-Z_]+)@ ]]; do
    name=${BASH_REMATCH[1]}
    name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
    case $name in
      data) value=$data ;;
      *) value=$(ug_fact "$name") || return 1 ;;
    esac
    [[ -n $value ]] || { printf 'ug_service_expand: no value for %s\n' "${BASH_REMATCH[0]}" >&2; return 1; }
    text=${text/"${BASH_REMATCH[0]}"/$value}
  done
  printf '%s\n' "$text"
}

ug_err() {
  local tool=$1
  shift
  printf '%s%s: %s%s\n' "$(ug_paint 2 red)" "$tool" "$*" "$(ug_paint 2 off)" >&2
}

ug_die() {
  ug_err "$@"
  exit 1
}

ug_stopped() {
  local status=$1 line=$2 command=$3 tool=$4 file=$5 mid=${6:-} tail=${7:-}
  (( BASH_SUBSHELL == 0 )) || return 0
  printf '%s%s: stopped at line %s of %s: "%s" failed with exit %s. The steps above it are done, and nothing after it ran%s. Fix the cause, then run host/bin/ug-setup again%s.%s\n' \
    "$(ug_paint 2 red)" "$tool" "$line" "$file" "$command" "$status" "$mid" "$tail" "$(ug_paint 2 off)" >&2
}

ug_sha256() {
  local out
  out=$(shasum -a 256 "$1") || return 1
  printf '%s\n' "${out%% *}"
}

ug_check_checkout() {
  local src=$1 tool=$2 head main dirty
  dirty=$(git --no-optional-locks -c "safe.directory=$src" -C "$src" status --porcelain 2>/dev/null) || { printf '%s: %s is not a git checkout\n' "$tool" "$src" >&2; return 1; }
  [[ -z $dirty ]] || { printf '%s: the checkout %s has changes that are not committed; setup installs only origin/main\n' "$tool" "$src" >&2; return 1; }
  head=$(git --no-optional-locks -c "safe.directory=$src" -C "$src" rev-parse HEAD)
  main=$(git --no-optional-locks -c "safe.directory=$src" -C "$src" rev-parse --verify --quiet origin/main) || { printf '%s: the checkout has no origin/main; fetch first\n' "$tool" >&2; return 1; }
  [[ $head == "$main" ]] || { printf '%s: the checkout is at %s, not origin/main %s; setup installs only origin/main. Check out main and pull, or fetch.\n' "$tool" "${head:0:7}" "${main:0:7}" >&2; return 1; }
}

ug_pull_main() {
  local src=$1 tool=$2 dirty branch before after
  local g=(git --no-optional-locks -c "safe.directory=$src" -C "$src")
  dirty=$("${g[@]}" status --porcelain 2>/dev/null) || { printf '%s: %s is not a git checkout\n' "$tool" "$src" >&2; return 1; }
  [[ -z $dirty ]] || { printf '%s: the checkout %s has changes that are not committed; commit, stash, or drop them, then run setup again. Nothing changed.\n%s\n' "$tool" "$src" "$dirty" >&2; return 1; }
  if "${g[@]}" rev-parse --verify --quiet origin/main >/dev/null; then
    [[ $("${g[@]}" rev-list --count origin/main..HEAD) == 0 ]] || { printf '%s: the checkout has commits that are not on origin/main, so it is not origin/main and cannot fast-forward; move them to a branch, then run setup again. Nothing changed.\n' "$tool" >&2; return 1; }
  fi
  branch=$("${g[@]}" symbolic-ref --quiet --short HEAD) || branch=""
  [[ $branch == main ]] || { printf '%s: the checkout is on %s, not main; check out main, then run setup again. Nothing changed.\n' "$tool" "${branch:-a detached HEAD}" >&2; return 1; }
  before=$("${g[@]}" rev-parse HEAD)
  ug_check_main_rule "$src" "$tool" || return 1
  "${g[@]}" fetch --quiet origin main || { printf '%s: cannot fetch main from origin; check the network and your GitHub login, then run setup again. Nothing changed.\n' "$tool" >&2; return 1; }
  "${g[@]}" merge --quiet --ff-only origin/main || { printf '%s: main cannot fast-forward to origin/main; setup does not merge or rebase. Nothing changed.\n' "$tool" >&2; return 1; }
  after=$("${g[@]}" rev-parse HEAD)
  if [[ $before == "$after" ]]; then
    ug_say same checkout "main is at origin/main ${after:0:7}"
  else
    ug_say changed checkout "pulled main from ${before:0:7} to ${after:0:7}"
  fi
}

ug_repo_slug() {
  local top=$1 url re='^(git@github\.com:|ssh://git@github\.com/|https://github\.com/)([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$'
  url=$(git -C "$top" config --get remote.origin.url 2>/dev/null) || true
  url=${url%/}
  url=${url%.git}
  [[ $url =~ $re ]] || return 1
  echo "${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
}

# Sync every "<repo path> <target>" source of the list into the agent's home and print
# each synced target, so a caller can look inside what arrived; errors are printed like
# ug_die's and return 1, and the caller decides whether that stops it. The trailing
# words run before git, so a caller that runs as root can pass ug_as <owner> and have
# git read the repos, which are the owner's, as the owner.
ug_sync_sources() {
  local sources=$1 owner_home=$2 agent=$3 unpack=$4 tool=$5
  shift 5
  local -a runner=("${@+"$@"}") paths=() targets=()
  local target_re='^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$'
  local line path target extra prev n
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n $line && $line != '#'* ]] || continue
    read -r path target extra <<<"$line"
    [[ -n $path ]] || continue
    [[ -n $target && -z $extra ]] ||
      { ug_err "$tool" "in $sources: \"$line\": a source is a repo path and a target, and nothing else"; return 1; }
    case $path in
      '~') path=$owner_home ;;
      '~/'*) path=$owner_home/${path#\~/} ;;
    esac
    [[ $path == /* ]] ||
      { ug_err "$tool" "in $sources: $path is not an absolute path or a ~ path"; return 1; }
    [[ $target =~ $target_re ]] ||
      { ug_err "$tool" "in $sources: target $target is not a plain relative path"; return 1; }
    case /$target/ in
      */./*|*/../*) ug_err "$tool" "in $sources: target $target has a . or .. component"; return 1 ;;
    esac
    for (( n=0; n<${#targets[@]}; n++ )); do
      prev=${targets[n]}
      [[ $target != "$prev" ]] ||
        { ug_err "$tool" "in $sources: two sources share the target $target"; return 1; }
      case $target in
        "$prev"/*) ug_err "$tool" "in $sources: target $target lies inside $prev"; return 1 ;;
      esac
      case $prev in
        "$target"/*) ug_err "$tool" "in $sources: target $prev lies inside $target"; return 1 ;;
      esac
    done
    paths+=("$path") targets+=("$target")
  done <"$sources"
  for (( n=0; n<${#paths[@]}; n++ )); do
    ( cd / && ${runner[@]+"${runner[@]}"} git -C "${paths[n]}" archive --format=tar HEAD | sudo -n -u "$agent" "$unpack" "${targets[n]}" ) ||
      { ug_err "$tool" "cannot sync ${paths[n]} to $agent:${targets[n]}; is it a git repository with a HEAD commit, and did host/bin/ug-setup grant the unpack helper?"; return 1; }
    printf '%s\n' "${targets[n]}"
  done
}

# shellcheck disable=SC2016
ug_main_rule_gaps='
def rule(t): [.rules[]? | select(.type == t)][0];
[
  (if (.conditions.ref_name.include // []) | any(. == "~DEFAULT_BRANCH" or . == "refs/heads/main") then empty else "it does not target main" end),
  (if ((.conditions.ref_name.exclude // []) | length) == 0 then empty else "it excludes some branches" end),
  (rule("pull_request").parameters as $p
    | if $p == null then "it does not require a pull request"
      elif ($p.required_approving_review_count >= 1 and $p.require_code_owner_review and $p.require_last_push_approval and $p.dismiss_stale_reviews_on_push) then empty
      else "its pull request rule needs 1 approval, review from code owners, approval of the most recent push, and dismissal of stale approvals" end),
  (if rule("non_fast_forward") then empty else "it does not block force pushes" end),
  (if rule("deletion") then empty else "it does not restrict deletions" end),
  (if .bypass_actors == null then "its bypass list is not readable with your login"
    else (.bypass_actors[] | select(((.actor_type == "RepositoryRole" and .actor_id == 5) or .actor_type == "OrganizationAdmin") | not) | "its bypass list holds \(.actor_type) \(.actor_id)") end)
] | join("; ")
'

ug_check_main_rule() {
  local src=$1 tool=$2 repo login file="" name pattern owners star=0 ids id json gaps report=""
  local open="$tool: a wall is open, so setup pulled nothing and changed nothing:"
  repo=$(ug_repo_slug "$src") || { printf '%s the origin of %s is not a GitHub repo, so setup cannot check the rule on main\n' "$open" "$src" >&2; return 1; }
  for name in gh jq; do
    command -v "$name" >/dev/null || { printf '%s setup needs %s to check the rule on main of %s\n' "$open" "$name" "$repo" >&2; return 1; }
  done
  login=$(gh api user | jq -r '.login // empty') || login=""
  [[ -n $login ]] || { printf '%s gh has no GitHub login; run: gh auth login\n' "$open" >&2; return 1; }

  for name in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
    [[ ! -f $src/$name ]] || { file=$src/$name; break; }
  done
  [[ -n $file ]] || { printf '%s the checkout has no CODEOWNERS file, so no file needs your approval\n' "$open" >&2; return 1; }
  while read -r pattern owners || [[ -n $pattern ]]; do
    [[ -n $pattern && $pattern != \#* ]] || continue
    [[ $owners == "@$login" ]] || { printf '%s %s gives "%s" to "%s"; each line must name only @%s\n' "$open" "$file" "$pattern" "$owners" "$login" >&2; return 1; }
    [[ $pattern != "*" ]] || star=1
  done <"$file"
  [[ $star == 1 ]] || { printf '%s %s has no line "* @%s", so some files need no approval\n' "$open" "$file" "$login" >&2; return 1; }

  ids=$(gh api "repos/$repo/rulesets?per_page=100" | jq -r '.[] | select(.enforcement == "active" and .target == "branch") | .id') || { printf '%s cannot read the rulesets of %s from GitHub\n' "$open" "$repo" >&2; return 1; }
  for id in $ids; do
    json=$(gh api "repos/$repo/rulesets/$id") || { printf '%s cannot read ruleset %s of %s from GitHub\n' "$open" "$id" "$repo" >&2; return 1; }
    gaps=$(jq -r "$ug_main_rule_gaps" <<<"$json") || { printf '%s cannot read ruleset %s of %s: GitHub sent no ruleset\n' "$open" "$id" "$repo" >&2; return 1; }
    [[ -n $gaps ]] || { ug_say same "main rule" "GitHub merges to main of $repo only with the approval of @$login (ruleset $id)"; return 0; }
    report+=" Ruleset $id: $gaps."
  done
  printf '%s no active ruleset of %s makes main need your approval.%s Fix it in the repo settings under Rules.\n' "$open" "$repo" "${report:- It has no active branch ruleset.}" >&2
  return 1
}

ug_stop_service() {
  local target=$1 i
  launchctl bootout "$target" >/dev/null 2>&1 || true
  for (( i = 0; i < 60; i++ )); do
    launchctl print "$target" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
  printf '%s is still loaded 30 s after launchctl bootout, so its new version cannot load\n' "$target"
  return 1
}

ug_wait() {
  local tries=$1 i
  shift
  for (( i = 0; i < tries; i++ )); do
    "$@" >/dev/null 2>&1 && return 0
    (( i + 1 < tries )) && sleep 0.5
  done
  return 1
}

ug_http_answers() { curl -fsS -o /dev/null --max-time 1 "$1"; }

ug_port_answers() { nc -z -w 1 "$1" "$2"; }

ug_sshd_denies_agent() {
  local agent
  agent=$(ug_fact agent_user) || return 1
  /usr/sbin/sshd -T -f "$1" -o HostKey="$2" -C "user=$agent,host=localhost,addr=127.0.0.1" 2>/dev/null | grep -qix "denyusers $agent"
}

ug_ensure_owner_mode() {
  local file=$1 owner=$2 mode=$3
  [[ $(stat -f '%Su:%Sg %Mp%Lp' "$file") != "$owner $mode" ]] || return 0
  chown "$owner" "$file" && chmod "$mode" "$file" || return 1
  [[ $(stat -f '%Su:%Sg %Mp%Lp' "$file") == "$owner $mode" ]]
}

ug_render() {
  local out=$1 template=$2 shown=$3 key value left unsafe='[|&\\]' facts=()
  shift 3
  while IFS='=' read -r key value || [[ -n $key ]]; do
    [[ -n $key ]] || continue
    [[ ! $value =~ $unsafe ]] || { printf '%s holds %s=%s, which no template can take\n' "$ug_facts_file" "$key" "$value"; return 1; }
    facts+=(-e "s|@$(tr '[:lower:]' '[:upper:]' <<<"$key")@|$value|g")
  done <"$ug_facts_file"
  sed "${facts[@]}" "$@" "$template" >"$out" || { printf 'cannot render %s\n' "$shown"; return 1; }
  left=$(grep -o '@[A-Z_]\{1,\}@' "$out" | head -1) || true
  [[ -z $left ]] || { printf '%s has an unknown placeholder %s\n' "$shown" "$left"; return 1; }
}

ug_ensure_service() {
  local domain=$1 label=$2 rendered=$3 plist=$4 err i
  shift 4
  install -m 644 "$rendered" "$plist" || { printf 'cannot install %s\n' "$plist"; return 1; }
  ug_stop_service "$domain/$label" || return 1
  for (( i = 0; i < 5; i++ )); do
    err=$(launchctl bootstrap "$domain" "$plist" 2>&1) && break
    sleep 1
  done
  (( i < 5 )) || { printf 'launchctl bootstrap of %s failed: %s\n' "$label" "$err"; return 1; }
  ug_wait 60 "$@" || { printf '%s does not answer 30 s after it loaded\n' "$label"; return 1; }
  printf 'restarted, answers\n'
}

ug_pf_refuses_listener() {
  local uid=$1 port=$2
  pfctl -s info 2>/dev/null | grep -q '^Status: Enabled' || return 1
  pfctl -a com.apple/underground -sr 2>/dev/null | grep -qx "block return in quick proto tcp from any to any port = $port user = $uid"
}
