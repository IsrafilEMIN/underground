# shellcheck shell=bash

dr_env_vars='^(HOME|TMPDIR|PATH|OMP_AUTH_BROKER_URL|OMP_AUTH_BROKER_TOKEN|GIT_CONFIG_[A-Z0-9_]+|UG_GATEWAY_TOKEN)='

dr_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.000Z; }

dr_age() {
  local seconds=$1
  shift
  touch -t "$(date -r $(($(date +%s) - seconds)) +%Y%m%d%H%M.%S)" "$@" || fail "cannot age $*"
}

dream_fixture() {
  local name
  ug_mktemp_dir
  dr_home=$UG_TMPDIR/home
  dr_root=$UG_TMPDIR/root
  dr_dreams=$dr_home/.omp/agent/dreams
  dr_sessions=$dr_home/.omp/agent/sessions/-work-acme-widget
  dr_calls=$UG_TMPDIR/calls
  dr_log=$dr_root/logs/agent-dream.log
  mkdir -p "$dr_root/code/bin" "$dr_root/logs" "$dr_sessions" "$dr_calls" || fail 'cannot make the fixture dirs'
  printf 'gateway-secret\n' >"$dr_root/gateway-token"
  : >"$dr_root/code/ug-notices.ts"
  cp "$UG_REPO_ROOT/host/agent/dream-prompt.md" "$dr_root/code/dream-prompt.md" || fail 'cannot copy the dream prompt'
  for name in agent-env agent-start agent-dream; do
    render "$UG_REPO_ROOT/host/agent/$name" "$dr_root/code/$name" \
      AGENT_HOME="$dr_home" ROOT="$dr_root" USAGE_BROKER_PORT=9
  done
  cat >"$dr_root/code/omp-stub" <<EOF
#!/bin/bash
if [[ \$1 == config ]]; then
  cat '$UG_TMPDIR/db-path' 2>/dev/null || printf '(not set)\n'
  exit 0
fi
pwd >'$dr_calls/omp.cwd'
printf '%s\n' "\$@" >'$dr_calls/omp.args'
printf '%s' "\${UG_NOTICES-<unset>}" >'$dr_calls/omp.notices'
env | grep -E '$dr_env_vars' | LC_ALL=C sort >'$dr_calls/omp.env'
cat '$UG_TMPDIR/answer.md' 2>/dev/null
exit \$(cat '$UG_TMPDIR/omp.rc' 2>/dev/null || echo 0)
EOF
  chmod +x "$dr_root/code/omp-stub"
  ln -s "$dr_root/code/omp-stub" "$dr_root/code/bin/omp"
  cat >"$dr_root/code/bin/sqlite3" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>'$dr_calls/sqlite3'
exec /usr/bin/sqlite3 "\$@"
EOF
  chmod +x "$dr_root/code/bin/sqlite3"
}

dr_answer() {
  printf '%s' "$1" >"$UG_TMPDIR/answer.md"
  printf '%s\n' "${2:-0}" >"$UG_TMPDIR/omp.rc"
}

dr_session() {
  local id=$1 items=${2:-1} size=${3:-20}
  jq -nc --arg id "$id" --arg at "$(dr_iso "$(date +%s)")" --argjson items "$items" --argjson size "$size" '
    {type: "session", id: $id, timestamp: $at, cwd: "/work/acme"},
    (range($items) | {type: "message", timestamp: $at, message: {role: "user", content: [{type: "text", text: ("prompt \($id) " + ("u" * $size))}]}}),
    {type: "message", timestamp: $at, message: {role: "assistant", stopReason: "toolUse", content: [{type: "text", text: "thinking aloud \($id)"}]}},
    {type: "message", timestamp: $at, message: {role: "toolResult", isError: true, toolName: "bash", content: [{type: "text", text: "tool broke in \($id)"}]}},
    {type: "message", timestamp: $at, message: {role: "assistant", stopReason: "stop", content: [{type: "text", text: "final answer \($id)"}]}}
  ' >"$dr_sessions/2026-11-21T00-00-00-000Z_$id.jsonl" || fail "cannot write the session $id"
}

dr_db() {
  dr_db_file=$UG_TMPDIR/mnemopi.db
  local table cols='id TEXT PRIMARY KEY, content TEXT, source TEXT, timestamp TEXT, session_id TEXT, metadata_json TEXT, valid_until TEXT, consolidated_at TEXT, scope TEXT'
  for table in working_memory episodic_memory; do
    /usr/bin/sqlite3 "$dr_db_file" "CREATE TABLE $table ($cols)" || fail "cannot make the table $table"
  done
  printf '%s\n' "$dr_db_file" >"$UG_TMPDIR/db-path"
}

dr_row() {
  local table=$1 id=$2 content=$3 at=$4 consolidated=${5:-NULL}
  /usr/bin/sqlite3 "$dr_db_file" "INSERT INTO $table (id, content, source, timestamp, session_id, metadata_json, consolidated_at, scope) VALUES ('$id', '$content', 'retain', '$at', 's0', '{\"context\":\"ctx $id\"}', $consolidated, 'global')" ||
    fail "cannot insert the row $id"
}

run_dream() {
  dr_rc=0
  env -i PATH=/usr/bin:/bin /bin/bash "$dr_root/code/agent-dream" >"$UG_TMPDIR/dream.out" 2>&1 || dr_rc=$?
  dr_out=$(cat "$UG_TMPDIR/dream.out")
}

run_start() {
  rm -f "$dr_calls/omp.notices"
  env -i PATH=/usr/bin:/bin /bin/bash "$dr_root/code/agent-start" >"$UG_TMPDIR/start.out" 2>&1 ||
    fail "agent-start exited non-zero: $(cat "$UG_TMPDIR/start.out")"
  dr_notices=$(cat "$dr_calls/omp.notices" 2>/dev/null) || fail 'agent-start did not call omp'
}

dr_state() { cat "$dr_dreams/.state" 2>/dev/null || printf '<none>'; }

dr_reports() { find "$dr_dreams" -maxdepth 1 -name '*.md' 2>/dev/null | LC_ALL=C sort; }

dr_digest() {
  local f
  for f in "$dr_dreams"/run/*/digest.md; do
    [[ -f $f ]] && { cat "$f"; return 0; }
  done
  fail 'the dream left no digest'
}

t_9_1() {
  local want start_env
  dream_fixture
  run_start
  start_env=$(cat "$dr_calls/omp.env")
  rm -f "$dr_calls/omp.env"
  dr_session s1
  dr_answer $'# Dream\n\nSummary: ok\n'
  run_dream
  assert_eq 0 "$dr_rc" "agent-dream with one session exits 0 ($dr_out)"
  want=$(
    {
      printf 'HOME=%s\n' "$dr_home"
      printf 'TMPDIR=%s\n' "$(getconf DARWIN_USER_TEMP_DIR)"
      printf 'PATH=%s/code/bin:/usr/bin:/bin:/usr/sbin:/sbin\n' "$dr_root"
      printf 'OMP_AUTH_BROKER_URL=http://127.0.0.1:9\nOMP_AUTH_BROKER_TOKEN=usage-only\n'
      printf 'GIT_CONFIG_COUNT=2\nGIT_CONFIG_KEY_0=credential.https://github.com.helper\nGIT_CONFIG_VALUE_0=\n'
      printf 'GIT_CONFIG_KEY_1=credential.https://github.com.helper\n'
      printf 'GIT_CONFIG_VALUE_1=!f() { t=$("%s/code/bin/gh-app-token") || exit 1; echo username=x-access-token; echo "password=$t"; }; f\n' "$dr_root"
      printf 'UG_GATEWAY_TOKEN=gateway-secret\n'
    } | LC_ALL=C sort
  )
  assert_eq "$want" "$start_env" 'agent-start gives omp the agent environment'
  assert_eq "$want" "$(cat "$dr_calls/omp.env" 2>/dev/null)" 'agent-dream gives omp the same agent environment'
}

t_9_2() {
  local holder i
  dream_fixture
  dr_session s1
  dr_answer $'# Dream\n\nSummary: ok\n'
  mkdir -p "$dr_dreams"
  /usr/bin/lockf -k "$dr_dreams/.lock" /bin/bash -c \
    ': >"$1"; for ((i = 0; i < 600; i++)); do [[ -e $2 ]] && exit 0; sleep 0.1; done' _ "$UG_TMPDIR/held" "$UG_TMPDIR/release" >/dev/null 2>&1 &
  holder=$!
  for ((i = 0; i < 100; i++)); do
    [[ -e $UG_TMPDIR/held ]] && break
    sleep 0.1
  done
  [[ -e $UG_TMPDIR/held ]] || fail 'the lock holder did not take the lock'
  run_dream
  : >"$UG_TMPDIR/release"
  wait "$holder"
  assert_eq 0 "$dr_rc" "agent-dream exits 0 while another dream holds the lock ($dr_out)"
  assert_contains 'skipped: another dream holds' "$dr_out" 'the log says the dream was skipped'
  [[ ! -e $dr_calls/omp.args ]] || fail 'omp ran while another dream held the lock'
  assert_eq '' "$(dr_reports)" 'no report is written while the lock is held'
  assert_eq '<none>' "$(dr_state)" 'the state is not written while the lock is held'
}

t_9_3() {
  local state
  dream_fixture
  state=$(dr_iso $(($(date +%s) - 3600)))
  mkdir -p "$dr_dreams"
  printf '%s\n' "$state" >"$dr_dreams/.state"
  dr_session old
  dr_age 172800 "$dr_sessions"/*.jsonl
  dr_db
  dr_row working_memory w-open 'open fact' 2020-01-01T00:00:00.000Z
  dr_row episodic_memory e-done 'consolidated fact' 2020-01-01T00:00:00.000Z "'2020-01-02T00:00:00.000Z'"
  dr_answer $'# Dream\n\nSummary: ok\n'
  run_dream
  assert_eq 0 "$dr_rc" "agent-dream with an empty window exits 0 ($dr_out)"
  assert_contains 'skipped: no sessions and no new memory rows' "$dr_out" 'the log says the window was empty'
  [[ ! -e $dr_calls/omp.args ]] || fail 'omp ran for an empty window'
  assert_eq '' "$(dr_reports)" 'no report is written for an empty window'
  assert_eq "$state" "$(dr_state)" 'the state stays as it was for an empty window'
  assert_eq '' "$(find "$dr_dreams/run" -mindepth 1 2>/dev/null)" 'no run dir is left for an empty window'
}

t_9_4() {
  local i digest size
  dream_fixture
  for ((i = 10; i < 27; i++)); do
    dr_session "s$i" 8 3000
  done
  dr_answer $'# Dream\n\nSummary: ok\n'
  run_dream
  assert_eq 0 "$dr_rc" "agent-dream with 17 large sessions exits 0 ($dr_out)"
  digest=$(dr_digest)
  assert_contains '[truncated: this session kept 20000 of ' "$digest" 'a session over 20000 characters is cut and says so'
  assert_contains '[truncated: the digest reached its total cap of 300000 characters inside this session]' "$digest" 'the session that hits the total cap says so'
  assert_contains 'more sessions left out by the total cap of 300000 characters: ' "$digest" 'sessions past the total cap are listed as left out'
  size=$(printf '%s' "$digest" | jq -Rs length)
  ((size < 302000)) || fail "the digest holds $size characters, over the total cap"
}

t_9_5() {
  local digest end args
  dream_fixture
  dr_session s1
  dr_db
  dr_row working_memory w-new 'new fact' "$(dr_iso "$(date +%s)")"
  dr_row working_memory w-open 'open fact' 2020-01-01T00:00:00.000Z
  dr_row episodic_memory e-done 'consolidated fact' 2020-01-01T00:00:00.000Z "'2020-01-02T00:00:00.000Z'"

  dr_answer $'# Dream x\n\nSummary: half done\n' 1
  run_dream
  assert_eq 1 "$dr_rc" 'agent-dream exits 1 when omp fails'
  assert_eq '<none>' "$(dr_state)" 'a failed omp run leaves no state'
  assert_contains 'Failure: omp exited 1' "$(cat "$(dr_reports | head -n 1)")" 'the report records the omp failure'
  assert_contains ' failed: omp exited 1' "$(tail -n 1 <<<"$dr_out")" 'the log ends with the failure'

  dr_answer $'# Dream x\n\nno summary here\n'
  run_dream
  assert_eq 1 "$dr_rc" 'agent-dream exits 1 when the answer has no Summary line'
  assert_eq '<none>' "$(dr_state)" 'an answer without a Summary line leaves no state'

  rm -rf "$dr_dreams"/run
  dr_answer $'# Dream x\n\nSummary: 1 added, 0 invalidated, 0 proposals.\n'
  run_dream
  assert_eq 0 "$dr_rc" "agent-dream exits 0 on success ($dr_out)"
  end=$(dr_state)
  [[ $end =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.000Z$ ]] || fail "the state after success is [$end], not an ISO UTC time"
  assert_contains "ok: " "$dr_out" 'the log says the dream succeeded'
  assert_eq 3 "$(dr_reports | wc -l | tr -d ' ')" 'each of the three runs wrote its own report'
  report=${dr_out##*ok: }
  report=${report%%, window*}
  assert_eq "$(cat "$UG_TMPDIR/answer.md")" "$(cat "$report")" 'the report is the omp answer'

  args=$(sed -n 1,8p "$dr_calls/omp.args")
  assert_eq $'-p\n--no-session\n--model\ndefault\n--tools\nread,grep,glob,retain,memory_edit\n--max-time\n30m' "$args" 'omp runs headless with the dream tools'
  assert_eq "$dr_dreams/run" "$(cat "$dr_calls/omp.cwd")" 'omp runs in the fixed run dir'
  assert_contains "- Digest: $dr_dreams/run/" "$(cat "$dr_calls/omp.args")" 'the prompt names the digest path'
  digest=$(dr_digest)
  assert_contains 'prompt s1' "$digest" 'the digest holds the user prompt'
  assert_contains 'final answer s1' "$digest" 'the digest holds the final answer'
  assert_contains 'tool broke in s1' "$digest" 'the digest holds the tool error'
  [[ $digest != *'thinking aloud s1'* ]] || fail 'the digest holds a non-final assistant message'
  assert_contains 'working_memory id w-new · new' "$digest" 'the digest holds the new row'
  assert_contains 'working_memory id w-open · open' "$digest" 'the digest holds the open row'
  assert_contains 'context ctx w-new' "$digest" 'the digest holds the row context'
  [[ $digest != *'consolidated fact'* ]] || fail 'the digest holds an old consolidated row'
  assert_contains "Failure: omp exited 1" "$digest" 'the digest holds the earlier reports'
  [[ -f $dr_dreams/.mnemopi-before.db ]] || fail 'the db was not copied before the dream'
  assert_contains ".backup '$dr_dreams/.mnemopi-before.db'" "$(cat "$dr_calls/sqlite3")" 'the db copy uses sqlite3 .backup'
}

dr_report() {
  local name=$1 age=$2 body=$3
  mkdir -p "$dr_dreams"
  printf '%s' "$body" >"$dr_dreams/$name"
  dr_age "$age" "$dr_dreams/$name"
}

t_9_6() {
  local hint=' say "review the dream" to review.'
  dream_fixture
  run_start
  assert_eq '' "$dr_notices" 'no dream report means no notice'

  dr_report 2026-01-01.md 172800 $'# Dream\n\nSummary: 1 added.\n\n## Proposals\nNone.\n'
  run_start
  assert_eq '' "$dr_notices" 'a report older than a day with no pending proposal gives no notice'

  dr_report 2026-01-02.md 3600 $'# Dream\n\nSummary: 2 added.\n\n## Proposals\nNone.\n'
  run_start
  assert_eq "dream: 2 added.$hint" "$dr_notices" 'a report younger than a day gives its summary'

  dr_report 2026-01-02.md 172800 $'# Dream\n\nSummary: 1 pending.\n\n## Proposals\n### 1. x\nStatus: pending\n'
  dr_report 2026-01-03.md 100000 $'# Dream\n\nSummary: 3 added.\n\n## Proposals\n### 1. x\nStatus: rejected\n'
  run_start
  assert_eq '' "$dr_notices" 'only the newest report counts, and its proposal is not pending'

  dr_report 2026-01-04.md 90000 $'# Dream\n\nSummary: 1 pending.\n\n## Proposals\n### 1. x\nStatus: pending\n'
  run_start
  assert_eq "dream: 1 pending.$hint" "$dr_notices" 'an old report with a pending proposal gives its summary'
}

t_9_7() {
  dream_fixture
  printf '2026-01-01T04:00:00.000Z ok: done\n2026-01-02T04:00:00.000Z failed: sqlite3 cannot back up x\n' >"$dr_log"
  run_start
  assert_eq "the last dream failed: sqlite3 cannot back up x; read $dr_log" "$dr_notices" 'a failure at the end of the dream log gives a notice'

  printf '2026-01-03T04:00:00.000Z ok: done\n' >>"$dr_log"
  dr_report 2026-01-03.md 60 $'# Dream\n\nSummary: half.\n\nFailure: omp exited 3; read e\n'
  run_start
  assert_eq "the last dream failed: omp exited 3; read e; read $dr_dreams/2026-01-03.md" "$dr_notices" 'a failure note in the newest report gives one failure notice and no summary'
}

t_9_8() {
  dream_fixture
  run_start
  assert_eq '' "$dr_notices" 'a missing agent-check is skipped silently'
  printf '#!/bin/bash\nprintf "%%s\\n" "$1" >%q\nprintf "omp is old\\n\\nmemory is off\\n"\n' "$dr_calls/check.args" >"$dr_root/code/bin/agent-check"
  chmod +x "$dr_root/code/bin/agent-check"
  run_start
  assert_eq $'omp is old\nmemory is off' "$dr_notices" 'each agent-check line becomes a notice'
  assert_eq "$dr_root/code/requirements" "$(cat "$dr_calls/check.args")" 'agent-check reads the installed requirements'
}

t_9_9() {
  ug_mktemp_dir
  (
    source "$UG_REPO_ROOT/host/lib/ug.bash"
    source "$UG_REPO_ROOT/host/lib/services.bash"
    label=com.underground.agent-dream
    row=$(ug_services daemon | grep "^$label|") || fail 'the services table has no daemon row for the dream'
    IFS='|' read -r _ _ scope user template health log watch <<<"$row"
    assert_eq daemon "$scope" 'the dream is a system LaunchDaemon'
    assert_eq ugagent "$(ug_fact "$user")" 'the dream runs as the agent user'
    ug_service_probe daemon "$label" "$health" || fail 'the dream row has no usable health'
    assert_eq "launchctl print system/$label" "${ug_probe[*]}" 'setup probes the dream as a loaded system job'
    plist=$UG_TMPDIR/$label.plist
    out=$(ug_render "$plist" "$UG_REPO_ROOT/$template" "$template" -e "s|@OMP@|omp|g" -e "s|@ENGINE@|1.2.3.4:5|g") || fail "$out"
    plutil -lint -s "$plist" || fail 'the rendered dream plist is not a valid plist'
    get() { plutil -extract "$1" raw -o - "$plist"; }
    assert_eq "$label" "$(get Label)" 'the plist label matches the services row'
    assert_eq ugagent "$(get UserName)" 'launchd runs the dream as the agent user'
    assert_eq 4 "$(get StartCalendarInterval.Hour)" 'the dream starts at 04'
    assert_eq 0 "$(get StartCalendarInterval.Minute)" 'the dream starts on the hour'
    assert_eq /Library/Underground/code/agent-dream "$(get ProgramArguments.1)" 'launchd runs the installed agent-dream'
    assert_eq "$(ug_service_expand "$log")" "$(get StandardOutPath)" 'the dream logs where the services row says'
    assert_eq "$(get StandardOutPath)" "$(get StandardErrorPath)" 'stdout and stderr share the dream log'
    assert_eq '/Library/Underground/code/agent-dream /Library/Underground/code/agent-env /Library/Underground/code/dream-prompt.md' \
      "$(ug_service_expand "$watch")" 'a change to the dream code reloads the job'
    for name in agent-env agent-dream agent-start; do
      out=$(ug_render "$UG_TMPDIR/$name" "$UG_REPO_ROOT/host/agent/$name" "host/agent/$name") || fail "$out"
    done
  ) || exit $?
}
