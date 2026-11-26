# shellcheck shell=bash

ug_services_file=${BASH_SOURCE[0]%/*}/../services

ug_services() {
  local want=${1:-} label name scope user template health log watch
  while IFS='|' read -r label name scope user template health log watch || [[ -n $label ]]; do
    [[ -n $label && $label != \#* ]] || continue
    [[ -z $want || $scope == "$want" ]] || continue
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$label" "$name" "$scope" "$user" "$template" "$health" "$log" "$watch"
  done <"$ug_services_file"
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
  ug_probe_hint="sudo launchctl print $domain/$label"
  [[ $scope == daemon ]] || ug_probe_hint="launchctl print $domain/$label"
  case $scope:$kind in
    *:http) ug_probe=(ug_http_answers "$target") ;;
    *:port) ug_probe=(ug_port_answers "${target%:*}" "${target##*:}") ;;
    *:launchd) ug_probe=(launchctl print "$domain/$label") ;;
    daemon:udp) ug_probe=(ug_udp_held "$target") ;;
    daemon:pf)
      agent=$(ug_fact agent_user) || return 1
      ug_probe=(ug_pf_refuses_listener "$(id -u "$agent")" "$target")
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

ug_udp_held() { lsof -nP -t -iUDP@"$1" >/dev/null; }

ug_sshd_denies_agent() {
  local agent
  agent=$(ug_fact agent_user) || return 1
  /usr/sbin/sshd -T -f "$1" -o HostKey="$2" -C "user=$agent,host=localhost,addr=127.0.0.1" 2>/dev/null | grep -qix "denyusers $agent"
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

ug_code_sum() {
  local paths path
  read -r -a paths <<<"$1"
  for path in "${paths[@]}"; do
    [[ -e $path ]] || return 1
  done
  find "${paths[@]}" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d ' ' -f 1
}

ug_ensure_service() {
  local domain=$1 label=$2 rendered=$3 plist=$4 watch=$5 sum err i
  shift 5
  if [[ -n $watch ]]; then
    sum=$(ug_code_sum "$watch") || { printf 'cannot read %s, which %s runs\n' "$watch" "$label"; return 1; }
    printf '<!-- code sha256 %s -->\n' "$sum" >>"$rendered"
  fi
  if cmp -s "$rendered" "$plist" && launchctl print "$domain/$label" >/dev/null 2>&1 && "$@" >/dev/null 2>&1; then
    printf 'unchanged, healthy\n'
    return 0
  fi
  install -m 644 "$rendered" "$plist" || { printf 'cannot install %s\n' "$plist"; return 1; }
  ug_stop_service "$domain/$label" || return 1
  for (( i = 0; i < 5; i++ )); do
    err=$(launchctl bootstrap "$domain" "$plist" 2>&1) && break
    sleep 1
  done
  (( i < 5 )) || { printf 'launchctl bootstrap of %s failed: %s\n' "$label" "$err"; return 1; }
  ug_wait 60 "$@" || { printf '%s does not answer 30 s after it loaded\n' "$label"; return 1; }
  printf 'restarted, healthy\n'
}

ug_pf_refuses_listener() {
  local uid=$1 port=$2
  pfctl -s info 2>/dev/null | grep -q '^Status: Enabled' || return 1
  pfctl -a com.apple/underground -sr 2>/dev/null | grep -qx "block return in quick proto tcp from any to any port = $port user = $uid"
}
