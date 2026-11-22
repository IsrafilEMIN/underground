# Back up the agent home

`ug-backup` saves the agent home (`.omp/agent` and `scratch`) to the restic repo on the backup host once a day. launchd runs it as the owner, and the owner can run it by hand. The first run makes the repo. Each good run clears stale locks, saves one snapshot (tried twice), checks a part of the repo data and records the time in `backup/last`. Every failure is one log line on stderr and exit 1, and `backup/last` stays as it was. The `omp` launcher reads `backup/last` and warns when there is no good backup or it is more than 2 days old.

## Sub-features

- `first-run` makes the repo, saves a snapshot, checks it and writes `backup/last`.
- `snapshot` holds `.omp/agent` and `scratch`, not the cache, `models.db*` or `node_modules`; a live sqlite db is a consistent copy.
- `second-run` uses the existing repo (no init) and adds one snapshot.
- `backup-fail` tries the save twice, does no check, exit 1, `last` unchanged.
- `check-fail` keeps the snapshot but exit 1, `last` unchanged.
- `wrong-password` names a wrong password when the repo does not open with restic exit 12.
- `host-down` stops when the backup host does not answer ssh and the config has no `wake=` line (or the wake command fails).
- `bad-config` rejects a repo that is not `sftp:`, an unknown key, a line without `=`, and a missing config.
- `missing-setup` stops on a missing pinned restic, a missing or empty password, or a missing agent home reader.
- `usage` refuses arguments.
- `age` the next `omp` launch shows no backup notice after a good run.

## How to get to it (user POV)

- launchd runs `host/bin/ug-backup` daily as the owner (LaunchAgent installed by `ug-setup`; not drivable in the stand-in, see Gotchas). Its stderr goes to `~/.local/share/underground/backup/backup.log`.
- The owner runs `host/bin/ug-backup` by hand in a terminal.
- The owner sees the result at the next `omp` launch as a backup notice, or no notice (see [launch-agent.md](./launch-agent.md)).

## Driving it with ugv

Preconditions:

- Fresh stand-in: `U=.omp/skills/verify-underground/scripts/ugv`, `RUN=$(date +%Y%m%d-%H%M%S)-backup`, `$U up "$RUN"`, `B=/private/tmp/ugv-$RUN`, and `$U doctor "$RUN"` ends with `doctor: ok`.
- `D=owner-home/.local/share/underground` (relative to `$B`; `look` runs in `$B`). The baseline config is `repo=sftp:verify@backup.invalid:/ugv-$RUN`, `$D/backup/last` is missing and `$B/backup-repo` does not exist.
- Run the bullets in order: the snapshot seeds come before `first-run`, and the later failure bullets need the repo and the `last` value from the good runs.

- **Seed the agent home.** Add scratch files and the parts that must stay out. Run `$U look "$RUN" snapshot-seed -- /bin/sh -c 'mkdir -p agent-home/scratch/notes agent-home/.omp/agent/cache agent-home/.omp/agent/node_modules/x && echo hi >agent-home/scratch/notes/a.txt && echo c >agent-home/.omp/agent/cache/blob && echo m >agent-home/.omp/agent/models.db && echo n >agent-home/.omp/agent/node_modules/x/i.js'`. Exit 0.
- **Seed a live db.** Keep a sqlite writer open with its data only in the WAL. Run `$U look "$RUN" snapshot-live-db -- /bin/sh -c '( printf "PRAGMA journal_mode=WAL;\nCREATE TABLE t(v);\nINSERT INTO t VALUES (\"live\");\n"; sleep 120 ) | /usr/bin/sqlite3 "$1" >/dev/null 2>&1 &' _ "$B/agent-home/.omp/agent/sessions.db"`, then `$U look "$RUN" snapshot-live-db-state -- ls -l agent-home/.omp/agent`. The listing shows `sessions.db` (4096 bytes), `sessions.db-wal` and `sessions.db-shm`.
- **first-run.** Run the daily backup by hand. Run `$U owner "$RUN" --label first-run -- host/bin/ug-backup`. Exit 0; stderr is `ug-backup: made the repo sftp:verify@backup.invalid:/ugv-<RUN>`, `cleared any stale locks in ...`, `saved the agent home to ...`, `checked data subset NN/100 of ...`, `recorded the run in $B/owner-home/.local/share/underground/backup/last`. Calls: ssh `-o BatchMode=yes -o ConnectTimeout=10 verify@backup.invalid true`; restic `cat config`, `init`, `unlock`, `backup --quiet --tag ug-agent --stdin-filename ug-agent-home.tar --stdin-from-command -- sudo -n -u ugagent $B/root/code/bin/agent-home-tar`, `check --read-data-subset=NN/100`; sudo `-n -u ugagent $B/root/code/bin/agent-home-tar`.
- **first-run state.** Read the record and the repo. Run `$U look "$RUN" first-run-state -- /bin/sh -c "cat $D/backup/last; ls backup-repo/snapshots; cat backup-repo/config"`. A Unix time (for example `1795319428`), `001.tar`, and `repo=sftp:verify@backup.invalid:/ugv-<RUN>`.
- **snapshot list.** Read the snapshot members. Run `$U look "$RUN" snapshot-list -- tar -tf backup-repo/snapshots/001.tar`. It lists `./.omp/agent/`, `./.omp/agent/extensions/underground-guard.ts`, `./.omp/agent/skills/dream-review/SKILL.md`, `./scratch/notes/a.txt` and `./.omp/agent/sessions.db`. It has no `cache/`, no `models.db`, no `node_modules`, no `sessions.db-wal`/`-shm`.
- **snapshot live db.** Open the db from the snapshot alone. Run `$U look "$RUN" snapshot-db -- /bin/sh -c 'd=$(mktemp -d) && tar -xf backup-repo/snapshots/001.tar -C "$d" ./.omp/agent/sessions.db && /usr/bin/sqlite3 "$d/.omp/agent/sessions.db" "select v from t;"'`. Stdout `live`: the row that was only in the WAL is in the saved file.
- **second-run.** Run the backup again. Run `$U owner "$RUN" --label second-run -- host/bin/ug-backup`. Exit 0; no `made the repo` line; restic calls are `cat config`, `unlock`, `backup ...`, `check ...` with no `init`.
- **second-run state.** Run `$U look "$RUN" second-run-state -- /bin/sh -c "cat $D/backup/last; ls backup-repo/snapshots"`. A newer time and `001.tar 002.tar`. Note this `last` value for the failure bullets.
- **age.** Start a session after the good run. Run `$U owner "$RUN" --label age-fresh -- host/bin/ug-agent`. Exit 0, stdout `omp-stub: session started in $B/agent-home/scratch` with no `omp-stub: warning notice:` line; ssh and omp calls note `UG_NOTICES=''`. The stale and missing cases are in [launch-agent.md](./launch-agent.md).
- **backup-fail.** Make the save fail. Run `$U fault "$RUN" restic-backup 1`, then `$U owner "$RUN" --label backup-fail -- host/bin/ug-backup`. Exit 1; stderr `attempt 1: the agent home was not saved (restic exit 1); a failed read stores no snapshot`, the same for `attempt 2`, then `the agent home was not saved in 2 attempts`. Calls: two restic `backup` calls each with `fault restic-backup: exit 1`, and no `check`.
- **backup-fail state.** Run `$U look "$RUN" backup-fail-state -- /bin/sh -c "cat $D/backup/last; ls backup-repo/snapshots"`, then `$U fault "$RUN" restic-backup clear`. `last` is the second-run value; still `001.tar 002.tar`.
- **check-fail.** Make the check fail. Run `$U fault "$RUN" restic-check 1`, then `$U owner "$RUN" --label check-fail -- host/bin/ug-backup`. Exit 1; stderr `saved the agent home to ...` then `checking the repo sftp:verify@backup.invalid:/ugv-<RUN> failed (restic exit 1): `.
- **check-fail state.** Run `$U look "$RUN" check-fail-state -- /bin/sh -c "cat $D/backup/last; ls backup-repo/snapshots"`, then `$U fault "$RUN" restic-check clear`. `last` unchanged; `003.tar` exists (the snapshot was saved, only the record is withheld).
- **wrong-password.** Make the repo refuse to open with exit 12. Run `$U fault "$RUN" restic-cat 12`, then `$U owner "$RUN" --label wrong-password -- host/bin/ug-backup`. Exit 1; stderr `the repo sftp:verify@backup.invalid:/ugv-<RUN> does not open (restic exit 12, which can mean a wrong password): `. The only restic call is `cat config`.
- **wrong-password state.** Run `$U look "$RUN" wrong-password-state -- /bin/sh -c "cat $D/backup/last; ls backup-repo/snapshots"`, then `$U fault "$RUN" restic-cat clear`. `last` unchanged; no new snapshot.
- **host-down.** Make the backup host not answer. Run `$U fault "$RUN" ssh-backup 255`, then `$U owner "$RUN" --label host-down -- host/bin/ug-backup`. Exit 1; stderr `backup-target: verify@backup.invalid does not answer ssh and the config has no wake= line to wake it`. One ssh call, no restic call.
- **host-down state.** Run `$U look "$RUN" host-down-state -- /bin/sh -c "cat $D/backup/last; ls backup-repo/snapshots"`. `last` unchanged; no new snapshot.
- **host-down wake fails.** With the ssh fault still set, add a failing wake command. Run `$U look "$RUN" wake-fail-seed -- /bin/sh -c "cp $D/backup/config $D/backup/config.good && printf 'wake=/usr/bin/false\n' >>$D/backup/config"`, then `$U owner "$RUN" --label wake-fail -- host/bin/ug-backup`, then `$U fault "$RUN" ssh-backup clear` and `$U look "$RUN" wake-fail-restore -- cp $D/backup/config.good $D/backup/config`. Exit 1; stderr `backup-target: the wake command /usr/bin/false failed`.
- **bad-config not sftp.** Run `$U look "$RUN" config-not-sftp-seed -- /bin/sh -c "printf 'repo=/Volumes/backup/ug\n' >$D/backup/config"`, then `$U owner "$RUN" --label config-not-sftp -- host/bin/ug-backup`. Exit 1; stderr `backup-target: $B/owner-home/.local/share/underground/backup/config: repo must be sftp:<user>@<host>:<path>, not '/Volumes/backup/ug'`. No stub calls.
- **bad-config unknown key.** Run `$U look "$RUN" config-unknown-seed -- /bin/sh -c "cp $D/backup/config.good $D/backup/config && printf 'speed=fast\n' >>$D/backup/config"`, then `$U owner "$RUN" --label config-unknown -- host/bin/ug-backup`. Exit 1; stderr `backup-target: .../backup/config: unknown key speed`.
- **bad-config no `=`.** Run `$U look "$RUN" config-noeq-seed -- /bin/sh -c "cp $D/backup/config.good $D/backup/config && printf 'wake\n' >>$D/backup/config"`, then `$U owner "$RUN" --label config-noeq -- host/bin/ug-backup`. Exit 1; stderr `backup-target: .../backup/config: a line without '=': wake`.
- **bad-config missing.** Run `$U look "$RUN" config-missing-seed -- mv $D/backup/config $D/backup/config.off`, then `$U owner "$RUN" --label config-missing -- host/bin/ug-backup`. Exit 1; stderr `ug-backup: no $B/owner-home/.local/share/underground/backup/config; write it in the format that backup_target_read in host/lib/backup-target.bash reads`.
- **bad-config state.** Restore and read. Run `$U look "$RUN" config-restore -- cp $D/backup/config.good $D/backup/config`, then `$U look "$RUN" config-state -- /bin/sh -c "cat $D/backup/last; ls backup-repo/snapshots"`. `last` unchanged; no new snapshot.
- **missing-setup restic.** Run `$U look "$RUN" restic-missing-seed -- /bin/sh -c "cd $D/restic/* && mv restic restic-off"`, then `$U owner "$RUN" --label restic-missing -- host/bin/ug-backup`, then `$U look "$RUN" restic-restore -- /bin/sh -c "cd $D/restic/* && mv restic-off restic && ls -l"`. Exit 1; stderr `ug-backup: the pinned restic $B/owner-home/.local/share/underground/restic/<pin>/restic is missing; run host/bin/ug-setup`. The restore listing shows `restic -> $B/stubs/restic`.
- **missing-setup password.** Run `$U look "$RUN" password-missing-seed -- mv $D/backup/password $D/backup/password.off`, then `$U owner "$RUN" --label password-missing -- host/bin/ug-backup`. Exit 1; stderr `ug-backup: the backup password $B/owner-home/.local/share/underground/backup/password is missing; run host/bin/ug-setup`. An empty file gives the same line: `$U look "$RUN" password-empty-seed -- /usr/bin/touch $D/backup/password`, then `$U owner "$RUN" --label password-empty -- host/bin/ug-backup`. Restore with `$U look "$RUN" password-restore -- mv $D/backup/password.off $D/backup/password`.
- **missing-setup reader.** Run `$U look "$RUN" reader-missing-seed -- mv root/code/bin/agent-home-tar root/code/bin/agent-home-tar.off`, then `$U owner "$RUN" --label reader-missing -- host/bin/ug-backup`, then `$U look "$RUN" reader-restore -- mv root/code/bin/agent-home-tar.off root/code/bin/agent-home-tar`. Exit 1; stderr `ug-backup: the agent home reader $B/root/code/bin/agent-home-tar is missing; run: host/bin/ug-setup`; restic calls stop after `cat config`.
- **missing-setup state.** Run `$U look "$RUN" missing-state -- /bin/sh -c "cat $D/backup/last; ls backup-repo/snapshots; wc -c $D/backup/password"`. `last` unchanged; no new snapshot; password back to 33 bytes.
- **usage.** Run `$U owner "$RUN" --label usage -- host/bin/ug-backup now`. Exit 64; stderr `usage: ug-backup`.
- **recover.** With all faults cleared and files restored, run `$U owner "$RUN" --label recover -- host/bin/ug-backup`, then `$U look "$RUN" recover-state -- /bin/sh -c "cat $D/backup/last; ls backup-repo/snapshots"`. Exit 0 with `recorded the run in ...`; `last` is newer; one more snapshot.
- **Cleanup.** Run `$U down "$RUN"`. It prints `removed /private/tmp/ugv-<RUN>` and `evidence: ~/scratch/verify-underground/<RUN>`.

## Gotchas

- The check subset `NN/100` is the local day of year mod 100, plus 1 (`date +%j`, local time zone, not UTC). The log timestamps are UTC, so near midnight the subset can look one day off. Assert `checked data subset [0-9]+/100`, not a fixed number. There is no date stub, and do not add one.
- `check-fail` leaves a new snapshot in `backup-repo/snapshots` while `last` stays old. Count snapshots and read `last`; do not treat a new snapshot as a good run.
- The restic fault stubs print nothing on stderr, so failure lines end in `): ` with an empty restic message. The real restic text follows the colon on the real host.
- `host-down` with a working `wake=` line and a host that never answers waits 30 × 10 s (5 minutes) before `did not answer ssh after the wake`. That path is not driven here; only the no-`wake=` and wake-fails paths are.
- The live-db writer runs `sleep 120`. Pass the db as the absolute `"$B/..."` path as written: `$U down` kills only processes whose command line names the base, so a relative path would leave `sqlite3` holding the db after the base is gone. If the db seed is older than 2 minutes, the writer has exited and checkpointed, and the `snapshot-db` proof no longer shows a WAL-only row. Seed it just before `first-run`.
- A config error, a missing restic or a missing password makes no stub call at all. Seeing restic or ssh calls in those steps means the wrong file was changed.
- `mv restic-off $D/restic/*/` moves the file into the dir under its own name; restore inside the pin dir (`cd $D/restic/* && mv restic-off restic`) as written above.
- The launchd job (schedule, `backup.log` redirect, running as the owner) is not drivable in the stand-in; only the by-hand run is verified.
- Not proven: real restic against the sftp backup host, real `sudo -u ugagent` policy, and file ownership of the snapshot members.
