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
    cyan) printf '\e[36m' ;;
    off) printf '\e[0m' ;;
    *) printf 'ug_paint: unknown color %s\n' "$2" >&2; return 1 ;;
  esac
}

ug_home=$HOME

ug_short() {
  local text=$1
  [[ -z $ug_home || $ug_home == / ]] || text=${text//"$ug_home"/\~}
  printf '%s' "$text"
}

ug_step() {
  printf '\n%s%s▸ %s%s\n' "$(ug_paint 1 bold)" "$(ug_paint 1 cyan)" "$1" "$(ug_paint 1 off)"
}

ug_say() {
  local kind=$1 subject text mark color
  subject=$(ug_short "$2")
  text=$(ug_short "$3")
  case $kind in
    same) mark='·' color=dim ;;
    changed) mark='✓' color=green ;;
    ok) mark='•' color='' ;;
    warn) mark='!' color=yellow ;;
    *) printf 'ug_say: unknown kind %s\n' "$kind" >&2; return 1 ;;
  esac
  if [[ $kind == same ]]; then
    printf '  %s%s %-24s %s%s\n' "$(ug_paint 1 dim)" "$mark" "$subject" "$text" "$(ug_paint 1 off)"
  else
    printf '  %s%s%s %s%-24s%s %s%s%s\n' "${color:+$(ug_paint 1 "$color")}" "$mark" "$(ug_paint 1 off)" \
      "$(ug_paint 1 bold)" "$subject" "$(ug_paint 1 off)" "${color:+$(ug_paint 1 "$color")}" "$text" "$(ug_paint 1 off)"
  fi
}

ug_pin() { sed -n "s/^$2=//p" "$1"; }

ug_facts_file=${BASH_SOURCE[0]%/*}/../facts

ug_fact() {
  local value
  value=$(ug_pin "$ug_facts_file" "$1") || return 1
  [[ -n $value ]] || { printf 'ug_fact: %s has no %s\n' "$ug_facts_file" "$1" >&2; return 1; }
  printf '%s\n' "$value"
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

ug_repo_slug() {
  local top=$1 url re='^(git@github\.com:|ssh://git@github\.com/|https://github\.com/)([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$'
  url=$(git -C "$top" config --get remote.origin.url 2>/dev/null) || true
  url=${url%/}
  url=${url%.git}
  [[ $url =~ $re ]] || return 1
  echo "${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
}
