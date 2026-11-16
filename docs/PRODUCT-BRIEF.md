# Product brief: underground

This page holds the base: the problem, the user and scope, the north star, the gate, the harms that cannot be undone, what the agent needs to do its work, and for each harm the mechanism that handles it or the name under which it is accepted. History lives in git.

## Problem

The owner runs omp without approvals, but does not trust an unattended run. The owner must watch only to stop harm that cannot be undone. underground makes that harm impossible, undoable, or visible at once, so the owner can let the agent work alone.

## User and scope

- One owner: a solo developer, on one macOS laptop. The agent runs as a macOS user of its own, not as the owner.
- One agent: omp. The owner keeps no other agent on the mac.
- Repos: public for now. A private repo reopens the data-out question.

Two ways of working (owner decision, 2026-11-08):

- **Together.** Design, architecture, specs, ADRs, and the split of user stories into tickets. The owner reads each step, but only after it runs: omp runs tool calls without approvals, so presence stops no call in time. A leak, a force-push, or a write to the owner's files is as irreversible here as in a run alone.
- **On its own.** A ready ticket: the smallest unit of work, with no design decision left in it. Only this part runs unattended.

## North star

The agent works like a coworker. The owner and the agent do the design together; the agent turns each ready ticket into a merged change on its own. Whatever the agent does without the owner's approval, in either way of working, the owner can undo.

## The gate

Before each decision, the agent and the owner ask: does this bring us closer to the north star, or further away? It does only if it stops an irreversible harm, or keeps undo and work possible. If not, it waits. (`AGENTS.md`, "The gate".)

## The harms that cannot be undone

|id|harm|
|---|---|
|H1|Code runs as the owner, or the owner's files, logins, or desktop are read or changed: through a secret left on a command line, a listener the agent stands up, or a stray path.|
|H2|A change reaches code that runs on the host, so a revert cannot undo what already ran.|
|H3|The agent, or a service the setup needs, fails and stays silent, so undo and work stop while nobody knows.|
|H4|The agent destroys data in its own home that the owner cannot rebuild: the session history, `history.db`, unpushed work.|
|H5|The agent sends data it can read to anywhere outside the mac.|
|H6|Model calls and spend run through a credential the agent holds.|
|H7|The agent fills the mac's disk from its home.|

## What the agent needs to do its work

|need|held by|
|---|---|
|Start as its own user, in its own home, on one binary, with the current rules.|The omp launcher (`host/bin/ug-agent`), the session start (`host/agent/agent-start`).|
|A config that resets at each start, so its own edits die with the session.|The staged config copy (`config-names`, `host/agent/agent-start`); `host/bin/ug-agent-setup` stages it.|
|Free read and write inside its own home.|The agent user's file rights.|
|A current clone of each repo, kept current between sessions.|`host/agent/agent-refresh`.|
|Reach GitHub as a GitHub App, with a short list of rights, on the repos the owner picks. Its rights: Contents read and write, Pull requests read and write, Checks read, Commit statuses read, Metadata read. No Workflows, no Administration (the permission steps of `scripts/github-app-wizard.sh`).|The app key that setup gives the agent to read (`root/github-app/`), the token helper (`host/agent/gh-app-token`), and the pinned gh through the `gh` wrapper (`host/agent/gh`).|
|Call models without holding a login.|The auth broker and the auth gateway, run by the login user.|
|Usage numbers.|The usage broker (`host/usage-broker/usage-broker.ts`).|
|Learn at once when something it depends on is broken.|The status lines the launcher passes to the session (`UG_WARNINGS`, `host/bin/ug-agent`) and the watch.|

## The mechanisms

**Agent user**. The agent is a standard, hidden macOS user of its own (the `agent_user` fact, `host/facts`). It starts through a login of its own, never from the owner's terminal, so it shares no screen or desktop session with the owner. A sandbox profile (`host/agent/pin.sb`) holds its writes to its own home. The owner's home is closed to it by file rights. Handles H1. Accepted by name: the agent reads the command lines of the owner's processes, so the rule is "no secret on a command line"; the pin is a wall for file paths only; the agent reads world-readable files outside the homes. Open: the agent's terminal output reaches the owner's terminal app, and an escape code there can write the owner's clipboard.

**Login user**. A second hidden user (`auth_user`, `host/facts`) owns the model logins and the tokens in a home the owner's user cannot read. The login services run as it. The owner cannot run the pinned omp and cannot read the gateway bearer. Handles H1, H6. Accepted by name: the owner through sudo reaches everything; the owner cannot stop it on purpose.

**Least rights for agent input**. A job that reads what the agent makes runs as a user that holds only what the job needs, or it names the threat row that covers it. The lower users now are the agent user and the login user. Two checks hold this, not a sentence. Structure: owner and root code reaches a lower user's home only through `ug_as`, `ug_read_as`, and `ug_write_as` (`host/lib/ug.bash`). Proof: each root setup runs `ug_user_walls` (`host/lib/ug.bash`) as each lower user, and stops when one can list another party's home or, for a service user, read the staged models file. The service table also refuses a job that is not the agent's, reads agent input, and names no threat row (`ug_service_allowed`, `host/lib/ug.bash`). Handles H1 for the jobs in the table. Open by name: the owner's terminal, the owner's scratch restore, the agent sshd, and the login user's services.

**Pinned omp**. One omp binary on the mac, fixed by the version and SHA-256 in `VERSIONS`: setup downloads the file and checks the hash, and root installs it with an owner and mode that admit only the agent user and the login user (`ug_ensure_owner_mode`, `host/bin/ug-agent-setup`). Every session checks its SHA-256 before omp starts (`omp_bin`, `host/agent/agent-start`). The agent cannot change the code its later sessions run, so the owner can trust that the code read after a merge is the code that runs. Handles H2.

**Loopback firewall line**. The sandbox profile (`host/agent/pin.sb`) and one pf line, each checked by setup, refuse the agent user a listener on the auth broker's port (`auth_broker_port`, `host/facts`), so the agent cannot stand in for the broker and take its bearer. Handles H1. Accepted by name: the agent reaches every listener of the owner on loopback; the guard is the owner's rule that no program of the owner listens without a secret.

**GitHub ruleset on main**. On underground, GitHub refuses every merge to `main` without the owner's approval; a push after an approval needs a new one. Setup checks the rule before it pulls. Handles H2. On the other repos the wall is an onboarding check: each workflow that deploys, publishes, or uses secrets on `main` waits for the owner's approval in a GitHub environment, so a merge has no effect that a revert cannot undo. The workflow in `AGENTS.md` still has the owner merge every PR on GitHub; that is a rule, not a wall. Owner decision, 2026-11-15, changes three things, accepted by name: (a) the agent holds the GitHub App key and can send it anywhere; the key does not expire, and the owner replaces it on GitHub. (b) The agent can force-push or delete branches other than underground's `main`, and can push to any branch name. (c) On the other repos the agent can merge a PR; the environment approval above keeps such a merge undoable by a revert. Whether those repos get the `main` rule too is open; the owner decides.

**Backup**. Once a day a restic snapshot of the agent's home goes to a repo on the owner's other machine, which the agent cannot reach. Every snapshot stays. Handles H4. Accepted: harm to work written since the last run. The agent's home path (`agent_home`, `host/facts`) stays the same in every design, for now (owner decision, 2026-11-10). omp saves full paths in its sessions and history (`rewriteSessionText` and `rewriteHistory`, `host/agent/migrate-paths.ts`), so a snapshot restores cleanly only to the path it came from. The one move so far, from the box's home, needs `host/agent/migrate-paths.ts`.

**Failures reach the owner**. Each job leaves a record that only its own user or root can write. The watch reads the records, asks the services, writes a status that the launcher passes to the session, and pings a check outside the mac that alerts when the pings stop. Handles H3.

**State over lists**. A control rots while it still looks good when it trusts a saved list or value instead of the state. These controls read the state, so a change in reality shows at once: GitHub says whether a token is dead; setup checks the real pf anchor, the real ruleset, and the real rights of each file a service runs; setup builds its code folder fresh and removes what this version does not make.

**Data out**. There is no network wall: the agent reaches every site, the LAN, and the tailnet (owner decision). Accepted by name while the repos are public. H5.

**Spend through the bearer**. The gateway bearer is not a control: the agent reads it and can send it anywhere. Accepted: calls and spend through it, up to the cap the owner sets at each provider; nothing in this repo checks that a cap is set. H6.

**Disk**. No cap on the agent's home, by owner decision, 2026-11-08: not needed. H7.

## In redesign

The gh-broker is deleted (owner decision, 2026-11-15). The agent reaches GitHub as the GitHub App, with the token helper and the pinned gh (see the needs table). Auto merge and a merge queue are open and out of scope until the owner redesigns them (owner decision, 2026-11-10). The merge gate is deleted (owner decision, 2026-11-10). The owner merges PRs on GitHub, as the workflow in `AGENTS.md` says; "GitHub ruleset on main" says what the swap changes.
