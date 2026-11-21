# shellcheck shell=bash

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
    ug_say same checkout "main at origin/main ${after:0:7}"
  else
    ug_say changed checkout "pulled main ${before:0:7} → ${after:0:7}"
  fi
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

ug_check_codeowners() {
  local text=$1 login=$2 where=$3 open=${4:-} line="" pattern="" owners="" star=0
  while read -r pattern owners || [[ -n $pattern ]]; do
    [[ -n $pattern && $pattern != \#* ]] || continue
    [[ $owners == "@$login" ]] || { printf '%s%s gives "%s" to "%s"; each line must name only @%s\n' "$open" "$where" "$pattern" "$owners" "$login" >&2; return 1; }
    [[ $pattern != "*" ]] || star=1
  done <<<"$text"
  [[ $star == 1 ]] || { printf '%s%s has no line "* @%s", so some files need no approval\n' "$open" "$where" "$login" >&2; return 1; }
}

ug_ruleset_id=""
ug_check_rulesets() {
  local repo=$1 open=${2:-} ids id json gaps report=""
  ids=$(gh api "repos/$repo/rulesets?per_page=100" | jq -r '.[] | select(.enforcement == "active" and .target == "branch") | .id') || { printf '%scannot read the rulesets of %s from GitHub\n' "$open" "$repo" >&2; return 1; }
  for id in $ids; do
    json=$(gh api "repos/$repo/rulesets/$id") || { printf '%scannot read ruleset %s of %s from GitHub\n' "$open" "$id" "$repo" >&2; return 1; }
    gaps=$(jq -r "$ug_main_rule_gaps" <<<"$json") || { printf '%scannot read ruleset %s of %s: GitHub sent no ruleset\n' "$open" "$id" "$repo" >&2; return 1; }
    [[ -n $gaps ]] || { ug_ruleset_id=$id; return 0; }
    report+=" Ruleset $id: $gaps."
  done
  printf '%sno active ruleset of %s makes main need your approval.%s Fix it in the repo settings under Rules.\n' "$open" "$repo" "${report:- It has no active branch ruleset.}" >&2
  return 1
}

ug_check_main_rule() {
  local src=$1 tool=$2 repo login name file=""
  local open="$tool: a wall is open, so setup pulled nothing and changed nothing: "
  repo=$(ug_repo_slug "$src") || { printf '%sthe origin of %s is not a GitHub repo, so setup cannot check the rule on main\n' "$open" "$src" >&2; return 1; }
  for name in gh jq; do
    command -v "$name" >/dev/null || { printf '%ssetup needs %s to check the rule on main of %s\n' "$open" "$name" "$repo" >&2; return 1; }
  done
  login=$(gh api user | jq -r '.login // empty') || login=""
  [[ -n $login ]] || { printf '%sgh has no GitHub login; run: gh auth login\n' "$open" >&2; return 1; }

  for name in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
    [[ ! -f $src/$name ]] || { file=$src/$name; break; }
  done
  [[ -n $file ]] || { printf '%sthe checkout has no CODEOWNERS file, so no file needs your approval\n' "$open" >&2; return 1; }
  ug_check_codeowners "$(cat "$file")" "$login" "$file" "$open" || return 1

  ug_check_rulesets "$repo" "$open" || return 1
  ug_check_required_tests "$repo" "$open" || return 1
  ug_say same "main rule" "$repo needs @$login approval and green tests (ruleset $ug_ruleset_id)"
}

ug_check_required_tests() {
  local repo=$1 open=$2 ids id required
  ids=$(gh api "repos/$repo/rulesets?per_page=100" | jq -r '.[] | select(.enforcement == "active" and .target == "branch") | .id') ||
    { printf '%scannot read the rulesets of %s from GitHub\n' "$open" "$repo" >&2; return 1; }
  for id in $ids; do
    required=$(gh api "repos/$repo/rulesets/$id" | jq -r '
      select((.conditions.ref_name.include // []) | any(. == "~DEFAULT_BRANCH" or . == "refs/heads/main"))
      | .rules[]? | select(.type == "required_status_checks")
      | .parameters.required_status_checks[]?.context') ||
      { printf '%scannot read ruleset %s of %s from GitHub\n' "$open" "$id" "$repo" >&2; return 1; }
    grep -qxF tests <<<"$required" && return 0
  done
  printf '%sno active ruleset of %s requires the check "tests" on main, so a pull request with failing tests can merge. Add it in the repo settings under Rules: Require status checks to pass, check "tests".\n' "$open" "$repo" >&2
  return 1
}

ug_check_repo_rule() {
  local repo=$1 login=$2 name text="" where=""
  for name in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
    if text=$(gh api "repos/$repo/contents/$name" --jq .content 2>/dev/null | base64 -d 2>/dev/null); then
      where="the CODEOWNERS of $repo"
      break
    fi
  done
  [[ -n $where ]] || { printf '%s has no CODEOWNERS file, so no file needs your approval\n' "$repo" >&2; return 1; }
  ug_check_codeowners "$text" "$login" "$where" || return 1
  ug_check_rulesets "$repo"
}
