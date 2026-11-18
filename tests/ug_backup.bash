# shellcheck shell=bash

UB_OLD_LAST=1700000000
UB_NEW_LAST=1800000000

ub_fixture() {
  local line pin
  ug_mktemp_dir
  UB_SRC=$UG_TMPDIR/src
  UB_HOME=$UG_TMPDIR/home
  UB_ROOT=$UG_TMPDIR/root
  UB_STATE=$UG_TMPDIR/state
  UB_STUBS=$UG_TMPDIR/stubs
  mkdir -p "$UB_SRC/host/bin" "$UB_ROOT/code/bin" "$UB_STATE" "$UB_STUBS" || fail 'cannot make the fixture dirs'
  cp "$UG_REPO_ROOT/VERSIONS" "$UB_SRC/VERSIONS" &&
    cp "$UG_REPO_ROOT/host/bin/ug-backup" "$UB_SRC/host/bin/ug-backup" &&
    cp -R "$UG_REPO_ROOT/host/lib" "$UB_SRC/host/lib" || fail 'cannot copy ug-backup and its libraries'
  # root= moves to scratch so the agent home reader does not need /Library/Underground.
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == root=* ]] && line="root=$UB_ROOT"
    printf '%s\n' "$line"
  done <"$UG_REPO_ROOT/host/facts" >"$UB_SRC/host/facts" || fail 'cannot write the scratch facts'
  printf '#!/bin/sh\nexit 1\n' >"$UB_ROOT/code/bin/agent-home-tar"

  pin=$(sed -n 's/^restic=//p' "$UB_SRC/VERSIONS")
  [[ -n $pin ]] || fail 'VERSIONS has no restic pin'
  UB_BACKUP=$UB_HOME/.local/share/underground/backup
  UB_RESTIC=$UB_HOME/.local/share/underground/restic/$pin/restic
  mkdir -p "$UB_BACKUP" "${UB_RESTIC%/*}" || fail 'cannot make the data dir'
  printf 'secret\n' >"$UB_BACKUP/password"
  printf 'repo=sftp:ug@backup.local:/srv/ug\n' >"$UB_BACKUP/config"
  printf '%s\n' "$UB_OLD_LAST" >"$UB_BACKUP/last"

  cat >"$UB_RESTIC" <<EOF
#!/bin/sh
shift 2
printf '%s\n' "\$*" >>"$UB_STATE/restic.calls"
rc=0
[ ! -f "$UB_STATE/rc.\$1" ] || rc=\$(cat "$UB_STATE/rc.\$1")
exit "\$rc"
EOF
  cat >"$UB_STUBS/date" <<EOF
#!/bin/sh
case "\$*" in
  +%j) cat "$UB_STATE/day" ;;
  +%s) printf '%s\n' $UB_NEW_LAST ;;
  *) exec /bin/date "\$@" ;;
esac
EOF
  printf '#!/bin/sh\nexit 0\n' >"$UB_STUBS/ssh"
  printf '#!/bin/sh\nexit 1\n' >"$UB_STUBS/sudo"
  chmod +x "$UB_RESTIC" "$UB_STUBS/date" "$UB_STUBS/ssh" "$UB_STUBS/sudo" "$UB_ROOT/code/bin/agent-home-tar"
  printf '001\n' >"$UB_STATE/day"
}

ub_restic_fails() {
  printf '%s\n' "$2" >"$UB_STATE/rc.$1"
}

ub_run() {
  : >"$UB_STATE/restic.calls"
  ub_rc=0
  HOME=$UB_HOME PATH=$UB_STUBS:/usr/bin:/bin "$UB_SRC/host/bin/ug-backup" 2>"$UB_STATE/err" || ub_rc=$?
  ub_err=$(cat "$UB_STATE/err")
  ub_last=$(cat "$UB_BACKUP/last")
}

ub_subcommands() {
  local line words=
  while IFS= read -r line; do
    words+=${words:+ }${line%% *}
  done <"$UB_STATE/restic.calls"
  printf '%s' "$words"
}

ub_check_call() {
  local line
  while IFS= read -r line; do
    [[ $line == check* ]] && printf '%s' "$line"
  done <"$UB_STATE/restic.calls"
}

t_4_1() {
  ub_fixture
  ub_run
  assert_eq 0 "$ub_rc" "a run whose backup and check pass exits 0 ($ub_err)"
  assert_eq "$UB_NEW_LAST" "$ub_last" 'backup/last holds the time of the passing run'
}

t_4_2() {
  ub_fixture
  ub_restic_fails backup 1
  ub_run
  assert_eq 1 "$ub_rc" 'a run whose backup fails exits 1'
  assert_eq 'cat unlock backup backup' "$(ub_subcommands)" 'a failing backup is tried twice and never checked'
  assert_eq "$UB_OLD_LAST" "$ub_last" 'backup/last keeps its old value after a failed backup'
  ub_restic_fails backup 0
  ub_run
  assert_eq 0 "$ub_rc" "the same fixture with a passing backup exits 0 ($ub_err)"
  assert_eq "$UB_NEW_LAST" "$ub_last" 'the same fixture with a passing backup records the run'
}

t_4_3() {
  ub_fixture
  ub_restic_fails check 1
  ub_run
  assert_eq 1 "$ub_rc" 'a run whose check fails exits 1'
  assert_eq 'cat unlock backup check' "$(ub_subcommands)" 'the failing check runs after one passing backup'
  assert_eq "$UB_OLD_LAST" "$ub_last" 'backup/last keeps its old value after a failed check'
  ub_restic_fails check 0
  ub_run
  assert_eq 0 "$ub_rc" "the same fixture with a passing check exits 0 ($ub_err)"
  assert_eq "$UB_NEW_LAST" "$ub_last" 'the same fixture with a passing check records the run'
}

t_4_4() {
  ub_fixture
  ub_restic_fails cat 10
  ub_run
  assert_eq 0 "$ub_rc" "a run on a repo that does not exist yet exits 0 ($ub_err)"
  assert_eq 'cat init unlock backup check' "$(ub_subcommands)" 'cat config exit 10 runs init once, before the backup'
  assert_contains 'made the repo sftp:ug@backup.local:/srv/ug' "$ub_err" 'the log says the repo was made'
}

t_4_5() {
  ub_fixture
  ub_run
  assert_eq 0 "$ub_rc" "the day 001 run exits 0 ($ub_err)"
  assert_eq 'check --read-data-subset=2/100' "$(ub_check_call)" 'day 001 checks data subset 2/100'
  printf '366\n' >"$UB_STATE/day"
  ub_run
  assert_eq 0 "$ub_rc" "the day 366 run exits 0 ($ub_err)"
  assert_eq 'check --read-data-subset=67/100' "$(ub_check_call)" 'day 366 checks data subset 67/100'
}
