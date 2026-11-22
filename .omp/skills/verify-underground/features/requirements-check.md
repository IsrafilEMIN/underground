# Requirements check

`agent-check` compares the agent's omp settings and agent-config files with `requirements` and prints one warning line per unmet item. It prints nothing and exits 0 when every item is met. The agent side runs it as `code/bin/agent-check code/requirements` at every session start, and each warning line shows in the agent session as a notice. `host/bin/ug-setup` runs it as the agent at the end of setup and prints each line as an `agent check` warning.

## Sub-features

- `check-met` every setting and file is met: no output, exit 0.
- `check-unmet` one warning per unmet setting: wrong value, unset (no `value`), unknown key.
- `check-missing-file` a `file` line whose path is absent in the agent home: `~/<path> is missing; ...`.
- `check-omp-fails` `omp config list` fails: one `cannot read the omp settings (omp config list failed)` line instead of the setting checks.
- `check-not-json` omp prints something that is not a JSON object: `(omp printed settings that are not json)`.
- `check-bad-line` a line of the requirements file that is neither `setting` nor `file`: `agent-check cannot read this line of ...`.
- `check-usage` two or more arguments: usage on stderr, exit 64.
- `check-unreadable` the requirements file is unreadable or absent: `agent-check: cannot read the requirements file ...` on stderr, exit 1.
- `check-omp` the owner sees the same lines as `omp-stub: warning notice:` lines when they start `omp`.

## How to get to it (user POV)

- The owner runs `omp` (= `host/bin/ug-agent`); the agent session start runs the check and shows each line as a warning notice.
- The agent runs `/Library/Underground/code/bin/agent-check /Library/Underground/code/requirements` in its own shell.
- The owner runs `host/bin/ug-setup`; its last step `agent check` prints `every requirement is met` or one warning per line. Not drivable in the stand-in (real users and `sudo`); only `host/bin/ug-setup x` (exit 64, usage) runs.

## Driving it with ugv

Preconditions:

- Repo root; `U=.omp/skills/verify-underground/scripts/ugv`, `RUN=$(date +%Y%m%d-%H%M%S)-reqcheck`, `$U up "$RUN"`, `B=/private/tmp/ugv-$RUN`.
- `$U doctor "$RUN"` ends with `doctor: ok`.
- Baseline from `ugv up`: `$B/fixtures/omp-config.json` meets every `setting` line, every `file` line exists under `$B/agent-home`, no faults. Run the bullets in this order; each one keeps the state of the ones before it.

- **All met (`check-met`).** The agent runs the check. Run `$U agent "$RUN" --label check-met -- code/bin/agent-check "$B/root/code/requirements"`. Exit `0`, empty stdout and stderr; the only stub call is `omp: ... argv=config list --json`. The same result from the code dir: `$U agent "$RUN" --label check-met-cwd --cwd root -- code/bin/agent-check code/requirements` (exit `0`, no output).
- **Look: met settings.** Run `$U look "$RUN" check-met -- /usr/bin/jq -c . fixtures/omp-config.json`. One line: `{"memory.backend":{"value":"mnemopi"},"mnemopi.scoping":{"value":"global"},"mnemopi.autoRetain":{"value":"false"},"mnemopi.noEmbeddings":{"value":"true"},"skills.enabled":{"value":"true"}}`.
- **Owner launch, all met (`check-omp`).** The owner starts `omp`. Run `$U owner "$RUN" --label check-omp-met -- host/bin/ug-agent`. Exit `0`; stdout is `omp-stub: session started in $B/agent-home/scratch` and only one notice, `omp-stub: warning notice: no good backup yet; read .../backup/backup.log`. No requirement notice.
- **Seed unmet settings.** Make one value wrong, one unset and one unknown to this omp. Run `$U look "$RUN" seed-unmet -- /bin/bash -c '/usr/bin/jq ".\"memory.backend\".value = \"local\" | del(.\"mnemopi.scoping\".value) | del(.\"skills.enabled\")" fixtures/omp-config.json > fixtures/omp-config.new && mv fixtures/omp-config.new fixtures/omp-config.json && cat fixtures/omp-config.json'`. The file shows `"memory.backend": {"value": "local"}`, `"mnemopi.scoping": {}` and no `skills.enabled` key.
- **Unmet settings (`check-unmet`).** Run `$U agent "$RUN" --label check-unmet -- code/bin/agent-check "$B/root/code/requirements"`. Exit `0`, empty stderr, stdout has exactly three lines in requirements order:
  `memory.backend is local; underground needs mnemopi: the nightly dream reviews and consolidates the agent's mnemopi memory. set it in your agent-config config.yml`
  `mnemopi.scoping is unset; underground needs global: the dream reads one shared memory bank, not one bank per project. set it in your agent-config config.yml`
  `skills.enabled is not a setting of this omp; underground needs true: the review flow loads the dream-review skill when the user says 'review the dream'. update omp`
- **Owner launch, unmet (`check-omp`).** Run `$U owner "$RUN" --label check-omp-warn -- host/bin/ug-agent`. Exit `0`; after the backup notice, stdout has the three lines above, each prefixed `omp-stub: warning notice: `. The `ssh` call note carries only `UG_NOTICES=no\ good\ backup\ yet...`; the three lines are added on the agent side.
- **Look: what the session got.** Run `$U look "$RUN" check-omp-warn -- /usr/bin/grep -c 'underground needs' calls/omp.log`. Prints `1`: the one `UG_NOTICES=$'no good backup yet; ...\nmemory.backend is local; ...\nmnemopi.scoping is unset; ...\nskills.enabled is not a setting of this omp; ...'` note of the session call.
- **Seed a missing file.** Move the guard extension out of the agent-config. Run `$U look "$RUN" seed-missing-file -- mv agent-home/.omp/agent/extensions/underground-guard.ts agent-home/.omp/underground-guard.ts.away`. Exit `0`.
- **Missing file (`check-missing-file`).** Run `$U agent "$RUN" --label check-missing-file -- code/bin/agent-check "$B/root/code/requirements"`. Exit `0`; the first stdout line is `~/.omp/agent/extensions/underground-guard.ts is missing; underground needs it: this extension blocks destructive commands of the agent. add it to your agent-config`, followed by the three setting lines.
- **Look: file is gone.** Run `$U look "$RUN" check-missing-file -- ls -A agent-home/.omp/agent/extensions`. Exit `0`, empty stdout.
- **omp fails (`check-omp-fails`).** Run `$U fault "$RUN" omp-config 1`, then `$U agent "$RUN" --label check-omp-fails -- code/bin/agent-check "$B/root/code/requirements"`. Exit `0`; stdout is the `~/.omp/agent/extensions/underground-guard.ts is missing; ...` line and `agent-check cannot read the omp settings (omp config list failed), so 5 settings that underground needs are not checked`. Stub calls show `omp: ... argv=config list --json` and `omp:   fault omp-config: exit 1`.
- **Owner launch, omp fails (`check-omp`).** Run `$U owner "$RUN" --label check-omp-fails-launch -- host/bin/ug-agent`. Exit `0`; stdout has `omp-stub: warning notice: ~/.omp/agent/extensions/underground-guard.ts is missing; ...` and `omp-stub: warning notice: agent-check cannot read the omp settings (omp config list failed), so 5 settings that underground needs are not checked`.
- **Look: fault state.** Run `$U look "$RUN" check-omp-fails -- cat faults/omp-config`. Prints `1`. Then `$U fault "$RUN" omp-config clear` prints `fault omp-config cleared`.
- **Seed non-JSON settings.** Run `$U look "$RUN" seed-not-json -- /bin/bash -c 'printf "omp: config store locked\n" > fixtures/omp-config.json && cat fixtures/omp-config.json'`. Prints `omp: config store locked`.
- **Non-JSON (`check-not-json`).** Run `$U agent "$RUN" --label check-not-json -- code/bin/agent-check "$B/root/code/requirements"`. Exit `0`; stdout is the missing-file line and `agent-check cannot read the omp settings (omp printed settings that are not json), so 5 settings that underground needs are not checked`. A JSON value that is not an object gives the same line: `$U look "$RUN" seed-array -- /bin/bash -c 'printf "[]\n" > fixtures/omp-config.json'`, then `$U agent "$RUN" --label check-array -- code/bin/agent-check "$B/root/code/requirements"`.
- **Look: fixture.** Run `$U look "$RUN" check-not-json -- cat fixtures/omp-config.json`. Prints `[]`.
- **Bad line (`check-bad-line`).** Run `$U look "$RUN" seed-bad-line -- /bin/bash -c 'printf "file .omp/agent/skills/dream-review/SKILL.md: needed\nsetting broken line\n" > agent-home/reqs-bad && cat agent-home/reqs-bad'`, then `$U agent "$RUN" --label check-bad-line -- code/bin/agent-check "$B/agent-home/reqs-bad"`. Exit `0`, no stub call (no `setting` line parsed), stdout is only `agent-check cannot read this line of $B/agent-home/reqs-bad: setting broken line`.
- **Usage (`check-usage`).** Run `$U agent "$RUN" --label check-usage -- code/bin/agent-check a b`. Exit `64`, empty stdout, stderr `usage: agent-check [requirements-file]`, no `--- stub calls` block.
- **Look: no omp call.** Run `$U look "$RUN" check-usage -- /usr/bin/grep -c 'argv=config list --json' calls/omp.log`. Prints the same count as before the usage step: `10` when every bullet above ran once, including `check-met-cwd` and `check-array`; `check-bad-line` adds no call.
- **Unreadable (`check-unreadable`).** Run `$U look "$RUN" seed-unreadable -- /bin/bash -c 'cp root/code/requirements agent-home/reqs-locked && chmod 000 agent-home/reqs-locked && ls -l agent-home/reqs-locked'` (shows `----------`), then `$U agent "$RUN" --label check-unreadable -- code/bin/agent-check "$B/agent-home/reqs-locked"`. Exit `1`, empty stdout, stderr `agent-check: cannot read the requirements file $B/agent-home/reqs-locked`. An absent file gives the same: `$U agent "$RUN" --label check-absent -- code/bin/agent-check "$B/agent-home/no-such-file"` exits `1` with `agent-check: cannot read the requirements file $B/agent-home/no-such-file`.
- **Owner launch, unreadable requirements (`check-omp`).** Run `$U look "$RUN" seed-code-unreadable -- chmod 000 root/code/requirements`, then `$U owner "$RUN" --label check-omp-unreadable -- host/bin/ug-agent`. Exit `0`; the session starts with only the backup notice. The owner sees no sign of the failed check.
- **ug-setup entry.** Run `$U owner "$RUN" --label check-ug-setup-usage -- host/bin/ug-setup x`. Exit `64`, stderr `usage: ug-setup`. Its `agent check` step is not driven; report it as not verified.
- **Clean up.** Run `$U down "$RUN"`. Prints `removed $B` and `evidence: ~/scratch/verify-underground/$RUN`.

## Gotchas

- `$U agent` resolves only the command (`code/...`), not its arguments, and its cwd is `agent-home`. `code/bin/agent-check code/requirements` there exits `1` with `agent-check: cannot read the requirements file code/requirements`. Pass `"$B/root/code/requirements"` or add `--cwd root`.
- With no argument, `agent-check` looks for `requirements` next to itself (`code/bin/requirements`), which the install does not have: exit `1`, `agent-check: cannot read the requirements file $B/root/code/bin/requirements`. Every caller passes `code/requirements`, so always pass it.
- Warnings go to stdout with exit `0`; only usage (`64`) and an unreadable requirements file (`1`) fail. Judge a step by its stdout lines, not its exit code.
- Only keys named in `requirements` are checked. Adding a made-up key to the fixture changes nothing; to get the `is not a setting of this omp` line, delete a required key (`skills.enabled`) from `fixtures/omp-config.json`.
- `omp config list` failing or printing non-JSON skips all setting checks, but `file` lines are still checked first, so the missing-file line still prints.
- At session start the check's stderr and exit code are dropped. An unreadable requirements file gives no notice at all; prove that case with `$U agent ... code/bin/agent-check`, not with `omp`.
- The requirement lines are not in the `ssh` call's `UG_NOTICES` note (that holds only owner-side notices such as the backup age). Prove them in `calls/omp.log` and the `omp-stub: warning notice:` lines.
- Fixture edits and `omp-config` faults persist until `down`. Clear the fault before the next bullet; `fault omp-config` also makes `omp config get` fail.
- The underground guard blocks commands that contain `rm`; move files away with `mv` and let `$U down` remove the base.
- `host/bin/ug-setup` runs the check as the agent through `sudo`; the stand-in cannot run that path. Do not run `ug-setup` without arguments.
