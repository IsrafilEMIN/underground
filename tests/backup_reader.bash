# shellcheck shell=bash

bt_home() {
  ug_mktemp_dir
  BT_HOME=$UG_TMPDIR/home
  BT_TAR=$UG_TMPDIR/agent-home-tar
  mkdir -p "$BT_HOME/.omp/agent" "$BT_HOME/scratch"
  render "$UG_REPO_ROOT/host/agent/agent-home-tar" "$BT_TAR" AGENT_HOME="$BT_HOME"
  chmod +x "$BT_TAR"
}

bt_run() {
  bt_rc=0
  "$BT_TAR" >"$UG_TMPDIR/out.tar" 2>"$UG_TMPDIR/err" || bt_rc=$?
  bt_err=$(cat "$UG_TMPDIR/err")
}

bt_members() {
  /usr/bin/tar -tf "$UG_TMPDIR/out.tar" | LC_ALL=C sort | paste -sd ' ' -
}

bt_put() {
  mkdir -p "$(dirname "$BT_HOME/$1")"
  printf '%s\n' "$1" >"$BT_HOME/$1"
}

bt_live_db() {
  BT_DB=$BT_HOME/.omp/agent/sessions.db
  /usr/bin/sqlite3 "$BT_DB" 'pragma journal_mode=wal;' 'create table t(v text);' "insert into t values('old');" >/dev/null ||
    fail 'cannot create the fixture database'
  mkfifo "$UG_TMPDIR/hold.in"
  /usr/bin/sqlite3 "$BT_DB" <"$UG_TMPDIR/hold.in" >"$UG_TMPDIR/hold.out" 2>&1 &
  BT_HOLDER=$!
  exec 3>"$UG_TMPDIR/hold.in"
  printf '%s\n' 'pragma wal_autocheckpoint=0;' "insert into t values('newest');" ".system touch '$UG_TMPDIR/held'" >&3
  local i
  for ((i = 0; i < 100; i++)); do
    [[ -e $UG_TMPDIR/held ]] && break
    sleep 0.05
  done
  [[ -e $UG_TMPDIR/held ]] || fail "the database holder did not start: $(cat "$UG_TMPDIR/hold.out")"
}

bt_release_db() {
  exec 3>&-
  wait "$BT_HOLDER"
}

t_3_1() {
  bt_home
  bt_put .zshrc
  bt_put .omp/settings.json
  bt_put .omp/agent/config.yml
  bt_put .omp/agent/sessions/s1.jsonl
  bt_put .omp/agent/cache/blob
  bt_put .omp/agent/models.db
  bt_put .omp/agent/models.db-wal
  bt_put .omp/agent/plugins/node_modules/dep/index.js
  bt_put .omp/agent/plugins/main.js
  bt_put scratch/notes.txt
  bt_put scratch/app/node_modules/dep/index.js
  bt_put scratch/app/main.js
  bt_run
  assert_eq 0 "$bt_rc" "the run succeeds: $bt_err"
  assert_eq './.omp/agent/ ./.omp/agent/config.yml ./.omp/agent/plugins/ ./.omp/agent/plugins/main.js ./.omp/agent/sessions/ ./.omp/agent/sessions/s1.jsonl ./scratch/ ./scratch/app/ ./scratch/app/main.js ./scratch/notes.txt' \
    "$(bt_members)" 'the archive holds the agent dir and scratch without cache, models.db* and node_modules'
}

t_3_2() {
  bt_home
  bt_live_db
  cp "$BT_DB" "$UG_TMPDIR/main-only.db"
  assert_eq 0 "$(/usr/bin/sqlite3 "$UG_TMPDIR/main-only.db" "select count(*) from t where v='newest';")" \
    'the main database file lacks the newest row'
  bt_run
  bt_release_db
  assert_eq 0 "$bt_rc" "the run succeeds: $bt_err"
  mkdir "$UG_TMPDIR/x"
  /usr/bin/tar -xf "$UG_TMPDIR/out.tar" -C "$UG_TMPDIR/x" || fail 'the archive does not extract'
  local copy=$UG_TMPDIR/x/.omp/agent/sessions.db
  [[ -f $copy ]] || fail 'the archive has no .omp/agent/sessions.db'
  assert_eq 'newest old' "$(/usr/bin/sqlite3 "$copy" 'select v from t order by v;' | paste -sd ' ' -)" 'the archived database has the row that was only in the -wal'
  assert_eq ok "$(/usr/bin/sqlite3 "$copy" 'pragma integrity_check;')" 'the archived database passes integrity_check'
}

t_3_3() {
  bt_home
  bt_live_db
  bt_run
  [[ -f $BT_DB-wal && -f $BT_DB-shm ]] || fail 'the live -wal and -shm exist during the run'
  bt_release_db
  assert_eq 0 "$bt_rc" "the run succeeds: $bt_err"
  assert_eq './.omp/agent/ ./.omp/agent/sessions.db ./scratch/' "$(bt_members)" 'the archive holds the database copy and no live -wal or -shm'
}

t_3_4() {
  bt_home
  bt_put .omp/agent/config.yml
  bt_put scratch/notes.txt
  bt_put scratch/locked.txt
  chmod 000 "$BT_HOME/scratch/locked.txt"
  bt_run
  assert_eq 1 "$bt_rc" 'a run with an unreadable file in scratch fails'
  assert_contains 'agent-home-tar: tar failed' "$bt_err" 'stderr says tar failed'
  chmod 644 "$BT_HOME/scratch/locked.txt"
  bt_run
  assert_eq 0 "$bt_rc" "the same home with the file readable succeeds: $bt_err"
}
