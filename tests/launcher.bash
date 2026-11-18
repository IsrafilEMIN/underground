# shellcheck shell=bash

launcher_now=1800000000

launcher_stub() {
  local name=$1 body=$2
  printf '#!/bin/bash\n%s\n' "$body" >"$UG_TMPDIR/stubs/$name"
  chmod +x "$UG_TMPDIR/stubs/$name"
}

launcher_home() {
  ug_mktemp_dir
  LA_HOME=$UG_TMPDIR/home
  LA_DATA=$LA_HOME/.local/share/underground
  LA_CALLS=$UG_TMPDIR/calls
  mkdir -p "$LA_DATA/agent-ssh" "$LA_DATA/backup" "$UG_TMPDIR/stubs" "$UG_TMPDIR/work" "$LA_CALLS"
  chmod 700 "$LA_HOME"
  printf 'test key\n' >"$LA_DATA/agent-ssh/id_ed25519"
  printf '[127.0.0.1]:2222 ssh-ed25519 AAAAtest\n' >"$LA_DATA/agent-ssh/known_hosts"
  : >"$LA_DATA/sources"
  launcher_stub ssh "printf '%s\n' \"\${UG_NOTICES-<unset>}\" >'$LA_CALLS/ssh.notices'
printf '%s\n' \"\$@\" >'$LA_CALLS/ssh.args'
exit \${LA_SSH_RC:-0}"
  launcher_stub nc "printf '%s\n' \"\$*\" >>'$LA_CALLS/nc'
exit \${LA_NC_RC:-0}"
  launcher_stub launchctl "printf '%s\n' \"\$*\" >>'$LA_CALLS/launchctl'
exit \${LA_LAUNCHCTL_RC:-1}"
  launcher_stub sudo "printf '%s\n' \"\$*\" >>'$LA_CALLS/sudo'
exit 1"
  launcher_stub date "[[ \$* == +%s ]] || exit 1
printf '%s\n' $launcher_now"
}

run_launcher() {
  la_rc=0
  (
    cd "$UG_TMPDIR/work" &&
      env -i HOME="$LA_HOME" PATH="$UG_TMPDIR/stubs:/usr/bin:/bin" TERM=dumb \
        GIT_CEILING_DIRECTORIES="$UG_TMPDIR" \
        "$UG_REPO_ROOT/host/bin/ug-agent" omp
  ) >"$UG_TMPDIR/out" 2>"$UG_TMPDIR/err" || la_rc=$?
  la_err=$(cat "$UG_TMPDIR/err")
  la_notices=$(cat "$LA_CALLS/ssh.notices" 2>/dev/null) || la_notices='<ssh not called>'
  la_args=$(cat "$LA_CALLS/ssh.args" 2>/dev/null) || la_args='<ssh not called>'
}

launcher_ssh_args() {
  printf '%s\n' -tt -p 2222 -i "$LA_DATA/agent-ssh/id_ed25519" -o IdentitiesOnly=yes \
    -o "UserKnownHostsFile=$LA_DATA/agent-ssh/known_hosts" -o StrictHostKeyChecking=yes \
    -o LogLevel=ERROR -o SendEnv=UG_REPO -o SendEnv=UG_NOTICES ugagent@127.0.0.1 -- omp
}

t_5_1() {
  launcher_home
  run_launcher
  assert_eq 0 "$la_rc" "ug-agent with no backup/last runs ssh (stderr: $la_err)"
  assert_eq "$(launcher_ssh_args)" "$la_args" 'ssh gets the pinned agent login and the omp argument'
  assert_eq "no good backup yet; read $LA_DATA/backup/backup.log" "$la_notices" \
    'UG_NOTICES warns that there is no good backup'
}

t_5_2() {
  launcher_home
  printf '%s\n' $((launcher_now - 3 * 86400)) >"$LA_DATA/backup/last"
  run_launcher
  assert_eq 0 "$la_rc" "ug-agent with a 3-day-old backup runs ssh (stderr: $la_err)"
  assert_eq "$(launcher_ssh_args)" "$la_args" 'ssh gets the pinned agent login and the omp argument'
  assert_eq "the last good backup is 3 days old; read $LA_DATA/backup/backup.log" "$la_notices" \
    'UG_NOTICES warns that the backup is 3 days old'
}

t_5_3() {
  launcher_home
  printf '%s\n' $((launcher_now - 3600)) >"$LA_DATA/backup/last"
  run_launcher
  assert_eq 0 "$la_rc" "ug-agent with an hour-old backup runs ssh (stderr: $la_err)"
  assert_eq "$(launcher_ssh_args)" "$la_args" 'ssh gets the pinned agent login and the omp argument'
  assert_eq '' "$la_notices" 'UG_NOTICES is set and empty for an hour-old backup'
  assert_eq '-z -w 1 127.0.0.1 2222' "$(cat "$LA_CALLS/nc")" 'the agent sshd port was probed'
}
