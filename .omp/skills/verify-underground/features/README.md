# Underground verification map

This directory is the maintained source for verifying the user-facing behavior of the Underground host scripts. Read the index before driving, then use the matching feature file as the recipe. The harness and stand-in layout are in [../SKILL.md](../SKILL.md).

## Baseline preconditions

- Work from the repo root of the worktree under test. Set `U=.omp/skills/verify-underground/scripts/ugv`.
- Build a fresh stand-in per run: `RUN=$(date +%Y%m%d-%H%M%S)-<feature>` and `$U up "$RUN"`. Base is `/private/tmp/ugv-$RUN`; this map writes it as `B=/private/tmp/ugv-$RUN`.
- `$U doctor "$RUN"` ends with `doctor: ok` before the first drive.
- The baseline from `ugv up`: no backup has run (`backup/last` is missing), `sources` lists nothing, no repo exists, every omp setting in `host/requirements` is met, all files in `host/requirements` exist in the agent home, no dream has run, no faults are set.
- Never drive the real install (`/Library/Underground`, real `HOME`, real `sudo`). Never drive a stand-in that another run created.

## Driving conventions

- Start every recipe from a fresh `ugv up` unless its preconditions say otherwise. Faults and seeded files stay until `down`.
- Owner actions go through `$U owner "$RUN" -- host/bin/...`; agent actions through `$U agent "$RUN" -- code/...`; observations through `$U look "$RUN" <label> -- <cmd>`.
- Give every step a `--label` that names the sub-feature ID, so the evidence dir reads as the proof.
- Treat commands as literal. Quoted strings and flags are exact.
- Seed state with plain writes under `$B`; make the write a `look` step when the seeded value is part of the proof.
- `$U down "$RUN"` at the end, and after every failed attempt.

## Proof and skip reporting

- Each sub-feature proof is: the action step (command, stdout, stderr, exit), its stub calls, and a `look` step that reads the resulting state.
- Notices are proven by the `UG_NOTICES=...` note in the step's `calls/omp.log` (what the agent session received) and, for notices made on the owner side, in `calls/ssh.log` (what the launcher sent). The `omp-stub: warning notice:` stdout lines are a convenience; `ug-notices.ts` never runs in the stand-in.
- A step that exits as expected but leaves the wrong state is a failure.
- Record the RUN id and the evidence dir in your report.
- Report an unreachable path with the attempted command and the unmet precondition. Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with ugv` starts with `Preconditions:` and uses labeled bullets that pair each user action with an exact command and observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

Keep implementation details out of the map. Name only user paths, stable handles (messages, file paths, exit codes), required state, commands, and observable proof.

## Features

- [Start an agent session](./launch-agent.md) covers the owner's `omp` launcher: in and outside a repo, argument forwarding, refusals, and the backup-age notices.
- [Session start notices and repo sync](./session-start.md) covers what the agent side does at each start: notices from the dream, the requirements check and the last fetch, the first clone, and the background fetch and cleanup.
- [Sync source repos to the agent](./sync-sources.md) covers the owner's `sources` list, unpacked into the agent home at every launch.
- [Back up the agent home](./backup.md) covers the daily `ug-backup`: first-run repo creation, snapshot contents, retries, check failure, and the `last` record.
- [Nightly dream](./dream.md) covers `agent-dream`: skip, success report, failures, and the lock.
- [Requirements check](./requirements-check.md) covers `agent-check` warnings for omp settings and agent-config files.

## Not drivable in the stand-in

- `host/bin/ug-setup`, `host/bin/ug-agent-setup`: real users, launchd, sudoers, downloads. Only their usage errors can be driven (`$U owner "$RUN" -- host/bin/ug-setup x` exits 64 with `usage: ug-setup`).
- `host/bin/ug-auth`: needs `sudo -u ugauth` and the running auth broker. Only validation (`ug-auth bogus`, `ug-auth revoke abc` exit 64) runs; the `sudo` stub refuses the rest.
- The auth broker, auth gateway and usage broker daemons.
