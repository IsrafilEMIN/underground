# underground

A safe environment for the omp coding agent on one macOS laptop. The owner designs with the agent. The agent then implements ready tickets on its own, up to the merge. The design is in `docs/PRODUCT-BRIEF.md`. Terms describe what runs today. Where a part is being redesigned (`AGENTS.md`, "Redesign phase"), the term says "In redesign." Sessions run as the agent user.

## Language

### Places

**Host**:
The owner's macOS user session, apart from the agent user. Only the owner runs commands on the host.
_Avoid_: outside, plain terminal (as a place)

**Agent home omp binary**:
The one omp file on the mac. It is in the `omp/<pin>` folder of the root folder (`root`, `host/facts`). Only the agent user and the login user can run it. Its pinned SHA-256 is in `omp.sha256` beside it. Setup downloads it, and `ug-agent-setup` installs it as root (`omp_bin`, `host/bin/ug-agent-setup`). Each agent session checks its hash at start (`omp_bin`, `host/agent/agent-start`). The login services run it too.
_Avoid_: omp copy

**omp launcher**:
`host/bin/ug-agent`, linked as `~/.local/bin/omp`. Typing `omp` logs in as the agent user and starts the agent home omp binary there. The launcher is not omp.
_Avoid_: ug-agent command

**Agent user**:
The macOS user `ugagent` (`agent_user`, `host/facts`). It is standard and hidden. Its home is `agent_home`. It logs in through its own sshd on the agent sshd port (`agent_sshd_port`, `host/facts`), set up by `host/bin/ug-agent-setup`.
_Avoid_: agent account, bot user

**Login user**:
The hidden macOS user `ugauth` (`auth_user`, `host/facts`). It owns the model logins and the two bearer tokens, in its home `auth_home`. It runs the auth broker, the auth gateway, and the usage broker as LaunchDaemons. The owner's user cannot read its home.
_Avoid_: auth root, ug-auth profile

**Data folder**:
The owner's data folder `owner_data` (`host/facts`), mode 700. It holds a new GitHub App key and client ID until setup installs them in the root folder, the backup settings and password, the agent's ssh key, the addresses file, `config-repo`, the pinned restic, and setup's copy of the service code. It does not hold the model logins; the login user owns those.
_Avoid_: vault, keys dir

**Owner's home**:
The owner's home folder, outside the data folder. It holds the owner's checkouts, the config repo, `~/.ssh`, `~/Library`, and the rest. The agent user and the login user cannot read it (mode 700).
_Avoid_: host files, user space

**Owner's checkout**:
The owner's own Git checkout of a repo, in the owner's home. Setup runs from underground's checkout. It copies the code that the services need into the data folder (`install_service_code`, `host/bin/ug-setup`).
_Avoid_: repo folder, main checkout, primary checkout

**Agent clone**:
The agent user's clone of one repo, at `work/<owner>/<repo>` in the agent home (`clone`, `host/agent/agent-start`). The agent never works in the owner's checkout.
_Avoid_: task clone, copy, mirror

**Agent worktree**:
A Git worktree that a session makes from its clone, on its own `wt/<timestamp>` branch, under omp's default worktree folder `~/.omp/wt` [inference] in the agent home (`AGENTS.md`, "Work a change"). Everything in it is agent-written. Other sessions can write it too.
_Avoid_: ticket worktree, workspace

**Omp root**:
omp's default root, `~/.omp`. For the agent user it is `.omp` in the agent home. At each start, `config-names` in `host/agent/agent-start` copies the config names from the root folder into `~/.omp/agent`. omp runs on it unchanged, on its default profile.
_Avoid_: role home, profile, owner part

**Config repo**:
The owner's private repo of agent configs, in the owner's home, named by the first line of `config-repo` in the data folder (`config-repo`, `host/bin/ug-agent-setup`). It holds skills, hooks, `AGENTS.md`, `config.yml`, `models.yml` with the gateway markers, and other settings, laid out like omp's `~/.omp/agent`. It holds what the agent does inside the walls; underground holds the walls. It holds no secret: `ug-agent-setup` refuses a link, a special file, or a token in it (`vet_item`, `host/bin/ug-agent-setup`). Setup stages its last commit into the root folder (`stage_config`, `host/bin/ug-agent-setup`). The owner's local folder is the source of truth. GitHub keeps a private backup.
_Avoid_: dotfiles, role config

**Skill repo**:
An owner's repo of skills, kept apart from the config repo. The config repo's `skill-repos` file names one path per line, read at its last commit. Setup takes only paths inside the owner's home, after it resolves links. It keeps each folder with a `SKILL.md` at its top or under `skills/`, and refuses a link, a special file, or a token in it. A name that the config repo or an earlier skill repo already has stops setup (`stage_config`, `host/bin/ug-agent-setup`).
_Avoid_: skill pack, plugin

### Running omp

**Version pin**:
A version and a SHA-256 in `VERSIONS`. Setup downloads the pinned omp, checks its hash, and installs it as the agent home omp binary.
_Avoid_: lock, current version

**Vanilla omp**:
An omp that the owner starts by its full path, outside any session. It finds no login and no bearer, because the login user owns both. It still finds the keyless built-in providers (`apple`, and a local `lm-studio`, `ollama`, or `llama.cpp` server), unless `~/.omp/agent/config.yml` turns them off.
_Avoid_: raw omp, plain omp, unwrapped session

**ug-auth**:
The owner's command for the auth services. `ug-auth login <provider>` runs the OAuth login of a provider. `ug-auth key ANTHROPIC_API_KEY` stores an API key: the login user's shell reads it hidden from the terminal and hands it to `omp auth-broker migrate --from-local --include-env` in its environment, so the key is in no argument, file, or shell history (`UG_KEY_NAME`, `host/bin/ug-auth`). `ug-auth list` shows each active credential of the auth broker, with its id, provider, type, and account. An API key shows only its first and last characters. `ug-auth revoke <id>` turns off that one credential. Any other command runs the agent home omp binary as the login user through `sudo` (`host/bin/ug-auth`).
_Avoid_: vanilla omp, admin omp

**Agent home backup**:
The daily restic snapshot of the agent home. It goes to one repo on the owner's other machine. The tar stream is read through `agent-home-tar` (`host/agent/agent-home-tar`), which runs as the agent user, and the job is in `host/services`. Settings are in `~/.local/share/underground/backup/config` (`host/bin/ug-backup`). The repo keeps every snapshot, so harm to the home can be undone.
_Avoid_: archive, sync, Time Machine

**Setup**:
The host script that does what `git pull` cannot. It downloads the pinned omp and restic, makes the data folder and the backup password, and runs `sudo host/bin/ug-agent-setup`. That step asks for the owner's password. It installs the agent home omp binary, the agent user, the login user and its services, the GitHub App key, the `gh` wrapper and the token helper, the omp launcher, and the backup helper. Then it restarts the host services and checks, as the owner, that the owner cannot run omp or read a login or the bearer (`check_walls`, `host/bin/ug-setup`). It then runs the walls check for the lower users (`ug_user_walls`, `host/lib/ug.bash`), which tests from each service user and the agent user that none can list or read another party's home or the staged models file. It first fast-forwards `main` in its own checkout from `origin`. It runs no tests. It runs when underground's `main`, a pin, a host service, or macOS changes.
_Avoid_: install, installer, bootstrap

**Crossing**:
A way into or out of the agent's sessions: code out, model calls, `/usage`, web out, config in, repos in, unix sockets, localhost, and merge effects. Each crossing has one control [inference: a principle of an earlier brief, not in the current one].
_Avoid_: hole, exception, bypass

### GitHub and the merge

**Reviewer role**:
One of `code-review`, `security-review`, and `risk-review`. A reviewer is a skill from the config repo, not a separate session. Any omp session can run it, with the same home and trust level as every other session. It reads a PR with `gh pr checkout <n>` or `gh pr diff <n>` and gives its findings to the author. It is a quality step, not a safety wall.
_Avoid_: reviewer session, review agent, bug bot, security bot

**GitHub App**:
The GitHub App that the agent acts as, through the pinned gh and git. The owner's personal account owns it. It is installed only on the repos the owner selects, and its rights are in `docs/PRODUCT-BRIEF.md`, "What the agent needs to do its work". The owner makes its key with `scripts/github-app-wizard.sh`. GitHub shows the app's actions as `<app slug>[bot]`.
_Avoid_: bot account, bot token, machine user, service account

**App key**:
The private key of the GitHub App, `github-app.pem`, and its client ID in `github-app.json`. Setup installs them in the root folder (`github-app/`, `host/bin/ug-agent-setup`). The agent user reads them and cannot change them. The agent can send them anywhere, and the key does not expire: the owner replaces it on GitHub (`docs/PRODUCT-BRIEF.md`, "GitHub ruleset on main").
_Avoid_: PEM, secret, bot key

**Token helper**:
`host/agent/gh-app-token`, installed as `code/bin/gh-app-token` in the root folder. It signs a request with the app key, prints one installation token, and caches it in `.cache/underground/gh-token` in the agent home until 5 minutes before its expiry. The pinned gh (through `host/agent/gh`) and git get their token from it.
_Avoid_: token script, gh token

**Installation token**:
A token of the GitHub App for its installation, with all the app's rights and repos. It lasts one hour. The token helper makes it and caches it in the agent home.
_Avoid_: app token, PAT

**Onboarding checks**:
The checks that the owner makes on GitHub for each repo before agents work alone in it. A repo is onboarded when the owner has made them and installed the GitHub App on it. The app's installation is the list.
_Avoid_: onboarding list, repo setup

### Models

**Auth broker**:
The host service `omp auth-broker serve`. It runs as the login user, on the auth broker port (`auth_broker_port`, `host/facts`). It holds the owner's model logins in the login user's home, and does every OAuth refresh. The owner reaches it with `ug-auth`. Only the auth gateway talks to it. No session is a broker client, because a broker client receives access tokens and API keys.
_Avoid_: credential store, vault

**Auth gateway**:
The host service `omp auth-gateway serve`, on the tailscale address of this mac (the `gateway=` line of the addresses file). It runs as the login user, on the gateway port (`gateway_port`, `host/facts`). It makes model calls for the sessions with the logins of the auth broker. Every call needs the gateway bearer.
_Avoid_: model proxy, LLM proxy

**Usage broker**:
The host service `host/usage-broker/usage-broker.ts`, run as the login user from the pinned omp (`host/agent/com.underground.usage-broker.plist`). It speaks omp's broker protocol with no credentials. It passes `/v1/usage` to the auth gateway, so omp's native `/usage` works. It listens on the usage broker port (`usage_broker_port`, `host/facts`) on loopback only (`USAGE_BROKER_HOST`, `host/usage-broker/usage-broker.ts`).
_Avoid_: usage proxy, fake broker

**Gateway bearer**:
The shared token that lets a session use the auth gateway. It authorizes every session for all models and accounts that the gateway serves, plus usage and credential health. It does not expose provider secrets or credential management. The agent user reads it from the root folder's `config` folder. The owner accepted this cost. The separate auth-broker bearer stays in the login user's home.
_Avoid_: client token, API key, gateway key

**Gateway provider**:
A provider in a session's `models.yml`, with `transport: pi-native`, `baseUrl` set to the auth gateway, and `apiKey` set to the gateway bearer. Setup fills `@GATEWAY@` and `@GATEWAY_TOKEN@` into the staged `models.yml` (`@GATEWAY_TOKEN@`, `host/bin/ug-agent-setup`). Each model setting of a session names a model of a gateway provider.
_Avoid_: proxy provider

**Inference engine**:
The model server on another machine on the tailnet, at the `engine=` line of the addresses file. It needs an API key, which the auth broker holds under omp's built-in `lm-studio` provider. Sessions reach it only through the auth gateway.
_Avoid_: local model, llama

**Addresses file**:
The owner-only file with two lines: `gateway=<ip>:<port>`, the auth gateway on the tailscale address of this mac, and `engine=<ip>:<port>`, the inference engine. Setup writes it only when it is missing. The gateway comes from the first line of `tailscale ip -4`, with the gateway port (`gateway_port`, `host/facts`). The engine comes from the owner's answer at a prompt. Without a terminal, setup stops and writes nothing (`write_addresses`, `host/bin/ug-setup`). The owner edits it later. It is `addresses` in the data folder.
_Avoid_: address config, hosts file

### Decisions

**Agent-written**:
Describes any file, branch, or setting that the agent could change: everything in its home. Treat it as untrusted until the owner reviews it on GitHub.
_Avoid_: local work, dirty

**One trust level**:
Every role shares the agent user's home and can change what another role loads. The reviewers improve quality. They are not a safety wall. The onboarding checks keep a merge reversible instead.
_Avoid_: role isolation, shared trust

**Accepted risk**:
A threat that the project does not control. The brief accepts it by name and gives the reason (`docs/PRODUCT-BRIEF.md`, "The mechanisms").
_Avoid_: known issue, wontfix

**North star**:
The one direction that every decision follows, in `AGENTS.md` and `docs/PRODUCT-BRIEF.md`: the agent works like a coworker. The owner and the agent do the design together. The agent turns each ready ticket into a merged change on its own. Whatever the agent does without the owner's approval, in either way of working, the owner can undo.
_Avoid_: vision, goal, mission

**Ready ticket**:
A user story or ticket that the design has broken down into the smallest unit of work, with no design decision left in it. Only a ready ticket goes to the agent to do on its own (`docs/PRODUCT-BRIEF.md`, "User and scope").
_Avoid_: task, job, issue

**Gate**:
The question before each decision: does this bring us closer to the north star, or further away? Yes only if it stops an irreversible harm, or keeps undo and work possible.
_Avoid_: review, approval

**MVPF**:
The future underground MVP after 0.5. A threat marked MVPF has no control in 0.5.
_Avoid_: later, backlog, v1
