# shellcheck shell=bash

UG_REPO_ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)

UG_TEST_ID=${UG_TEST_ID:-}

UG_TMPDIRS=()
UG_TMPDIR=

fail() {
  printf 'ASSERT-FAILED %s: %s\n' "${UG_TEST_ID:-?}" "$1"
  exit 1
}

ug_mktemp_dir() {
  local base=${TMPDIR:-/tmp}
  base=${base%/}
  UG_TMPDIR=$(mktemp -d "$base/underground-test.XXXXXX") || fail 'cannot create a temp dir'
  UG_TMPDIRS+=("$UG_TMPDIR")
}

assert_eq() {
  local expected=$1 actual=$2 what=$3
  [[ $expected == "$actual" ]] ||
    fail "$what: expected [$expected] got [$actual]"
}

assert_contains() {
  local needle=$1 haystack=$2 what=$3
  [[ $haystack == *"$needle"* ]] ||
    fail "$what: [$haystack] does not contain [$needle]"
}

assert_exit() {
  local want=$1 what=$2 got=0
  shift 2
  [[ ${1:-} == -- ]] || fail "assert_exit: missing -- before the command for: $what"
  shift
  "$@" >/dev/null 2>&1 || got=$?
  [[ $got == "$want" ]] || fail "$what: exit $got, expected $want"
}

_ug_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    sha256sum | cut -d' ' -f1
  fi
}

tree_digest() {
  local dir=$1
  [[ -d $dir ]] || fail "tree_digest: not a directory: $dir"
  (
    cd "$dir" || exit 1
    find . -print | LC_ALL=C sort | while IFS= read -r p; do
      if [[ -L $p ]]; then
        printf 'l %s %s\n' "$(readlink "$p")" "${p#./}"
      elif [[ -d $p ]]; then
        printf 'd %s\n' "${p#./}"
      else
        printf 'f %s %s\n' "$( _ug_sha256 < "$p")" "${p#./}"
      fi
    done
  )
}

render() {
  local template=$1 out=$2
  shift 2
  local text kv name value
  [[ -f $template ]] || fail "render: no template: $template"
  text=$({ cat -- "$template" && printf x; }) || fail "render: cannot read $template"
  text=${text%x}
  while (($#)); do
    kv=$1
    shift
    name=${kv%%=*}
    value=${kv#*=}
    text=${text//@$name@/$value}
  done
  printf '%s' "$text" > "$out" || fail "render: cannot write $out"
}

# Define the tests of every tests/<seam>.bash in the calling shell. Must not be
# called inside a command substitution, or the functions die with the subshell.
ug_load_tests() {
  local file
  for file in "${BASH_SOURCE[0]%/*}"/*.bash; do
    [[ -f $file && ${file##*/} != lib.bash ]] || continue
    # shellcheck disable=SC1090
    source "$file" || return 1
  done
}

ug_test_ids() {
  local fn
  for fn in $(declare -F | cut -d' ' -f3 | LC_ALL=C sort); do
    [[ $fn == t_* ]] || continue
    printf '%s\n' "${fn#t_}" | tr '_' '.'
  done
}
