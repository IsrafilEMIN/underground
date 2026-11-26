# shellcheck shell=bash

us_git() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c user.name=ug-test -c user.email=ug-test@example.invalid "$@"
}

us_fixture() {
  local line
  ug_mktemp_dir
  US_SRC=$UG_TMPDIR/src
  US_HOME=$UG_TMPDIR/home
  US_ROOT=$UG_TMPDIR/root
  US_AGENT=$UG_TMPDIR/agent
  US_STUBS=$UG_TMPDIR/stubs
  US_SOURCES=$US_HOME/.local/share/underground/sources
  mkdir -p "$US_SRC/host/bin" "$US_ROOT/code/bin" "$US_AGENT" "$US_STUBS" "${US_SOURCES%/*}" || fail 'cannot make the fixture dirs'
  cp "$UG_REPO_ROOT/host/bin/ug-sync" "$US_SRC/host/bin/ug-sync" &&
    cp -R "$UG_REPO_ROOT/host/lib" "$US_SRC/host/lib" || fail 'cannot copy ug-sync and its libraries'
  # root= moves to scratch so the unpack helper is a stub.
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == root=* ]] && line="root=$US_ROOT"
    printf '%s\n' "$line"
  done <"$UG_REPO_ROOT/host/facts" >"$US_SRC/host/facts" || fail 'cannot write the scratch facts'
  # sudo -n -u <agent> <unpack> <target>: record the user, run the helper as this user.
  cat >"$US_STUBS/sudo" <<EOF
#!/bin/sh
[ "\$1" = -n ] && [ "\$2" = -u ] || exit 1
printf '%s\n' "\$3" >>"$UG_TMPDIR/sudo.users"
shift 3
exec "\$@"
EOF
  cat >"$US_ROOT/code/bin/agent-unpack" <<EOF
#!/bin/sh
mkdir -p "$US_AGENT/\$1" && tar -xf - -C "$US_AGENT/\$1"
EOF
  chmod +x "$US_STUBS/sudo" "$US_ROOT/code/bin/agent-unpack"
}

us_repo() {
  local repo=$US_HOME/repos/alpha
  mkdir -p "$repo" || fail 'cannot make the source repo'
  printf 'committed\n' >"$repo/a.txt"
  us_git -C "$repo" init -q -b main && us_git -C "$repo" add a.txt && us_git -C "$repo" commit -q -m one ||
    fail 'cannot commit in the source repo'
  printf 'uncommitted\n' >"$repo/a.txt"
}

us_run() {
  us_rc=0
  HOME=$US_HOME PATH=$US_STUBS:/usr/bin:/bin "$US_SRC/host/bin/ug-sync" 2>"$UG_TMPDIR/err" || us_rc=$?
  us_err=$(cat "$UG_TMPDIR/err")
}

t_6_1() {
  us_fixture
  us_repo
  cat >"$US_SOURCES" <<'EOF'
~/repos/alpha apps/alpha
EOF
  us_run
  assert_eq 0 "$us_rc" "ug-sync with one good source exits 0 ($us_err)"
  assert_eq committed "$(cat "$US_AGENT/apps/alpha/a.txt" 2>/dev/null)" 'the agent target holds the committed file, not the working copy'
  assert_eq ugagent "$(cat "$UG_TMPDIR/sudo.users")" 'the unpack helper runs once, as the agent user'
  assert_contains 'ug-sync: synced ugagent:apps/alpha' "$us_err" 'the log names the synced target'
}

t_6_2() {
  us_fixture
  us_run
  assert_eq 1 "$us_rc" 'ug-sync with no sources file exits 1'
  assert_contains "no $US_SOURCES; run host/bin/ug-setup" "$us_err" 'the log names the missing sources file'
  assert_eq no "$([[ -e $UG_TMPDIR/sudo.users ]] && echo yes || echo no)" 'nothing is unpacked'
  : >"$US_SOURCES"
  us_run
  assert_eq 0 "$us_rc" "the same fixture with an empty sources file exits 0 ($us_err)"
}
