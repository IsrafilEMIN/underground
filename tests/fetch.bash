# shellcheck shell=bash

fx_git() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c user.name=ug-test -c user.email=ug-test@example.invalid "$@"
}

fx_commit() {
  fx_git -C "$UG_TMPDIR/seed" commit -q --allow-empty -m "$1" || fail "cannot commit $1 in the seed"
  fx_git -C "$UG_TMPDIR/seed" push -q origin main || fail "cannot push $1 to the origin"
  fx_git -C "$UG_TMPDIR/seed" rev-parse HEAD
}

fetch_fixture() {
  ug_mktemp_dir
  fx_repo=acme/widget
  fx_home=$UG_TMPDIR/home
  fx_root=$UG_TMPDIR/root
  fx_origin=$UG_TMPDIR/origin.git
  fx_clone=$fx_home/work/$fx_repo
  mkdir -p "$fx_home/work/acme" "$fx_root/code/bin" || fail 'cannot make the fixture dirs'
  printf 'gateway-secret\n' >"$fx_root/gateway-token"
  : >"$fx_root/code/ug-notices.ts"
  printf '#!/bin/bash\nprintf %%s "${UG_NOTICES-}" >%q\n' "$UG_TMPDIR/notices" >"$fx_root/code/omp-stub"
  chmod +x "$fx_root/code/omp-stub"
  ln -s "$fx_root/code/omp-stub" "$fx_root/code/bin/omp"
  render "$UG_REPO_ROOT/host/agent/agent-start" "$UG_TMPDIR/agent-start" \
    AGENT_HOME="$fx_home" ROOT="$fx_root" USAGE_BROKER_PORT=9
  fx_git init -q --bare -b main "$fx_origin" || fail 'cannot make the bare origin'
  fx_git init -q -b main "$UG_TMPDIR/seed" || fail 'cannot make the seed repo'
  fx_git -C "$UG_TMPDIR/seed" remote add origin "$fx_origin"
  fx_old=$(fx_commit first)
  fx_git clone -q "$fx_origin" "$fx_clone" || fail 'cannot clone the origin'
  fx_git -C "$fx_clone" checkout -q --detach "$fx_old" || fail 'cannot detach the clone'
  fx_new=$(fx_commit second)
}

fx_head() {
  fx_git -C "$fx_clone" rev-parse HEAD
}

fx_status() {
  local line=
  [[ -f $fx_clone/.git/ug-fetch.status ]] && read -r line <"$fx_clone/.git/ug-fetch.status"
  printf '%s\n' "$line"
}

fx_start() {
  local before= line pid i
  [[ -f $fx_clone/.git/ug-fetch.pid ]] && read -r before <"$fx_clone/.git/ug-fetch.pid"
  UG_REPO=$fx_repo UG_NOTICES= /bin/bash "$UG_TMPDIR/agent-start" >"$UG_TMPDIR/start.out" 2>&1 ||
    fail "agent-start exited non-zero: $(cat "$UG_TMPDIR/start.out")"
  for ((i = 0; i < 300; i++)); do
    line=
    [[ -f $fx_clone/.git/ug-fetch.pid ]] && read -r line <"$fx_clone/.git/ug-fetch.pid"
    [[ $line =~ ^[0-9]+\ [0-9]+$ && $line != "$before" ]] && break
    sleep 0.1
  done
  [[ $line =~ ^[0-9]+\ [0-9]+$ && $line != "$before" ]] || fail 'the background fetch did not start within 30s'
  pid=${line%% *}
  for ((i = 0; i < 300; i++)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  fail 'the background fetch did not finish within 30s'
}

t_7_1() {
  fetch_fixture
  assert_eq "$fx_old" "$(fx_head)" 'the clone starts at the first commit'
  fx_start
  assert_eq "$fx_new" "$(fx_head)" 'HEAD moves to the commit pushed to origin'
  assert_eq ok "$(fx_status | cut -d' ' -f1)" 'the fetch status is ok'
}

t_7_2() {
  fetch_fixture
  fx_git -C "$fx_clone" fetch -q origin || fail 'cannot prefetch the second commit'
  fx_git -C "$fx_clone" remote set-url origin "$UG_TMPDIR/no-such-origin.git"
  fx_start
  assert_eq failed "$(fx_status | cut -d' ' -f1)" 'a fetch from a missing origin has status failed'
  assert_eq "$fx_old" "$(fx_head)" 'HEAD stays put after a failed fetch'
  assert_eq '' "$(cat "$UG_TMPDIR/notices")" 'the start that ran the failing fetch shows no warning'
  fx_start
  local notices
  notices=$(cat "$UG_TMPDIR/notices")
  assert_eq 1 "$(printf '%s\n' "$notices" | wc -l | tr -d ' ')" 'the next start shows exactly one warning'
  assert_contains "the last background fetch of $fx_repo failed: " "$notices" 'the warning names the failed fetch'
  assert_eq "$fx_old" "$(fx_head)" 'HEAD stays put after the second failed fetch'
  fx_git -C "$fx_clone" remote set-url origin "$fx_origin"
  fx_start
  assert_eq ok "$(fx_status | cut -d' ' -f1)" 'the same clone with its real origin fetches ok'
  assert_eq "$fx_new" "$(fx_head)" 'the same clone with its real origin moves HEAD'
}

t_7_3() {
  local holder i
  fetch_fixture
  printf 'ok 1000\n' >"$fx_clone/.git/ug-fetch.status"
  /usr/bin/lockf -k "$fx_clone/.git/ug-sync.lock" /bin/bash -c \
    ': >"$1"; for ((i = 0; i < 600; i++)); do [[ -e $2 ]] && exit 0; sleep 0.1; done' _ "$UG_TMPDIR/held" "$UG_TMPDIR/release" >/dev/null 2>&1 &
  holder=$!
  for ((i = 0; i < 100; i++)); do
    [[ -e $UG_TMPDIR/held ]] && break
    sleep 0.1
  done
  [[ -e $UG_TMPDIR/held ]] || fail 'the lock holder did not take the lock'
  fx_start
  : >"$UG_TMPDIR/release"
  wait "$holder"
  assert_eq "$fx_old" "$(fx_head)" 'HEAD stays put while another fetch holds the lock'
  assert_eq 'ok 1000' "$(fx_status)" 'the status is left as it was'
  assert_contains 'skipped: another fetch holds the lock' "$(cat "$fx_clone/.git/ug-fetch.log")" 'the log says the fetch was skipped'
  fx_start
  assert_eq "$fx_new" "$(fx_head)" 'the same clone without the lock held moves HEAD'
}

t_7_4() {
  local mid
  fetch_fixture
  printf 'one\n' >"$UG_TMPDIR/seed/file"
  fx_git -C "$UG_TMPDIR/seed" add file || fail 'cannot stage the file in the seed'
  mid=$(fx_commit 'add file')
  fx_git -C "$fx_clone" fetch -q origin || fail 'cannot fetch the file commit'
  fx_git -C "$fx_clone" checkout -q --detach "$mid" || fail 'cannot detach the clone at the file commit'
  fx_new=$(fx_commit third)
  printf 'staged\n' >"$fx_clone/file"
  fx_git -C "$fx_clone" add file || fail 'cannot stage the change in the clone'
  printf 'live\n' >"$fx_clone/file"
  [[ -n $(fx_git -C "$fx_clone" status --porcelain) ]] || fail 'the clone does not start dirty'
  fx_start
  assert_eq "$fx_new" "$(fx_head)" 'HEAD moves to the commit pushed to origin'
  assert_eq '' "$(fx_git -C "$fx_clone" status --porcelain)" 'the index and files match the new HEAD'
}
