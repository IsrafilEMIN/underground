# shellcheck shell=bash

# A seam that does not load is a harness error, so return instead of failing:
# a parse error inside the library only shows up here, as a missing function.
# shellcheck disable=SC1091
source "$UG_REPO_ROOT/host/lib/ug.bash" || return 1
[[ $(type -t ug_read_sources) == function ]] || return 1

read_sources() {
  local file=$1 home=$2
  rs_out=$(ug_read_sources "$file" "$home" testtool 2>"$UG_TMPDIR/err")
  rs_rc=$?
  rs_err=$(cat "$UG_TMPDIR/err")
}

src_lines() {
  local format= i
  for ((i = 0; i < $#; i += 2)); do format+='%s\t%s\n'; done
  printf "$format" "$@"
}

src_home() {
  ug_mktemp_dir
  UG_HOME=$UG_TMPDIR/home
  mkdir -p "$UG_HOME"
}

t_1_1() {
  src_home
  cat >"$UG_TMPDIR/sources" <<'EOF'
# sources of the underground host

~/repos/alpha apps/alpha
/Users/ugagent/repos/beta apps/beta
EOF
  read_sources "$UG_TMPDIR/sources" "$UG_HOME"
  assert_eq 0 "$rs_rc" 'a good list is accepted'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha /Users/ugagent/repos/beta apps/beta)" \
    "$rs_out" 'a ~ path and an absolute path print path<TAB>target, comments and blank lines print nothing'
}

t_1_2() {
  local bad=/Users/ugagent/repos/beta
  src_home
  cat >"$UG_TMPDIR/sources" <<EOF
# sources of the underground host
~/repos/alpha apps/alpha
$bad
EOF
  read_sources "$UG_TMPDIR/sources" "$UG_HOME"
  assert_eq 1 "$rs_rc" 'a line with only a repo path is refused'
  assert_contains "$bad" "$rs_err" 'stderr names the line with only a repo path'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the good line before it is streamed'
  cat >"$UG_TMPDIR/control" <<'EOF'
# sources of the underground host
~/repos/alpha apps/alpha
EOF
  read_sources "$UG_TMPDIR/control" "$UG_HOME"
  assert_eq 0 "$rs_rc" 'the same list without the one-field line is accepted'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the same list without the one-field line prints its source'
}

t_1_3() {
  local bad='/Users/ugagent/repos/beta apps/beta third-field'
  src_home
  cat >"$UG_TMPDIR/sources" <<EOF
# sources of the underground host
~/repos/alpha apps/alpha
$bad
EOF
  read_sources "$UG_TMPDIR/sources" "$UG_HOME"
  assert_eq 1 "$rs_rc" 'a line with three fields is refused'
  assert_contains "$bad" "$rs_err" 'stderr names the line with three fields'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the good line before it is streamed'
  cat >"$UG_TMPDIR/control" <<'EOF'
# sources of the underground host
~/repos/alpha apps/alpha
EOF
  read_sources "$UG_TMPDIR/control" "$UG_HOME"
  assert_eq 0 "$rs_rc" 'the same list without the three-field line is accepted'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the same list without the three-field line prints its source'
}

t_1_4() {
  local bad=repos/beta
  src_home
  cat >"$UG_TMPDIR/sources" <<EOF
# sources of the underground host
~/repos/alpha apps/alpha
$bad apps/beta
EOF
  read_sources "$UG_TMPDIR/sources" "$UG_HOME"
  assert_eq 1 "$rs_rc" 'a relative repo path is refused'
  assert_contains "$bad" "$rs_err" 'stderr names the relative repo path'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the good line before it is streamed'
  cat >"$UG_TMPDIR/control" <<'EOF'
# sources of the underground host
~/repos/alpha apps/alpha
EOF
  read_sources "$UG_TMPDIR/control" "$UG_HOME"
  assert_eq 0 "$rs_rc" 'the same list without the relative path is accepted'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the same list without the relative path prints its source'
}

t_1_5() {
  local bad='apps/../secrets'
  src_home
  cat >"$UG_TMPDIR/sources" <<EOF
# sources of the underground host
~/repos/alpha apps/alpha
~/repos/evil $bad
EOF
  read_sources "$UG_TMPDIR/sources" "$UG_HOME"
  assert_eq 1 "$rs_rc" 'a target with a .. component is refused'
  assert_contains "$bad" "$rs_err" 'stderr names the target with a .. component'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the good line before it is streamed'
  cat >"$UG_TMPDIR/control" <<'EOF'
# sources of the underground host
~/repos/alpha apps/alpha
EOF
  read_sources "$UG_TMPDIR/control" "$UG_HOME"
  assert_eq 0 "$rs_rc" 'the same list without the .. target is accepted'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the same list without the .. target prints its source'
}

t_1_6() {
  local bad='apps/./beta'
  src_home
  cat >"$UG_TMPDIR/sources" <<EOF
# sources of the underground host
~/repos/alpha apps/alpha
~/repos/beta $bad
EOF
  read_sources "$UG_TMPDIR/sources" "$UG_HOME"
  assert_eq 1 "$rs_rc" 'a target with a . component is refused'
  assert_contains "$bad" "$rs_err" 'stderr names the target with a . component'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the good line before it is streamed'
  cat >"$UG_TMPDIR/control" <<'EOF'
# sources of the underground host
~/repos/alpha apps/alpha
EOF
  read_sources "$UG_TMPDIR/control" "$UG_HOME"
  assert_eq 0 "$rs_rc" 'the same list without the . target is accepted'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the same list without the . target prints its source'
}

t_1_7() {
  local bad=/srv/beta
  src_home
  cat >"$UG_TMPDIR/sources" <<EOF
# sources of the underground host
~/repos/alpha apps/alpha
~/repos/beta $bad
EOF
  read_sources "$UG_TMPDIR/sources" "$UG_HOME"
  assert_eq 1 "$rs_rc" 'an absolute target is refused'
  assert_contains "$bad" "$rs_err" 'stderr names the absolute target'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the good line before it is streamed'
  cat >"$UG_TMPDIR/control" <<'EOF'
# sources of the underground host
~/repos/alpha apps/alpha
EOF
  read_sources "$UG_TMPDIR/control" "$UG_HOME"
  assert_eq 0 "$rs_rc" 'the same list without the absolute target is accepted'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the same list without the absolute target prints its source'
}

t_1_8() {
  src_home
  cat >"$UG_TMPDIR/sources" <<'EOF'
# sources of the underground host
~/repos/alpha apps/shared
~/repos/beta apps/shared
EOF
  read_sources "$UG_TMPDIR/sources" "$UG_HOME"
  assert_eq 1 "$rs_rc" 'two sources with the same target are refused'
  assert_contains 'apps/shared' "$rs_err" 'stderr names the target two sources share'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/shared)" "$rs_out" 'the first source is streamed before the refusal'
  cat >"$UG_TMPDIR/control" <<'EOF'
# sources of the underground host
~/repos/alpha apps/shared
EOF
  read_sources "$UG_TMPDIR/control" "$UG_HOME"
  assert_eq 0 "$rs_rc" 'the same list without the repeated target is accepted'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/shared)" "$rs_out" 'the same list without the repeated target prints its source'
}

t_1_9() {
  src_home
  cat >"$UG_TMPDIR/sources" <<'EOF'
# sources of the underground host
~/repos/team apps/team
~/repos/extra apps/team/extra
EOF
  read_sources "$UG_TMPDIR/sources" "$UG_HOME"
  assert_eq 1 "$rs_rc" 'a target inside an earlier target is refused'
  assert_contains 'apps/team/extra lies inside apps/team' "$rs_err" 'stderr names the nested target and the target holding it'
  assert_eq "$(src_lines "$UG_HOME/repos/team" apps/team)" "$rs_out" 'the first source is streamed before the refusal'
  cat >"$UG_TMPDIR/control" <<'EOF'
# sources of the underground host
~/repos/team apps/team
EOF
  read_sources "$UG_TMPDIR/control" "$UG_HOME"
  assert_eq 0 "$rs_rc" 'the same list without the nested target is accepted'
  assert_eq "$(src_lines "$UG_HOME/repos/team" apps/team)" "$rs_out" 'the same list without the nested target prints its source'
}

t_1_10() {
  src_home
  cat >"$UG_TMPDIR/sources" <<'EOF'
# sources of the underground host
~/repos/extra apps/team/extra
~/repos/team apps/team
EOF
  read_sources "$UG_TMPDIR/sources" "$UG_HOME"
  assert_eq 1 "$rs_rc" 'a target holding an earlier target is refused'
  assert_contains 'apps/team/extra lies inside apps/team' "$rs_err" 'stderr names the earlier target and the target now holding it'
  assert_eq "$(src_lines "$UG_HOME/repos/extra" apps/team/extra)" "$rs_out" 'the first source is streamed before the refusal'
  cat >"$UG_TMPDIR/control" <<'EOF'
# sources of the underground host
~/repos/extra apps/team/extra
EOF
  read_sources "$UG_TMPDIR/control" "$UG_HOME"
  assert_eq 0 "$rs_rc" 'the same list without the outer target is accepted'
  assert_eq "$(src_lines "$UG_HOME/repos/extra" apps/team/extra)" "$rs_out" 'the same list without the outer target prints its source'
}

t_1_11() {
  local bad='plugin apps/plug'
  src_home
  cat >"$UG_TMPDIR/sources" <<EOF
# sources of the underground host
~/repos/alpha apps/alpha
$bad
EOF
  read_sources "$UG_TMPDIR/sources" "$UG_HOME"
  assert_eq 1 "$rs_rc" 'a plugin line is refused'
  assert_contains "$bad" "$rs_err" 'stderr names the plugin line'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the good line before it is streamed'
  cat >"$UG_TMPDIR/control" <<'EOF'
# sources of the underground host
~/repos/alpha apps/alpha
EOF
  read_sources "$UG_TMPDIR/control" "$UG_HOME"
  assert_eq 0 "$rs_rc" 'the same list without the plugin line is accepted'
  assert_eq "$(src_lines "$UG_HOME/repos/alpha" apps/alpha)" "$rs_out" 'the same list without the plugin line prints its source'
}
