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
  # git reports the physical cwd, and agent-start compares it with $HOME/work.
  UG_TMPDIR=$(cd "$UG_TMPDIR" && pwd -P) || fail 'cannot resolve the temp dir'
  fx_repo=acme/widget
  fx_home=$UG_TMPDIR/home
  fx_root=$UG_TMPDIR/root
  fx_origin=$UG_TMPDIR/gh/$fx_repo.git
  fx_clone=$fx_home/work/$fx_repo
  mkdir -p "$fx_home/work/acme" "$fx_root/code/bin" "$fx_root/status" "$UG_TMPDIR/gh/acme" || fail 'cannot make the fixture dirs'
  printf 'gateway-secret\n' >"$fx_root/gateway-token"
  date +%s >"$fx_root/status/backup-last"
  : >"$fx_root/code/ug-notices.ts"
  printf '#!/bin/bash\npwd -P >%q\nprintf %%s "${UG_NOTICES-}" >%q\n' "$UG_TMPDIR/omp.cwd" "$UG_TMPDIR/notices" >"$fx_root/code/omp-stub"
  chmod +x "$fx_root/code/omp-stub"
  ln -s "$fx_root/code/omp-stub" "$fx_root/code/bin/omp"
  printf '#!/bin/bash\n[[ ! -f %q ]] || cat %q\n' "$UG_TMPDIR/open-prs" "$UG_TMPDIR/open-prs" >"$fx_root/code/bin/gh"
  chmod +x "$fx_root/code/bin/gh"
  render "$UG_REPO_ROOT/host/agent/agent-start" "$UG_TMPDIR/agent-start" \
    AGENT_HOME="$fx_home" ROOT="$fx_root" USAGE_BROKER_PORT=9 OWNER_DATA=.local/share/underground
  render "$UG_REPO_ROOT/host/agent/agent-env" "$fx_root/code/agent-env" \
    AGENT_HOME="$fx_home" ROOT="$fx_root" USAGE_BROKER_PORT=9
  fx_git init -q --bare -b main "$fx_origin" || fail 'cannot make the bare origin'
  fx_git init -q -b main "$UG_TMPDIR/seed" || fail 'cannot make the seed repo'
  fx_git -C "$UG_TMPDIR/seed" remote add origin "$fx_origin"
  fx_old=$(fx_commit first)
  fx_git clone -q "$fx_origin" "$fx_clone" || fail 'cannot clone the origin'
  # The clone names its GitHub origin, and git fetches it from the bare repo.
  fx_git -C "$fx_clone" remote set-url origin "https://github.com/$fx_repo.git" || fail 'cannot set the GitHub origin'
  fx_git -C "$fx_clone" config "url.$UG_TMPDIR/gh/.insteadOf" https://github.com/ || fail 'cannot map GitHub to the bare repo'
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

fx_age() {
  touch -t 202001010000 "$@" || fail "cannot age $*"
}

fx_worktree() {
  local name=$1 start=$2
  fx_git -C "$fx_clone" worktree add -q -b "$name" "$UG_TMPDIR/$name" "$start" || fail "cannot add the worktree $name"
}

fx_age_worktree() {
  local name=$1 gitdir=$fx_clone/.git/worktrees/$1
  fx_age "$gitdir/HEAD" "$gitdir/index" "$gitdir/logs/HEAD" "$fx_clone/.git/logs/refs/heads/$name"
}

fx_has_ref() {
  fx_git --git-dir="$1" show-ref --verify --quiet "$2"
}

fx_unique_commit() {
  local name=$1 parent=${2:-HEAD} blob tree
  blob=$(printf '%s\n' "$name" | fx_git -C "$UG_TMPDIR/seed" hash-object -w --stdin) || fail "cannot store the blob $name"
  tree=$(printf '100644 blob %s\t%s\n' "$blob" "$name" | fx_git -C "$UG_TMPDIR/seed" mktree) || fail "cannot make the tree $name"
  fx_git -C "$UG_TMPDIR/seed" commit-tree -p "$parent" -m "$name" "$tree" || fail "cannot make the side commit $name"
}

fx_run_start() {
  (cd "${1:-$fx_clone}" && /bin/bash "$UG_TMPDIR/agent-start") >"$UG_TMPDIR/start.out" 2>&1 ||
    fail "agent-start exited non-zero: $(cat "$UG_TMPDIR/start.out")"
}

# Start agent-start in the folder $1 (default: the main checkout) and wait for its background sync.
fx_start() {
  local before= line pid i
  [[ -f $fx_clone/.git/ug-fetch.pid ]] && read -r before <"$fx_clone/.git/ug-fetch.pid"
  fx_run_start "$@"
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
  mv "$fx_origin" "$fx_origin.away" || fail 'cannot hide the origin'
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
  mv "$fx_origin.away" "$fx_origin" || fail 'cannot restore the origin'
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
  printf 'two\n' >"$UG_TMPDIR/seed/file"
  fx_git -C "$UG_TMPDIR/seed" add file || fail 'cannot stage the new file in the seed'
  fx_new=$(fx_commit 'change file')
  fx_start
  assert_eq "$fx_new" "$(fx_head)" 'HEAD moves to the commit pushed to origin'
  assert_eq two "$(cat "$fx_clone/file")" 'the file holds its content at the new HEAD'
  assert_eq '' "$(fx_git -C "$fx_clone" status --porcelain)" 'the index and files match the new HEAD'
}

t_7_5() {
  fetch_fixture
  fx_worktree old "$fx_old"
  fx_worktree fresh "$fx_old"
  fx_git -C "$fx_clone" branch stale "$fx_old" || fail 'cannot make the stale branch'
  fx_age_worktree old
  fx_age "$fx_clone/.git/logs/refs/heads/stale" "$fx_clone/.git/logs/refs/heads/main"
  fx_start
  assert_eq no "$([[ -e $UG_TMPDIR/old ]] && echo yes || echo no)" 'an idle worktree at a commit in origin/main is removed'
  assert_eq no "$(fx_has_ref "$fx_clone/.git" refs/heads/old && echo yes || echo no)" 'the branch of the removed worktree is deleted'
  assert_eq no "$(fx_has_ref "$fx_clone/.git" refs/heads/stale && echo yes || echo no)" 'an idle branch in origin/main is deleted'
  assert_eq yes "$([[ -d $UG_TMPDIR/fresh ]] && echo yes || echo no)" 'a worktree used in the last 3 days stays'
  assert_eq yes "$(fx_has_ref "$fx_clone/.git" refs/heads/main && echo yes || echo no)" 'the default branch stays'
  assert_eq "$fx_new" "$(fx_head)" 'the main checkout stays at origin/main'
}

t_7_6() {
  fetch_fixture
  fx_worktree uniq "$fx_old"
  printf 'only here\n' >"$UG_TMPDIR/uniq/u"
  fx_git -C "$UG_TMPDIR/uniq" add u || fail 'cannot stage the unique file'
  fx_git -C "$UG_TMPDIR/uniq" commit -q -m unique || fail 'cannot commit the unique file'
  fx_git -C "$fx_clone" branch lone uniq || fail 'cannot make the lone branch'
  fx_age_worktree uniq
  fx_age "$fx_clone/.git/logs/refs/heads/lone"
  fx_start
  assert_eq yes "$([[ -f $UG_TMPDIR/uniq/u ]] && echo yes || echo no)" 'a worktree with a commit that GitHub does not hold stays'
  assert_eq yes "$(fx_has_ref "$fx_clone/.git" refs/heads/lone && echo yes || echo no)" 'a branch with a commit that GitHub does not hold stays'
  fx_start
  local notices
  notices=$(cat "$UG_TMPDIR/notices")
  assert_contains "cleanup of $fx_repo kept 2 items" "$notices" 'the next start names the kept items'
  assert_contains "$UG_TMPDIR/uniq" "$notices" 'the notice names the kept worktree'
  assert_contains ' lone' "$notices" 'the notice names the kept branch'
}

t_7_7() {
  fetch_fixture
  printf 'same\n' >"$UG_TMPDIR/seed/f"
  printf 'also\n' >"$UG_TMPDIR/seed/g"
  fx_git -C "$UG_TMPDIR/seed" add f g || fail 'cannot stage f and g in the seed'
  fx_new=$(fx_commit 'add f and g')
  local name
  for name in twin near; do
    fx_worktree "$name" "$fx_old"
    printf 'same\n' >"$UG_TMPDIR/$name/f"
    fx_git -C "$UG_TMPDIR/$name" add f || fail "cannot stage f in $name"
    fx_git -C "$UG_TMPDIR/$name" commit -q -m "$name adds f" || fail "cannot commit f in $name"
    fx_age_worktree "$name"
  done
  printf 'also\n' >"$UG_TMPDIR/twin/g"
  printf 'other\n' >"$UG_TMPDIR/near/g"
  fx_age "$fx_clone/.git/worktrees/twin/index" "$fx_clone/.git/worktrees/near/index"
  fx_start
  assert_eq no "$([[ -e $UG_TMPDIR/twin ]] && echo yes || echo no)" 'a worktree whose commit and untracked file match origin/main is removed'
  assert_eq yes "$([[ -f $UG_TMPDIR/near/g ]] && echo yes || echo no)" 'a worktree with an untracked file that differs from origin/main stays'
}

t_7_8() {
  local closed early open_head
  fetch_fixture
  closed=$(fx_unique_commit closed)
  early=$(fx_unique_commit early)
  open_head=$(fx_unique_commit open-head "$early")
  fx_git -C "$UG_TMPDIR/seed" push -q origin "$closed:refs/heads/done" "$closed:refs/pull/7/head" "$early:refs/heads/part" "$open_head:refs/heads/live" "$open_head:refs/pull/8/head" ||
    fail 'cannot push the pull request refs'
  printf '8 live\n' >"$UG_TMPDIR/open-prs"
  fx_git -C "$fx_clone" fetch -q origin || fail 'cannot fetch the pull request branches'
  fx_age "$fx_clone/.git/logs/refs/remotes/origin/done" "$fx_clone/.git/logs/refs/remotes/origin/part"
  fx_start
  assert_eq no "$(fx_has_ref "$fx_origin" refs/heads/done && echo yes || echo no)" 'an idle branch at the head of a closed pull request is deleted on origin'
  assert_eq yes "$(fx_has_ref "$fx_origin" refs/heads/part && echo yes || echo no)" 'a branch held only by an open pull request stays on origin'
}

t_7_9() {
  fetch_fixture
  fx_git -C "$UG_TMPDIR/seed" push -q origin "$fx_old:refs/heads/opened" || fail 'cannot push the opened branch'
  printf '9 opened\n' >"$UG_TMPDIR/open-prs"
  fx_git -C "$fx_clone" fetch -q origin || fail 'cannot fetch the opened branch'
  fx_age "$fx_clone/.git/logs/refs/remotes/origin/opened"
  fx_start
  assert_eq yes "$(fx_has_ref "$fx_origin" refs/heads/opened && echo yes || echo no)" 'the head branch of an open pull request stays on origin, even when its tip is in origin/main'
}

# Poll briefly so that a background sync started by mistake is seen.
fx_assert_no_sync() {
  local i
  for ((i = 0; i < 30; i++)); do
    [[ ! -e $fx_clone/.git/ug-fetch.pid ]] || fail "$1"
    sleep 0.1
  done
}

t_7_10() {
  fetch_fixture
  fx_worktree feat "$fx_old"
  mkdir -p "$UG_TMPDIR/feat/sub" || fail 'cannot make a folder in the worktree'
  fx_start "$UG_TMPDIR/feat/sub"
  assert_eq "$fx_new" "$(fx_head)" 'a start in a linked worktree moves the main checkout of its clone'
  assert_eq ok "$(fx_status | cut -d' ' -f1)" 'the fetch status of the clone is ok'
  assert_eq "$UG_TMPDIR/feat/sub" "$(cat "$UG_TMPDIR/omp.cwd")" 'omp starts in the folder where agent-start started'
  assert_eq "$fx_old" "$(fx_git -C "$UG_TMPDIR/feat" rev-parse HEAD)" 'the worktree itself does not move'
}

t_7_11() {
  fetch_fixture
  fx_git -C "$fx_clone" remote set-url origin "https://gitlab.com/$fx_repo.git" || fail 'cannot set the GitLab origin'
  # git could fetch the GitLab origin, so only the origin check stops the sync.
  fx_git -C "$fx_clone" config --add "url.$UG_TMPDIR/gh/.insteadOf" https://gitlab.com/ || fail 'cannot map GitLab to the bare repo'
  fx_run_start
  fx_assert_no_sync 'a clone with a non-GitHub origin starts a background sync'
  assert_eq "$fx_old" "$(fx_head)" 'a clone with a non-GitHub origin does not move'
  assert_eq "$fx_clone" "$(cat "$UG_TMPDIR/omp.cwd")" 'omp still starts in the clone'
  assert_eq '' "$(cat "$UG_TMPDIR/notices")" 'a clone that does not sync gives no notice'
}

t_7_12() {
  local mid notices
  fetch_fixture
  printf 'one\n' >"$UG_TMPDIR/seed/file"
  fx_git -C "$UG_TMPDIR/seed" add file || fail 'cannot stage the file in the seed'
  mid=$(fx_commit 'add file')
  fx_git -C "$fx_clone" fetch -q origin || fail 'cannot fetch the file commit'
  fx_git -C "$fx_clone" checkout -q -B main "$mid" || fail 'cannot put main of the clone at the file commit'
  fx_new=$(fx_commit third)
  printf 'mine\n' >"$fx_clone/file"
  fx_start
  assert_eq ok "$(fx_status | cut -d' ' -f1)" 'the fetch status is ok'
  assert_eq "$mid" "$(fx_head)" 'a main checkout with a tracked change does not move'
  assert_eq mine "$(cat "$fx_clone/file")" 'the tracked change stays'
  fx_start
  notices=$(cat "$UG_TMPDIR/notices")
  assert_eq "the main checkout of $fx_repo has uncommitted changes, so it did not move to origin/main" "$notices" \
    'the next start says why the main checkout did not move'
  fx_git -C "$fx_clone" checkout -q -- file || fail 'cannot drop the tracked change'
  printf 'scratch\n' >"$fx_clone/untracked"
  fx_start
  assert_eq "$fx_new" "$(fx_head)" 'the same checkout with only an untracked file moves'
  assert_eq scratch "$(cat "$fx_clone/untracked")" 'the untracked file stays'
  assert_eq no "$([[ -e $fx_clone/.git/ug-reset.summary ]] && echo yes || echo no)" 'a checkout that moved leaves no reset notice'
}

t_7_13() {
  local notices
  fetch_fixture
  fx_git -C "$fx_clone" checkout -q -b topic "$fx_old" || fail 'cannot make the topic branch'
  fx_start
  assert_eq "$fx_old" "$(fx_head)" 'a main checkout on another branch does not move'
  assert_eq "$fx_old" "$(fx_git -C "$fx_clone" rev-parse refs/heads/topic)" 'the other branch keeps its commit'
  fx_start
  notices=$(cat "$UG_TMPDIR/notices")
  assert_eq "the main checkout of $fx_repo is on the branch topic, so it did not move to origin/main" "$notices" \
    'the next start says why the main checkout did not move'
  fx_git -C "$fx_clone" checkout -q main || fail 'cannot check out main'
  fx_start
  assert_eq "$fx_new" "$(fx_head)" 'the same checkout on the default branch moves'
  assert_eq "$fx_new" "$(fx_git -C "$fx_clone" rev-parse refs/heads/main)" 'the default branch moves with it'
}
