# Changelog

## 0.14.0

- `board.sh` waits for GitHub's GraphQL quota to reset ( at most `BOARD_RATE_WAIT`, default 900 s ) and retries once, instead of failing mid-hand-back; `worktrees.sh` warns about worktree paths with a space and local branches named like remote ones ( `origin/...` ). Factory skill: no half states on the integration branch ( phased tickets merge when the branch stays consistent ), an owner preview server of the integration tip pulled after every merge, the GraphQL quota rule for repository tooling ( REST, one listing, cached ), orchestrator shell loops in bash. Kanban skill: `merged <branch>` names the ticket's branch; tools test sha ancestry ( reasons: a GraphQL quota emptied by per-card calls in every build froze the board; a zsh loop left a stray `origin/<umbrella>` branch; release notes keyed on the target branch name missed every merge; a canon-only phase would have shown a half-moved world ). Files: `scripts/board.sh`, `scripts/worktrees.sh`, `skills/factory/SKILL.md`, `skills/kanban/SKILL.md`, `README.md`.

## 0.13.0

- Contention measure ( reason: the owner wants as much parallel work as possible unless it slows the whole factory down, and only the headless queue shows that ): every guarded `run.sh` start logs its queue time to `FACTORY_WAITLOG` ( default `/tmp/agentkit-runwaits.log` ); `capacity.sh` reads the last 30 minutes ( measure `queue`, JSON `queue_runs_30m`, `queue_waited_30m`, `queue_longest_s` ) and lowers `agents` by 1 when half the runs queued a minute or one queued 5 minutes, by 2 when 80 % queued and one 10 minutes. The factory skill fills up to the recommendation when the owner asks for more parallelism. Files: `scripts/run.sh`, `scripts/capacity.sh`, `skills/factory/SKILL.md` ( section 2 ), `README.md`.

## 0.12.1

- Review: a visual fix is checked under every condition the app renders ( every time of day and weather, same pose ), not only the reported one; a one-light sheet goes back ( reason: a haze fix verified at noon reappeared at dusk ). Files: `skills/factory/SKILL.md` ( section 4 ), `README.md`.

## 0.12.0

- Effort is a second dial next to the model, set on every spawn ( `low` deployers and bookkeeping, `medium` mechanical work, `high` builders and judgement, `xhigh` foundations or a fix that failed at `high` ), and both are re-routed when a subagent's scope changes: model and effort are fixed at spawn and a message keeps them, so the agent stops at a hand-over file and the next part starts as a new agent with the fitting pair; resume by message only while both still fit ( reason: agents kept on their starting model after the scope changed did geometry on a model too weak for it, or spent the strong model on bookkeeping ). `STATE.md` records model / effort per agent. Files: `skills/factory/SKILL.md` ( section 3, review ), `templates/*/CLAUDE.delegation.md`, `templates/*/AGENTS.collaboration.md`, `templates/STATE.md`, `README.md`.

## 0.11.0

- `scripts/worktrees.sh`: removes merged, clean, unlocked worktrees no process works in, and merged local ( and with `--remote` remote ) branches; dry run by default; warns above `agentsMax` + 2 worktrees. Worktrees now go right after the merge, branches after Done ( reason: cleanup waited for Done, owners leave cards in review, and worktrees piled up by the dozen ). Orchestrator runs it after every hand-back.

## 0.10.0

- Model routing extended ( reason: a full board of parallel builders on the strong models can use most of a weekly limit within a day, and the cheapest model is not good enough for work whose quality rests on form ): Sonnet never generates 3D geometry; the tier above Opus runs only when the owner asks for it by name or after several rejected revisions on Opus, only for the form-critical steps, resumed by message instead of restarted; a ticket is split into a cascade ( top tier, Opus, Sonnet ) run one after another; the model is named when a result is shown. Files: `skills/factory/SKILL.md` ( section 3 ), `templates/*/CLAUDE.delegation.md`, `README.md`.
- Budget: the weekly limit comes before the 5-hour window. The orchestrator asks the owner for the weekly usage before a batch and each day, records it in `STATE.md` and plans against it ( above 70 %: two builders at most; above 85 %: wind down with hand-overs, nothing new without a yes ). `agentsMax` is a hard cap that counts every subagent, also under "full speed". Automated waiting notifications are answered in one line. Files: `skills/factory/SKILL.md` ( section 5 ), `templates/*/CLAUDE.delegation.md`, `README.md`.

## 0.9.2

- Headless rule extended to every process that could open an audio device, not only browsers: Blender runs with `-noaudio`, ffmpeg never plays back, Python / Node audio libraries stay off ( reason: a Blender authoring run without the flag opened CoreAudio on every start and the owner heard the output device switch while all headless browsers were already muted and audio-gated ) ( templates' Branches section, factory skill 5b, README ).

## 0.9.1

- Owner override for the capacity measurement: `FACTORY_OWNER=afk|active` or the machine-wide file `/tmp/factory-owner` holding `afk` or `active` wins over the idle-time measurement; an `afk` file older than 12 h is ignored ( reason: the owner said "I am away now, go" and the factory still waited 30 minutes for the idle detector; conversely a second machine or a remote session has no idle signal ). The orchestrator writes `afk` when the owner announces leaving and removes the file ( or writes `active` ) when they return; the reasons list names the override ( `capacity.sh`, README ).

## 0.9.1

- The board's view and workflows join the automatic setup ( reason: after the columns, the owner still had to rename the view, switch it to Board and check the workflows by hand ). `project.sh view` makes one Board view named `kanban` ( `.factory.json` key `view` ): GitHub's default table "View 1" is renamed and switched through `updateProjectV2View`, a same-named view is switched, otherwise one is created and the owner's views stay. `project.sh workflows` lists the built-in workflows and warns when Auto-add, Item closed or Auto-close is on. `create` and `init.sh` run both. Found to have no API, so still manual: the project's "Default repository" setting and switching a workflow on or off ( `project.sh`, `init.sh`, factory-init skill, README ).

## 0.9.0

- Reports to the owner over several tickets are a bullet list, one bullet per ticket with its number, title and one sentence on what the ticket does for the owner, then state and open points; cross-ticket facts ( capacity, deployed entry file ) in one closing paragraph; never two tickets in one paragraph; every report ends with the next step as a yes / no or a / b / c question ( recommendation first ) and, when nothing is left until an agent reports, with "standing by until the agents report" ( reason: a report that put a decision, four running builders and a new ticket into one paragraph could not be read, and a title like "dusk continuous" explained nothing to the owner ) ( templates' Autonomy sections, delegation templates, factory skill before section 2, README rules ).

## 0.8.1

- The board is found or created by the kit, not by the owner ( reason: init demanded a project number and told the owner to add seven columns by hand, although the API can do both ). New `scripts/project.sh`: `create` uses the project linked to the repository, else the owner's project titled like the repository ( and links it ), else creates one named after the repository and links it, listing the owner's other projects so an existing board is chosen over a second one; `columns` gives the Status field the preset's columns through `updateProjectV2Field` ( empty board: exactly the seven, defaults dropped; board with cards: append only with `--force` ). `init.sh` runs `create` when no `--project` is given and `columns` otherwise. Rule in the factory-init skill: look at the boards that exist before creating one; an existing board for the repository is used and its columns mapped under `columns` in `.factory.json`, extended only where the workflow's column is missing. Still manual, no API: the first view's Board layout and the "Auto-add" workflows ( `project.sh`, `init.sh`, factory-init skill, README ).

## 0.8.0

- The kit measures the machine and sets the number of agents and headless browsers itself, instead of fixed caps the orchestrator guesses ( reason: a fixed six builders and three browsers stalled the owner's machine under load and left it idle at night ). New `scripts/capacity.sh [--json] [--no-disk]` ( macOS first, Linux fallbacks, no sudo ): 1-minute load against the cores, thermal limit ( `pmset -g therm` ), memory pressure, free percentage and swap, GPU utilisation ( `ioreg` IOAccelerator, `nvidia-smi` ), headless browsers of the testing build already running, disk MB/s and tps; it starts at the maxima and reduces ( load over 0.8 × cores, memory warn / critical, GPU over 70 / 90 %, thermal limit, disk over `diskMBs` ), never below 1, and prints a table with the reasons, or `{ agents, headless, free_headless, owner, reasons, measures, caps }`.
- Owner activity decides the headroom: input within `idleMinutes` ( default 10 ) or a connection on one of `ownerPorts` is **active** ( agents −2, headless −2, GPU threshold 60 % ); idle, the hardware limits alone decide; from `afkMinutes` ( default 30 ) on, **AFK**: up to `agentsMax` + 2 while load and GPU allow, so the factory runs flat out overnight. When the owner says the machine is slow, the orchestrator halves the recommendation until told otherwise.
- New `.factory.json` keys `agentsMax` ( 6 ), `headlessMax` ( 4; `headlessCap` read as its alias ), `diskMBs` ( 1500 ), `ownerPorts` ( [] ), `idleMinutes` ( 10 ), `afkMinutes` ( 30 ); `init.sh` writes them only where missing. `run.sh` takes its headless cap from `capacity.sh` and re-measures while it waits ( env `HEADLESS_CAP` overrides ); `board.sh state` prints the capacity under Limits; `STATE.md` gets `Capacity ( last measured )` and `Owner override` lines.
- Rules: factory skill section 5c "Dynamic capacity" ( `capacity.sh` before every spawn and every 30 minutes with the stale check, spawn only while `agents` is above the running count, `free_headless` 0 pauses browser work, not agents ), and the matching lines in the templates' Autonomy and Branches sections and the delegation template ( factory, kanban and factory-init skills, templates, `STATE.md` template, README ).
- The deploy is done by a **deployer agent** on the cheapest model: after a batch's merges the orchestrator triggers it, it verifies the integration tip, builds and runs the gated deploy script with read-back under the merge lock, and returns one line ( sha, entry file, read-back ) that the orchestrator records in `STATE.md`; the rule stays once per batch, never two at once, never a builder ( reason: the deploy's logs and waiting cost the orchestrator's tokens for a mechanical step ) ( templates, delegation templates, factory and kanban skills, README ).
- `init.sh` works while GitHub's GraphQL is rate-limited: the repository from the `origin` remote, the project's name and link from the section it rendered before ( reason: a busy factory exhausts GraphQL and `init.sh` then stopped before writing anything ) ( `init.sh` ).

## 0.7.3

- Stalled agents are detected and replaced without the owner ( reason: a finishing agent stood for two hours with no commit, no running process and no message, and the owner noticed first ). `board.sh stale [--minutes N] [--json]`: per git worktree the minutes since the last commit and the last file change, whether a process runs inside it, the verdict `STALE`, and the merge lock with its age. Heartbeat rule for builders: a commit or a one-line note at least every 30 minutes, a one-line "waiting on X for Y" instead of silence, never more than 20 minutes on a lock or another agent without reporting. Watchdog rule for the orchestrator ( factory skill 4c ): `board.sh stale` every 30 minutes, one ping at 45 minutes without progress, stop and a successor on the same worktree 20 minutes later, never wait on an agent for more than an hour. `STATE.md`'s Running table gets a `Last progress` column ( templates, delegation templates, factory and kanban skills, README ).

## 0.7.2

- Maintenance rule for the plugin itself: every change bumps `version`, gets a `CHANGELOG.md` entry, and the same entry is copied into the README's Changelog section; a significant change ( a new or removed skill, script, config key, env variable, column, template placeholder or rule, or a changed workflow ) also updates the README sections it touches, in the same commit ( README "Maintaining AgentKit", the Upstream-first paragraphs of the skills and templates ).
- README reworked to the current state: who does what ( owner, orchestrator, shift lead, builder, finisher ), the batch cycle, the complete `.factory.json` reference ( `ownerName`, `repo`, `deploy` ), the scripts' environment variables, the templates and `STATE.md`, and the changelog in full.

## 0.7.1

- The deploy is the orchestrator's step, once per batch, never a builder's: builders merge, then the orchestrator runs the verify command on the integration branch's tip and deploys it once through the repository's single deploy script ( gates: generated data present, served page read back naming this build's entry file, other read-backs the repo defines ), and writes sha and entry file into `STATE.md`. Reason: builders deploying after their own merge shipped a build lacking another merge's generated files, and deployed intermediate umbrella states within minutes ( templates, delegation templates, factory skill, kanban skill, `STATE.md` template, README ).

## 0.7.0

- Belongs-there acceptance for visible changes: built from the existing module set ( no second type of an element ), the builder hands over context captures beside the nearest neighbours ( same scale, same state, plus the domain's overview views ), the reviewer judges "looks as if it had always been there" and names the neighbour comparison in the review comment, never accepts on the absence of the old flaw; an automatic neighbour check joins the verify command where the repo has one ( templates, ticket template, kanban skill, factory skill 4b and checklist, delegation templates, README ).

## 0.6.1

- Headless checks never run the owner's installed browser bundle ( the OS then treats every headless instance as the browser running; focus, keyboard and audio session go to the wrong process ): a separate build ( Chrome for Testing in a cache folder ) through the repo's launcher with an env override for the path ( templates, factory skill 5b, factory-init, `run.sh`, README ).

## 0.6.0

- `STATE.md`: the orchestrator's state sheet at the repo root ( Running with the shift lead, Waiting, Queue, Owner decisions open, Limits, Last hand-backs, Notes ), rewritten at every hand-back, spawn and owner decision; `init.sh` gitignores it and creates the skeleton ( `templates/STATE.md` ). Long sessions renew themselves: compaction and shift-lead subagents, never a new session from the owner ( factory skill 4a, delegation templates ).
- `board.sh state [--json]`: a draft of `STATE.md` from the board ( In Progress (Agent), In Review with the merged line, Ready top 10, Backlog top 5, the owner's cards, cards without a column ) in two calls; the REST part still prints when GraphQL is rate-limited.
- Headless checks never touch the owner's machine: muted, windowless, no audio context, one launcher per repo, `headlessCap` ( default 3 ) and a load guard, both enforced by `run.sh` before it starts the command ( templates, factory skill 5b, factory-init ).

## 0.5.5

- `mergelock.sh`: the lock is keyed on the repository's common git dir, so all worktrees of a repository share one lock (it was per worktree, which serialised nothing).

## 0.5.4

- `board.sh tidy`: removes cards without a column whose issue is a sub-issue of a package (GitHub's auto-add puts them back). `factory-init` tells the owner to switch the project's "Auto-add sub-issues to project" ( and any "Auto-add to project" ) workflow off (UI only).

## 0.5.3

- Budget levers: two-phase tickets (Opus builder, Sonnet finisher), `scripts/mergelock.sh`, read-by-range with a module map, trimmed tool output, no new builder in the last hour of a window (factory skill section 5a, delegation and collaboration templates).

## 0.5.2

- Work packages: one card per topic on the board, detail tickets as sub-issues off the board, one builder / branch / verify / merge / deploy per package while every sub-issue keeps its checks, assumptions, numbers and merged line (kanban and factory skills, both templates).
- Overlap search before creating a ticket: extend an existing ticket instead of opening a twin.

## 0.5.1

- Budget section in the factory skill and the delegation templates: six builders at once, Sonnet for mechanical tickets, Opus for milestones, trimmed verification, behaviour at the usage window.
- Rule in the templates and the factory skill: a deploy ships only the built site and static assets; never an executable server-side file, no server configuration, no new credentials; free space from FTP commands, the owner's panel, or reported as unknown.

## 0.5.0

- Language presets (`lang`: `en` default, `de`) for column names, labels and ticket wording; `scripts/lang.sh`; templates moved to `templates/<lang>/`. **Breaking:** repositories that relied on the former German defaults must set `"lang": "de"` in `.factory.json` (`init.sh --lang de` writes it), otherwise `board.sh` looks for the English column names.
- `board.sh`: `project` is required, the owner defaults to the repository's owner; the merged line follows the preset.
- New rules from production, in templates and skills: merge-test-push `&&` chains; clean tree after a build; generated data out of git; deploy verified by reading the served page; dependencies in new worktrees; review findings become tickets; numbers in a comment and in the plan's done line; the orchestrator's queue memo; usage-limit pauses; Monitor re-arming; a hands-off list at kickoff; the orchestrator's review comment on the ticket.
- Docs and manifests carry no personal or project names; a private `REPOS.local.md` (gitignored) replaces the registry table in the README.
- Owner pronouns in the templates are neutral.

## 0.4.0

- Renamed from agent-factory to AgentKit.

## 0.3.0

- Assumptions over questions: the **Annahmen** section in the ticket template, the rule in the Autonomy section and the factory skill.

## 0.2.0

- Upstream-first rule, repo registry, repo-specific items preserved by `init.sh --replace-existing`.

## 0.1.0

- Skills `kanban`, `factory`, `factory-init`; scripts `board.sh`, `init.sh`, `run.sh`, `picdiff.mjs`, `verify-report.sh`, `watch.sh`; templates.
