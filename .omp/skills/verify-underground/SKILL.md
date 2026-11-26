---
name: verify-underground
description: Drive the Underground host scripts (ug-backup, ug-sync, and the agent-side agent-start session start that omp runs in the agent's Tern shell, agent-dream, agent-check, agent-unpack) end to end in a disposable stand-in host under /tmp, with stubs only at sudo, launchd, the backup host's ssh, GitHub and the omp model binary. Reach for it to prove a change to host/ works the way the owner or the agent experiences it, without touching the real /Library/Underground install.
---

# Verify Underground

Underground is a macOS host kit, not a server. Its users touch command-line tools:

- The **owner** (an admin account) runs `host/bin/ug-setup` once. He then adds the remote host `ugagent@<mac tailscale ip>:18376` in his Tern app on the mac and the phone (the phone's key is in `host/tern-keys`) and types `omp` in that shell to start an agent session. launchd runs `host/bin/ug-backup` daily and `host/bin/ug-sync` every 5 minutes as the owner. `host/bin/ug-auth` manages model credentials.
- The **agent** (user `ugagent`) gets its shell from the `com.underground.agent-tern` daemon (`code/agent-tern`, `tern remote serve --user`). Its zsh files (`code/zsh`) load `code/agent-env` and put `code/session-bin` first, so `omp` is `code/session-bin/omp` → `code/agent-start` → omp, with warning notices, in the folder where it was typed. launchd runs `code/agent-dream` nightly. `code/bin/agent-check` reports missing omp settings, agent-config files and skills.

The real install is one per machine (users `ugagent`/`ugauth`, `/Library/Underground`, system LaunchDaemons, Tern on UDP 18376, which `code/pf.conf` opens to loopback and the tailnet only). It cannot run twice, and it belongs to the user. **Never drive it**: do not run `ug-setup`, `ug-agent-setup`, `ug-auth`, `ug-sync` or `sudo` against it, and do not run host scripts with your real `HOME`. Verify in a stand-in instead.

## How the stand-in works

`scripts/ugv up RUN` builds `/tmp/ugv-RUN/` (`/private/tmp/...` on macOS):

| path | what it is |
|---|---|
| `src/` | copy of this worktree's `host/` and `VERSIONS`, including uncommitted edits; `src/host/facts` points `root`, `agent_home`, `auth_home` into the base and every port at 9 |
| `root/code/` | `host/agent/*` rendered with the repo's own `ug_render` and laid out like the agent code step of `host/bin/ug-agent-setup` (`agent-start`, `agent-env`, `agent-dream`, `agent-tern` (rendered, never run), `requirements`, `ug-notices.ts`, `session-bin/omp` → `agent-start`, `zsh/{.zshenv,.zprofile,.zshrc}`, `authorized_keys/ugagent`, `bin/{omp,gh,agent-check,agent-home-tar,agent-unpack}`; no `bin/tern`) |
| `root/gateway-token`, `root/logs/`, `root/status/` | what `agent-env` and `agent-start` read; `ug-backup` writes `status/backup-last` |
| `owner-home/` (mode 700) | owner `HOME`; `.ssh/id_ed25519` (its public key and the keys in `host/tern-keys` are in `root/code/authorized_keys/ugagent`, as setup copies them for Tern); `.local/share/underground/` holds an empty `sources`, `backup/{password,config}` and the pinned restic path |
| `agent-home/` (mode 700) | the agent `HOME`; `.omp/agent/` has placeholder files for the `file` lines of `host/requirements` and a placeholder `skills/<name>/SKILL.md` for each `skill <name>` line (scaffolding); `.gitconfig` rewrites `https://github.com/` to `origins/`, so the background sync of a `ugv repo` clone stays offline |
| `stubs/` | first on the owner `PATH` (see below) |
| `calls/<stub>.log` | every stub call: time, cwd, argv, notes |
| `fixtures/` | `omp-config.json` (meets `host/requirements`), `omp-plugins.json` (no plugins: `{"npm":[],"marketplace":[]}`), optional `omp-answer.md`, `gh-pr-list` |
| `faults/` | `ugv fault` files that make a stub fail |
| `backup-repo/` | the restic stand-in; `snapshots/NNN.tar` are the real `agent-home-tar` streams |
| `origins/`, `seeds/` | local bare repos and their seed checkouts from `ugv repo`; the agent clone is `agent-home/work/<owner>/<name>` |

Stubs replace only production boundaries. Everything between them is the real code under test:

| stub | behavior |
|---|---|
| `ssh` | only `ug-backup` calls it, for the backup host: exit 0 (fault `ssh-backup`). Nothing reaches the agent over ssh |
| `sudo` | `sudo -n -u USER [-H] CMD` runs CMD with a reset env when CMD is inside the base; anything else is refused (exit 1) |
| `launchctl` | `print` exits 113 (not loaded); every other verb is refused |
| `nc` | the port answers |
| `restic` | local repo in `backup-repo/`; `backup --stdin-from-command -- CMD` really runs CMD and stores its stdout |
| `omp` (`root/code/bin/omp`) | `config list --json` → `fixtures/omp-config.json`; `config get` → `(not set)`; `plugin list --json` → `fixtures/omp-plugins.json`; a session prints `omp-stub: session started in <cwd>` and one `omp-stub: warning notice: <line>` per `UG_NOTICES` line, as `ug-notices.ts` would show them; `-p` prints `fixtures/omp-answer.md`; all record `HOME`, `UG_NOTICES`, gateway token presence, broker URL |
| `gh` | `pr list` prints `fixtures/gh-pr-list`; everything else is refused |

Fault names for `ugv fault RUN NAME RC|clear`: `sudo`, `launchctl`, `launchctl-print`, `ssh`, `ssh-backup`, `nc`, `restic`, `restic-cat`, `restic-init`, `restic-unlock`, `restic-backup`, `restic-check`, `omp`, `omp-config` (`omp config ...`), `omp-plugins` (`omp plugin ...`), `gh`.

## Launch

Requires macOS (`lockf`, BSD `stat`, `/usr/bin/jq`, `/usr/bin/sqlite3`, `openssl`, `ssh-keygen`). No root, no network.

```bash
U=.omp/skills/verify-underground/scripts/ugv   # from the repo root
RUN=$(date +%Y%m%d-%H%M%S)-myfeature
$U up "$RUN"
```

Ready means the last line block starts with `ready: run=$RUN` and lists `base=`, `evidence=` and `src=<HEAD> <dirty-hash>`. The base dir is complete only then (`meta/ready` exists). `up` refuses an existing RUN; pick a new one.

The stand-in tests the code as it was at `up`. After you edit `host/`, run `ugv down` and `ugv up` again; `doctor` flags the drift.

Optional baseline gate: `/bin/bash tests/run` (about 2 minutes, all `ok`, exit 0) proves the checkout itself is sound before you blame the stand-in.

## Doctor

```bash
$U doctor "$RUN"
```

Read-only. It prints run, base, evidence, the source state, active faults and live processes of the run, and ends with `doctor: ok` (exit 0) or `doctor: FAIL` plus one line per problem (exit 1). It checks that `src/host/facts` points into the base, that no rendered file in `root/code` names `/Library/Underground` or `/Users/ugagent`, that `code/bin/omp` is the stub, that `code/session-bin/omp` points at `code/agent-start`, that the three `code/zsh` files exist, that all stubs exist, that `owner-home` is mode 700, the macOS tools, and that the worktree has not changed since `up`. Run it first, and again whenever a result looks off.

## Drive

Each drive is one captured step:

```bash
$U owner "$RUN" [--label L] [--cwd DIR] [--env K=V]... -- CMD [ARGS...]   # as the owner
$U agent "$RUN" [--label L] [--cwd DIR] [--env K=V]... -- CMD [ARGS...]   # as ugagent
$U look  "$RUN" LABEL -- CMD [ARGS...]                                   # read-only observation
```

- `host/...` resolves to `src/host/...`; `code/...` resolves to `root/code/...`. `--cwd` is relative to the base.
- `owner` runs with `env -i HOME=owner-home PATH=stubs:/usr/bin:/bin:/usr/sbin:/sbin TERM=dumb NO_COLOR=1`, an empty git config and `GIT_CEILING_DIRECTORIES=/tmp`, in `owner-home` by default. This is the owner's shell.
- `agent` runs with `env -i HOME=agent-home USER=ugagent PATH=/usr/bin:/bin:/usr/sbin:/sbin`, in `agent-home` by default. This is what a Tern shell (before its zsh files run) and launchd give the agent scripts. The owner's `omp` in the Tern shell is `$U agent "$RUN" --cwd <folder> -- code/session-bin/omp [ARGS...]`; the folder decides the repo. To run the zsh files too, add `--env ZDOTDIR=$B/root/code/zsh` and run `/bin/zsh -i -c 'omp ...'`.
- `look` runs CMD in the base with your own env; use it for `cat`, `ls`, `tar -tf`, `git -C`.
- stdin passes through, so `$U agent "$RUN" -- code/bin/agent-unpack apps/x < some.tar` works.

Fixture helpers:

```bash
$U repo "$RUN" acme/widget      # bare origin + seed + agent clone agent-home/work/acme/widget (on main, origin https://github.com/acme/widget.git)
$U git  "$RUN" -- -C seeds/acme/widget commit --allow-empty -qm next   # git with an isolated identity, cwd = base
$U git  "$RUN" -- -C seeds/acme/widget push -q origin main
$U fault "$RUN" restic-backup 1  # make a stub fail; `clear` removes it
$U calls "$RUN" [stub]           # all stub calls so far
```

Seed other state with plain file writes under the base (paths in the table above), for example `date +%s > /tmp/ugv-$RUN/root/status/backup-last`. Do each write through `ugv look` when the write itself is part of the proof.

The feature recipes are in [features/README.md](features/README.md). Read the index, then the feature file.

## Evidence

Every `owner`/`agent`/`look` call writes `steps/NN-<label>/` under the evidence dir, `${UGV_EVIDENCE:-$HOME/scratch/verify-underground}/$RUN/`:

- `command.txt`: the exact argv run
- `stdout.txt`, `stderr.txt`, `exit.txt`
- `calls/<stub>.log`: only the stub calls this step made (the side effects at the boundaries)

It also echoes all of it to your terminal. `ugv down` adds `final/` with all call logs, the source state and a file tree of the owner home, agent home, logs, origins and backup repo.

Proof standards:

- Drive the user path: `code/session-bin/omp` from the folder the owner would `cd` to, not `code/agent-start` with a made-up environment; `host/bin/ug-sync` and `host/bin/ug-backup` as the owner, as launchd runs them.
- Capture the action and the resulting state: the step for the command, then a `look` step that reads the files it wrote (`backup/last`, `status/backup-last`, `snapshots/*.tar`, `.git/ug-fetch.status`, `.git/ug-reset.summary`, `dreams/*.md`, unpacked files).
- Check side effects in `calls/`: the `UG_NOTICES` the omp session got, the restic subcommands, the sudo targets, the refused calls.
- A stub is a boundary, not the proof. The proof is what the real script did with the stub's answer.
- Report a skipped entry point as skipped. Never report it as verified through another path.

## Cleanup

```bash
$U down "$RUN"
```

It waits up to 5 s for processes whose command line names the base (for example the background sync that `agent-start` leaves), then kills only those pids, copies call logs and the tree to `final/`, and removes `/tmp/ugv-$RUN`. It never touches the evidence dir. It prints `evidence: <dir>`; check that dir still holds `steps/` before you report. Run `down` after every failed attempt as well. If it reports surviving processes, it keeps the base; inspect them with `ps -p <pid>`.

## What the stand-in does not prove

These steps run only on the real host, by the owner. Report them as not verified:

- `host/bin/ug-setup` and `host/bin/ug-agent-setup`: user creation, `/Library/Underground` install with root ownership and modes, the root-owned Tern.app copy, sudoers, sshd deny file, pf rules, LaunchDaemons/LaunchAgents load, `tern remote trust`, downloads of the pinned omp/gh/restic.
- The Tern daemon and app (`code/agent-tern`, key login from `authorized_keys`, the UDP health probe) and the real `sudo` policy; the stand-in plays the Tern shell with `ugv agent`, and the `sudo` stub only mimics the policy.
- `host/bin/ug-auth`, the auth broker, gateway and usage broker (`host/usage-broker/`).
- restic against the sftp backup host, GitHub (`gh`, `gh-app-token`, fetches from github.com), and the omp TUI with a real model call.
- File ownership: everything in the stand-in belongs to the user running `ugv`.
- `host/agent/ug-notices.ts`: the omp stub prints the notices itself, so a broken extension still passes. The notice proof is the `UG_NOTICES` value in the step's `calls/omp.log`; only a real omp with `--extension` exercises the extension.

Read-only checks on the real install are fine when a task needs them: `ls -l /Library/Underground/code`, `readlink /Library/Underground/code/bin/omp`, `cat /Library/Underground/code/facts`.

## Helpers

| file | use |
|---|---|
| `scripts/ugv` | the harness; `$U help` prints usage |
| `scripts/stub-lib.bash` | shared head of every stub (logging, `fault`) |
| `scripts/stubs/<name>` | stub bodies; `ugv up` writes them into `stubs/` with the base baked in |
