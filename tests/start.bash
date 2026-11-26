# shellcheck shell=bash

start_fixture() {
  ug_mktemp_dir
  st_home=$UG_TMPDIR/home
  st_root=$UG_TMPDIR/root
  st_log='read ~/.local/share/underground/backup/backup.log in the owner account'
  mkdir -p "$st_home" "$st_root/code/bin" "$st_root/status" || fail 'cannot make the fixture dirs'
  printf 'gateway-secret\n' >"$st_root/gateway-token"
  : >"$st_root/code/ug-notices.ts"
  render "$UG_REPO_ROOT/host/agent/agent-start" "$st_root/code/agent-start" \
    AGENT_HOME="$st_home" ROOT="$st_root" USAGE_BROKER_PORT=9 OWNER_DATA=.local/share/underground
  render "$UG_REPO_ROOT/host/agent/agent-env" "$st_root/code/agent-env" \
    AGENT_HOME="$st_home" ROOT="$st_root" USAGE_BROKER_PORT=9
  printf '#!/bin/bash\nprintf %%s "${UG_NOTICES-<unset>}" >%q\n' "$UG_TMPDIR/notices" >"$st_root/code/omp-stub"
  chmod +x "$st_root/code/omp-stub"
  ln -s "$st_root/code/omp-stub" "$st_root/code/bin/omp"
}

st_backup_age() {
  printf '%s\n' $(($(date +%s) - $1)) >"$st_root/status/backup-last" || fail 'cannot write status/backup-last'
}

run_start_notices() {
  rm -f "$UG_TMPDIR/notices"
  (cd "$UG_TMPDIR" && env -i PATH=/usr/bin:/bin GIT_CEILING_DIRECTORIES="$UG_TMPDIR" /bin/bash "$st_root/code/agent-start") >"$UG_TMPDIR/start.out" 2>&1 ||
    fail "agent-start exited non-zero: $(cat "$UG_TMPDIR/start.out")"
  st_notices=$(cat "$UG_TMPDIR/notices" 2>/dev/null) || fail 'agent-start did not call omp'
}

t_5_1() {
  start_fixture
  run_start_notices
  assert_eq "no good backup yet; $st_log" "$st_notices" 'no status/backup-last warns that there is no good backup'
  printf 'garbage\n' >"$st_root/status/backup-last"
  run_start_notices
  assert_eq "no good backup yet; $st_log" "$st_notices" 'a status/backup-last that is not a time warns that there is no good backup'
}

t_5_2() {
  start_fixture
  st_backup_age $((3 * 86400 + 60))
  run_start_notices
  assert_eq "the last good backup is 3 days old; $st_log" "$st_notices" 'a 3-day-old status/backup-last warns with its age'
}

t_5_3() {
  start_fixture
  st_backup_age 3600
  run_start_notices
  assert_eq '' "$st_notices" 'an hour-old status/backup-last gives no notice'
  st_backup_age $((2 * 86400 - 60))
  run_start_notices
  assert_eq '' "$st_notices" 'a status/backup-last just under 2 days old gives no notice'
}
