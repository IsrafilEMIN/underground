# shellcheck shell=bash

ug_pin_checked() {
  local file=$1 key=$2 re=$3 tool=$4 value
  value=$(ug_pin "$file" "$key") || true
  [[ $value =~ $re ]] || ug_die "$tool" "bad pin for $key in $file"
  printf '%s\n' "$value"
}

ug_sha256() {
  local out
  out=$(shasum -a 256 "$1") || return 1
  printf '%s\n' "${out%% *}"
}

ug_fetch_pinned() {
  local url=$1 want=$2 dest=$3 tool=$4
  local name=${dest##*/} dir=${dest%/*} tmp have
  if [[ -f $dest && ! -L $dest ]] && [[ $(ug_sha256 "$dest") == "$want" ]]; then
    ug_say same "$name" "in place"
    return 0
  fi
  [[ -d $dir ]] || install -d "$dir" ||
    { ug_err "$tool" "cannot create $dir to hold $dest"; return 1; }
  tmp=$(mktemp "$dir/.$name.XXXXXX") ||
    { ug_err "$tool" "cannot make a temp file in $dir to receive $url"; return 1; }
  if ! curl -fsSL --proto '=https' --retry 3 -o "$tmp" "$url"; then
    rm -f "$tmp"
    ug_err "$tool" "download of $url failed"
    return 1
  fi
  if ! have=$(ug_sha256 "$tmp"); then
    rm -f "$tmp"
    ug_err "$tool" "cannot checksum the download of $url"
    return 1
  fi
  if [[ $have != "$want" ]]; then
    rm -f "$tmp"
    ug_err "$tool" "$url has SHA-256 $have, want $want; nothing changed"
    return 1
  fi
  if ! mv -f "$tmp" "$dest"; then
    rm -f "$tmp"
    ug_err "$tool" "cannot move the checked download into $dest; nothing changed"
    return 1
  fi
  ug_say changed "$name" "downloaded and checked"
}
