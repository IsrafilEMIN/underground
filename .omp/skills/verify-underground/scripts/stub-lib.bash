# Shared head of every ugv stub. ugv up prepends base= and name= and appends the stub body.
# Stubs stand in for production boundaries only: privilege changes, launchd, ssh, the backup
# host, GitHub and the omp binary with its model gateway.

log_call() {
  local line
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ) cwd=$PWD argv=$(printf '%q ' "$@")"
  printf '%s\n' "${line% }" >>"$base/calls/$name.log"
}

log_note() {
  printf '  %s\n' "$*" >>"$base/calls/$name.log"
}

# fault NAME: exit with the code in $base/faults/NAME if `ugv fault` set one.
fault() {
  local rc
  [[ -f $base/faults/$1 ]] || return 0
  rc=$(<"$base/faults/$1")
  log_note "fault $1: exit $rc"
  exit "$rc"
}

log_call "$@"
