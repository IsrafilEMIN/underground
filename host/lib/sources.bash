# shellcheck shell=bash

ug_expand_home() {
  case $1 in
    '~') printf '%s\n' "$2" ;;
    '~/'*) printf '%s\n' "$2/${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

ug_read_sources() {
  local file=$1 home=$2 tool=$3
  local target_re='^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$'
  local line path target extra prev n
  local -a targets=()
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n $line && $line != '#'* ]] || continue
    read -r path target extra <<<"$line"
    [[ -n $path ]] || continue
    [[ $path != plugin ]] ||
      { ug_err "$tool" "in $file: \"$line\": plugins are not sources; they come from omp's own github marketplace"; return 1; }
    [[ -n $target && -z $extra ]] ||
      { ug_err "$tool" "in $file: \"$line\": a source is a repo path and a target, and nothing else"; return 1; }
    path=$(ug_expand_home "$path" "$home")
    [[ $path == /* ]] ||
      { ug_err "$tool" "in $file: $path is not an absolute path or a ~ path"; return 1; }
    [[ $target =~ $target_re ]] ||
      { ug_err "$tool" "in $file: target $target is not a plain relative path"; return 1; }
    case /$target/ in
      */./*|*/../*) ug_err "$tool" "in $file: target $target has a . or .. component"; return 1 ;;
    esac
    for (( n=0; n<${#targets[@]}; n++ )); do
      prev=${targets[n]}
      [[ $target != "$prev" ]] ||
        { ug_err "$tool" "in $file: two sources share the target $target"; return 1; }
      case $target in
        "$prev"/*) ug_err "$tool" "in $file: target $target lies inside $prev"; return 1 ;;
      esac
      case $prev in
        "$target"/*) ug_err "$tool" "in $file: target $prev lies inside $target"; return 1 ;;
      esac
    done
    targets+=("$target")
    printf '%s\t%s\n' "$path" "$target"
  done <"$file"
}

ug_sync_sources() {
  local sources=$1 owner_home=$2 agent=$3 unpack=$4 tool=$5
  local -a paths=() targets=() pids=()
  local pairs path target n failed=0
  pairs=$(ug_read_sources "$sources" "$owner_home" "$tool") || return 1
  while IFS=$'\t' read -r path target; do
    [[ -n $path ]] || continue
    paths+=("$path") targets+=("$target")
  done <<<"$pairs"
  for (( n=0; n<${#paths[@]}; n++ )); do
    ( cd / && git -C "${paths[n]}" archive --format=tar HEAD | sudo -n -u "$agent" "$unpack" "${targets[n]}" ) &
    pids+=($!)
  done
  for (( n=0; n<${#pids[@]}; n++ )); do
    if wait "${pids[n]}"; then
      printf '%s\n' "${targets[n]}"
    else
      ug_err "$tool" "cannot sync ${paths[n]} to $agent:${targets[n]}; is it a git repository with a HEAD commit, and did host/bin/ug-setup grant the unpack helper?"
      failed=1
    fi
  done
  return $failed
}
