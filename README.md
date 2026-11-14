# AgentKit

A Claude Code plugin that runs a repository as a **dark factory**: agents take tickets from a GitHub Projects kanban board, build on their own branch and worktree, verify, merge, and hand the card back for review. An orchestrating session starts the next tickets itself, reviews and deploys, and stops only for what truly needs the owner: approving a card as done, money, accounts, hardware, facts of the product's world, and removing something the owner specified.

It is three skills, nine scripts, the rule templates in two languages and a state-sheet skeleton. Nothing in it is specific to a framework or a language; the repository supplies its own verify command and, if it deploys, its own single deploy script.

## How it works

1. **The board is the source of truth.** Seven columns: Epics, Backlog, Ready, In Progress (Human), In Progress (Agent), In Review, Done. The owner sorts the Backlog; agents take from the top of Ready, else Backlog, and never reorder. Tickets that share files become one **work package**: one topic card on the board, the detail tickets as its sub-issues off it.
2. **One ticket or package, one branch, one worktree, one port block.** Branches are `<type>/<id>-<slug>`, from `main` or from the umbrella branch the ticket's epic names.
3. **Two phases per ticket.** An Opus builder designs, implements and stops at a short handover; a Sonnet finisher runs the full verify, takes the captures, writes the ticket and merges under the repository's merge lock. Merge, verify and push run in one `&&` chain.
4. **The orchestrator reviews and deploys.** It checks the diff against the ticket, runs the verify command, reads the builder's assumptions, judges visible changes against their neighbours, posts a review comment, and hands the card to In Review with the label `merged` and a `**Merged:** <sha> in <branch>` line. After a batch of merges it triggers one deployer agent that verifies the tip once and deploys it once. Only the owner moves a card to Done.
5. **Assumptions over questions.** What the repository does not answer, the agent decides, records under **Assumptions** in the ticket, and keeps going. Questions that must be asked are asked all at once, at kickoff, together with a hands-off list.
6. **The state lives outside the chat.** `STATE.md` at the repo root ( gitignored ) holds who runs what, the queue, open owner decisions and limits. A fresh or compacted session reads it, runs `board.sh state`, and continues; shift-lead subagents keep the root session thin, and nobody asks the owner for a new session.

### Who does what

| Role | Is | Does |
|---|---|---|
| **Owner** | The human | Sorts the Backlog, answers the kickoff questions, names the hands-off list, judges cards in In Review, moves cards to Done, decides money, accounts, hosting, canon and taste. |
| **Orchestrator** | The Claude Code session the owner opens | Kickoff, picks tickets, prepares branch / worktree / ports, starts builders, reviews, merges stragglers, decides the deploy once per batch, keeps `STATE.md`, waits with Monitor on `watch.sh`. |
| **Shift lead** | A long-lived orchestrator subagent, one per batch | Runs the loop for its batch, hands back decisions and short summaries, rewrites `STATE.md` when its context grows and makes way for the next. |
| **Builder** | A background subagent, Opus by default, Sonnet for mechanical tickets | Builds the ticket on its branch, commits early, records assumptions, hands over with context captures. Never deploys, never moves a card to Done. |
| **Deployer** | A subagent on the cheapest model, one per batch, never two at once | Under the merge lock: verify on the integration tip, build, the repo's gated deploy script, read-back; returns one line ( sha, entry file, read-back ). Fixes nothing. |
| **Finisher** | A Sonnet subagent | Full verify, captures, the ticket's checks and numbers, merge under the lock, `board.sh merged`. |

### The batch cycle

```
pick ( board.sh next ) -> In Progress (Agent) -> branch + worktree + install + ports -> builder ( model, effort )
  -> handover -> finisher: verify, captures, ticket, merge under mergelock.sh, push in one && chain
  -> orchestrator review: diff vs ticket, verify-report.sh, picdiff.mjs, neighbour comparison, assumptions
  -> board.sh merged + review comment -> In Review -> STATE.md rewritten -> next ticket
per batch: orchestrator triggers the deployer agent ( cheapest model, under mergelock.sh ) -> verify on the tip of main / umbrella
  -> build -> one deploy through the repo's deploy script -> served page read back -> its one line ( sha, entry file ) in STATE.md
```

## Install

```bash
claude plugin marketplace add niklasbrandt/AgentKit
claude plugin install agentkit@agentkit
```

Inside Claude Code: `/plugin marketplace add niklasbrandt/AgentKit`, then `/plugin install agentkit@agentkit`. To try a checkout without installing: `claude --plugin-dir <path to this repo>`.

Requirements: `gh` ( once: `gh auth refresh -s project` ), `jq`, `python3` ( `init.sh` renders the templates with it ). `node`, `puppeteer-core` in the target repo and a Chrome only for `picdiff.mjs`. `flock` is used for the merge lock where it exists; macOS falls back to an atomic `mkdir`.

**Cursor, Antigravity, or no plugin host:** the rules are plain Markdown. Run `scripts/init.sh` from a checkout of this repo inside the target repo, or copy `templates/<lang>/AGENTS.collaboration.md` into the repo's `AGENTS.md` and fill the `{{...}}` placeholders by hand. The skills in `skills/` are Markdown you can paste into `.cursor/rules` or `.agents/skills/`; call the scripts by path.

## Quick start

```bash
cd my-repo
gh auth refresh -s project                      # once
claude                                          # then: /factory-init
#   it finds the board linked to the repo, or one titled like it, or creates one named after the repo, links it and sets its
#   seven columns and one Board view named "kanban" ( scripts/project.sh ); asks for the language preset, verify command,
#   local run command, umbrella branches and the owner's dev port; writes the AGENTS.md / CLAUDE.md sections, .factory.json,
#   the labels and the STATE.md skeleton. Left to you ( no API ): the project's "Default repository" setting, and any
#   "Auto-add" / "Item closed" workflow that init reports as on
gh issue create --label feature --title "..." --body-file ticket.md     # ticket in the template of the kanban skill
scripts/board.sh add <issue-url> "Ready"
claude                                          # then: "run the factory" or /factory <plan or epic>
```

## The three skills

| Skill | What it is |
|---|---|
| `kanban` | The board workflow: columns and who moves what, assignees, labels, overlap search before filing, work packages, the ticket template ( checks, Assumptions, "Changed after review", branch, preview ), branch naming and umbrella branches, the merge and deploy rules, cleanup after Done, and the exact `gh` commands behind `board.sh`. |
| `factory` | The orchestrator loop: kickoff ( `STATE.md`, `board.sh state`, assumptions, hands-off list, `caffeinate`, the watcher ), pick / prepare / delegate / review / merge / hand back / next, what needs the owner, the Monitor watcher, long sessions ( usage limits, compaction, shift leads ), the neighbour test for visible changes, the budget rules ( six builders, model mix, two phases, merge lock, read by range ), headless checks that never touch the owner's machine, and the per-ticket checklist. |
| `factory-init` | Finds the board linked to the repository ( or one titled like it ) or creates one and sets its columns, asks the owner's settings in one message, runs `init.sh`, tells the owner which project workflows to switch off, checks that `CLAUDE.md` imports `AGENTS.md`, commits. |

## Scripts

All in `scripts/`, called by path ( `${CLAUDE_PLUGIN_ROOT}/scripts/...` inside Claude Code ), run inside the target repository.

| Script | Does |
|---|---|
| `board.sh ids <project> <owner> \| list [column] \| next \| status <n> \| add <url> "<col>" \| move <n> "<col>" \| merged <n> <sha> <branch> \| tidy \| stale [--minutes N] [--json] \| state [--json]` | Board operations with the guards built in: never sets Done, never touches a card in Done, assigns the author on In Review and removes the assignee on leaving it. `tidy` takes stray sub-issue cards off the board. `stale` ( no GitHub call ) lists every git worktree with minutes since its last commit and last file change, whether a process runs inside it, and the verdict `STALE` ( both ages over N, default 45, no process ), plus the merge lock and its age ( a lock over 30 minutes with no `mergelock.sh` process is stale ); the watchdog's eyes. `state` prints a draft of `STATE.md` from the board in one GraphQL and one REST call, with the measured capacity under Limits. |
| `capacity.sh [--json] [--no-disk]` ( `/tmp/factory-owner` = `afk` / `active` overrides the owner measurement ) | Measures the machine's bottlenecks ( load against cores, thermal limit, memory pressure and swap, GPU utilisation, headless browsers running, disk MB/s ) and the owner's activity ( idle time, `ownerPorts` in use ), and recommends `agents` and `headless` for right now, between 1 and `agentsMax` / `headlessMax` ( AFK: up to `agentsMax` + 2 ). Prints a table with the reasons; `--json` gives `{ agents, headless, free_headless, owner, reasons, measures, caps }`. Read-only, no sudo, always exit 0. The orchestrator runs it before every spawn and every 30 minutes. |
| `init.sh [--project <n>] [--lang en\|de] [--owner <handle>] [--name "<Full Name>"] [--verify "<cmd>"] [--run "<cmd>"] [--umbrella "a, b"] [--replace-existing] [--dry-run]` | What `factory-init` runs. Idempotent: sections are replaced between `<!-- factory:collaboration:start/end -->` and `<!-- factory:delegation:start/end -->` markers. Without `--project` it runs `project.sh create`. Writes `.factory.json`, the labels, the `STATE.md` skeleton and its `.gitignore` line, adds missing columns where the board is empty ( `project.sh columns` ), then runs `board.sh ids`. Existing `.factory.json` values are the defaults for omitted flags. |
| `project.sh create [--owner <handle>] [--repo owner/name] [--title "<title>"] \| columns <project> <owner> [--force] \| view <project> <owner> [--name kanban] \| workflows <project> <owner>` | The board itself. `create` finds the project linked to the repository ( several: exit 3, pass `--project` ), else the owner's project titled like the repository ( then links it ), else creates one named after the repository and links it; lists the owner's other projects so an existing board can be chosen; prints the number. `columns` gives the Status field the preset's seven columns: an empty board gets exactly those ( GitHub's defaults dropped ), a board with cards keeps its options and gets the missing ones appended only with `--force` ( `updateProjectV2Field` replaces the option set ). `view` makes sure there is one Board view named `kanban` ( `.factory.json` `view` ): the default table "View 1" is renamed and switched, a same-named view is switched, else one is created beside the owner's views. `workflows` lists the built-in workflows and warns when an Auto-add, Item closed or Auto-close one is on ( switching them, and the project's Default repository, are UI-only ). |
| `lang.sh` | The `en` and `de` presets for column names, labels and ticket wording. Sourced by the other scripts, never run. |
| `run.sh <timeout s> <cmd...>` | Watchdog for headless work: TERM after the timeout, then kills orphaned headless Chromes. Waits first while the headless cap is reached ( `capacity.sh`'s `headless`, re-measured while it waits; without it `headlessMax` ) or the 1-minute load is above the core count. Also for a dev server in the background ( `FACTORY_LOAD_WAIT=0` ). |
| `verify-report.sh [--quick] [--timeout 900]` | Runs the `verify` list of `.factory.json`, each under `run.sh`, and prints a ticket section with PASS / FAIL per check in the preset's wording. `--quick` skips `"slow": true` entries. Exit 1 on any FAIL. |
| `picdiff.mjs <A> <B> [--out dir] [--threshold 24] [--fail pct]` | Share of differing pixels between two captures or two folders of PNGs, decoded in headless Chrome, no image library. `--out` writes a sheet per pair, `--fail` makes it exit 1 above the share. |
| `worktrees.sh [--apply] [--remote] [--json]` | Dry run by default. Removes every worktree whose HEAD is merged into a base branch ( the default branch and `umbrella` ), that is clean, unlocked and has no process working in it; deletes merged local branches; `--remote` also merged remote branches ( only with the owner's go ). Warns when more than `agentsMax` + 2 worktrees remain. |
| `mergelock.sh <cmd...>` | One lock per repository ( keyed on the common git dir, so every worktree shares it ) around merge, verify and push: a second builder waits instead of verifying twice. |
| `watch.sh [issue ...]` | One line per change for Claude Code's Monitor tool: a card's column, assignees or labels; a session transcript appearing, going quiet or becoming active. |

### Environment variables the scripts read

| Variable | Script | Meaning |
|---|---|---|
| `FACTORY_JSON` | all | Path of the settings file ( default `<repo>/.factory.json` ). |
| `FACTORY_OWNER=1` | `board.sh` | Lifts the Done guards; for the owner's own shell only. |
| `FACTORY_LOAD_WAIT` | `run.sh` | Seconds to wait for the cap and load guard ( default 600, `0` = no guard ). |
| `HEADLESS_CAP` | `run.sh` | Fixed headless cap; overrides `capacity.sh` and `.factory.json`. |
| `FACTORY_CHROME_PATTERN` | `run.sh` | Pattern that identifies headless Chromes ( default `puppeteer_dev_chrome_profile` ). |
| `FACTORY_LOCK`, `MERGELOCK_WAIT` | `mergelock.sh` | Lock path ( default `/tmp/factory-<repo>.lock` ) and the longest wait in seconds ( default 3600 ). |
| `CHROME` | `picdiff.mjs` | Path of the Chrome to decode with ( default: the installed one; headless checks of a repo should point it at a Chrome for Testing build ). |
| `INTERVAL`, `QUIET`, `TRANSCRIPTS` | `watch.sh` | Poll interval ( 30 s ), quiet threshold ( 300 s ), transcript directory ( derived from the repo path ). |

## Templates and `STATE.md`

`templates/<lang>/AGENTS.collaboration.md` is rendered into the repository's `AGENTS.md` ( the Collaboration section: upstream first, board, autonomy, tickets, branches ), `templates/<lang>/CLAUDE.delegation.md` into `CLAUDE.md` ( the Delegation section: how the orchestrator uses Claude Code's tools ). Placeholders: `{{OWNER}}`, `{{OWNER_NAME}}`, `{{PROJECT}}`, `{{PROJECT_NAME}}`, `{{PROJECT_URL}}`, `{{VERIFY}}`, `{{LOCAL_RUN}}`, `{{UMBRELLA_NOTE}}`, `{{TRANSCRIPT_DIR}}`, `{{PLUGIN_URL}}`. Repo-specific facts ( ports, where the plan lives, the deploy command, canon ) go outside the markers in a `### Repo-specific` subsection; `init.sh --replace-existing` moves them there from an old unmarked section.

`templates/STATE.md` is the orchestrator's state sheet, copied to the repo root by `init.sh` and gitignored. Fixed sections: Running ( with the shift lead ), Waiting, Queue, Owner decisions open, Limits, Last hand-backs ( ticket, sha, deployed entry file, date ), Notes. It is rewritten, never appended, at every hand-back, spawn and owner decision.

## `.factory.json`

Lives at the repo root. `project` is required ( `init.sh` fills it in, creating the board if there is none ); everything else has a default. `init.sh` writes it, `board.sh`, `capacity.sh`, `run.sh`, `verify-report.sh` and `watch.sh` read it.

```json
{
  "project": 1,
  "owner": "<github handle, default: the repository's owner>",
  "ownerName": "<full name, default: the owner's GitHub name>",
  "reviewer": "<default: owner>",
  "repo": "<owner/name, default: the current repository>",
  "lang": "en",
  "localRun": "npm install && npm run dev",
  "verify": [ { "name": "Build", "cmd": "npm run build" },
              { "name": "Pictures", "cmd": "node picdiff.mjs before after --fail 6", "slow": true } ],
  "deploy": "<the repository's single deploy script, if it deploys>",
  "umbrella": [],
  "agentsMax": 6,
  "headlessMax": 4,
  "diskMBs": 1500,
  "ownerPorts": [ 5173 ],
  "idleMinutes": 10,
  "afkMinutes": 30,
  "columns": { "ready": "Ready" },
  "labels": { "merged": "merged" },
  "terms": { "mergedLine": "Merged" }
}
```

- `lang` selects the preset for columns, labels and the wording of the ticket template and the verify report. `en`: Epics, Backlog, Ready, In Progress (Human), In Progress (Agent), In Review, Done; labels `idea`, `merged`; line `**Merged:**`. `de`: Epics, Backlog, Bereit, In Arbeit (Mensch), In Arbeit (Agent), Zur Review, Fertig; labels `idee`, `gemergt`; line `**Gemergt:**`. Any single name can be overridden in `columns`, `labels` or `terms`.
- `verify` entries are `{ name, cmd, slow }` or a plain command string; `slow` entries are skipped by `verify-report.sh --quick`.
- `deploy` is read by the orchestrator ( the `factory` skill ), not by a script: it names the one script that deploys a verified tip and carries the repository's own gates.
- `agentsMax` ( default 6 ) and `headlessMax` ( default 4 ) are the upper bounds of `capacity.sh`'s recommendation; how many run is measured ( factory skill 5c ). `headlessCap`, the fixed cap before 0.8.0, is read as an alias of `headlessMax`.
- `diskMBs` is the disk throughput `capacity.sh` treats as saturated ( default 1500, an NVMe drive under heavy use ).
- `ownerPorts` lists the owner's own dev-server ports: an established connection on one counts as the owner testing. `idleMinutes` ( 10 ) and `afkMinutes` ( 30 ) are the owner-activity thresholds: below `idleMinutes` since the last input the owner is active and headroom is reserved, from `afkMinutes` on up to `agentsMax` + 2 agents run.

## Rules learned in production

These are in the templates and skills; the short version, grouped.

**Git, merge, build**

- **Merge, test, push in one `&&` chain.** A `;` once pushed a branch before its smoke test had been read.
- **Merge under the lock.** `mergelock.sh` serialises merge, verify and push per repository; waiting is free, a second verify is not.
- **A build must leave the tree clean.** A file the build regenerates is ignored or committed, never left dirty at merge time.
- **Generated data stays out of git**, however small the estimate was. Record where it lives and how it is rebuilt; hosting is the owner's call.
- **New worktrees need their dependencies installed** before any check runs in them.

**Deploy**

- **The orchestrator decides the deploy, once per batch, never a builder; a deployer agent does it.** Builders that each deployed after their own merge shipped a build missing another merge's generated files and broke the live page; the deploy is one step from the verified tip through one gated script. The work ( verify, build, deploy, read-back ) goes to a deployer agent on the cheapest model under the merge lock, which returns one line, so the deploy's logs never fill the orchestrator's context.
- **A deploy is done when the served page is checked**, not when the upload returns. A deploy that skipped unchanged-size files served a stale entry page for two days while every new bundle was uploaded.
- **Nothing executable on a server, ever.** A deploy ships the built site and static assets; free space comes from FTP commands, the owner's panel, or is reported as unknown.

**Tickets and review**

- **Assumptions over questions.** Decide, record under **Assumptions**, keep going; ask only what is irreversible or expensive, all at once at kickoff.
- **Ask for a hands-off list at kickoff**: areas the owner wants to decide in person first; do not touch them, not even with drafts.
- **Search before you file.** Two halves of one problem are one ticket; extend, don't duplicate.
- **Work packages, not forty cards.** Tickets that share files become one topic card with sub-issues; the owner sorts topics, one builder runs the package on one branch, every sub-issue keeps its own checks and merged line.
- **Review findings become tickets**, not side fixes: a flaw found while reviewing ticket A beyond its scope gets its own short ticket.
- **Numbers, not adjectives.** Performance, precision and look changes get the measured before and after in a comment; plan milestones get a dated done line with those numbers.
- **Visible changes pass the neighbour test.** A reviewer accepted a change because the flagged flaw was gone, while the new element looked nothing like its neighbours; now the builder hands over context captures beside the nearest neighbours and the review comment names the comparison.
- **Never two performance measurements at once.**
- **Reports to the owner: one bullet per ticket, and say what the ticket is.** A round-up over several tickets is a bullet list, one bullet per ticket with number, title and one sentence on what it does for the owner, then state and open points; cross-ticket facts in one closing paragraph; the next step as a yes / no or a / b / c question at the end, then "standing by until the agents report" when that is the case. A paragraph that mashed a decision, four builders and a new ticket together could not be read.

**Sessions and state**

- **The orchestrator keeps `STATE.md`**: running agents, waits, queue, open owner decisions, limits, last hand-backs, notes, rewritten at every hand-back, spawn and owner decision. Long sessions lost exactly what was in no ticket.
- **A fresh session reads `STATE.md`, then `board.sh state`**, and never asks the owner to open a new one: compaction plus the sheet is lossless, and shift-lead subagents keep the root session thin.
- **A stalled agent is found by the orchestrator, not by the owner.** A finishing agent once stood for two hours with no commit, no process and no message. Builders now commit or post a line at least every 30 minutes and say what they wait on ( never more than 20 minutes on a lock or another agent unreported ); the orchestrator runs `board.sh stale` every 30 minutes, pings at 45 minutes without progress, stops and replaces the agent on the same worktree 20 minutes later, and never waits on an agent for more than an hour. `STATE.md` shows `Last progress` per agent.
- **Model and effort follow the work, not the agent.** Both are fixed when a subagent starts; when its scope changes, it hands over on its branch and a new agent with the fitting pair continues.
- **Usage limits pause builders; they do not kill them.** Resume each with a message after the window resets.

**Budget**

- **The weekly limit comes first.** The orchestrator asks the owner for the weekly usage before a batch and plans against it: above 70 % two builders at most, above 85 % it winds down and starts nothing new without a yes. `agentsMax` is a hard cap that counts every subagent.
- **Model routing.** Opus builds, and builds all 3D geometry; Sonnet does the mechanical rest and never generates geometry; the tier above Opus runs only when the owner asks for it or after several rejected revisions, and then only for the form-critical steps of a ticket ( cascade: top tier, Opus, Sonnet, one after another ).
- **Six builders at once, Sonnet for the mechanical tickets.** The usage limit is a shared token budget per window; eight Opus builders empty it in three hours and idle for two.
- **Two phases per ticket.** Opus builds, a Sonnet finisher verifies, captures, writes the ticket, merges under the lock: a third of the tokens at a fifth of the price.
- **Read by range, never whole.** A generated module map tells builders where to look in big files.
- **No new builder in the last hour of a window**: it would pay its read-in twice.

**Headless checks**

- **The machine is measured, not guessed.** Fixed caps ( six builders, three browsers ) stalled the owner's machine under load and left it idle at night. `capacity.sh` sets agents and headless browsers from load, memory, GPU, disk and the owner's activity before every spawn: headroom while the owner works, the full machine when idle, more than the cap when AFK, half when the owner says it is slow.
- **Headless checks never touch the owner's machine**: muted, windowless, no audio context ( and no other headless process opens an audio device: Blender `-noaudio`, ffmpeg without playback ), one launcher, at most the measured `headless` at once and none above the core count in load. A muted headless browser that opened an audio context still made the owner's speakers pop.
- **Headless checks never use the owner's installed browser bundle**: the OS then thinks the owner's browser is running and it will not start; use a separate build ( Chrome for Testing ) through the one launcher, path overridable by env.
- **Worktrees are removed when their branch is merged, not when the card is Done.** Owners leave cards in review for days, and one repository collected more than ninety worktrees, each with its own dependencies, before anyone noticed. The orchestrator runs `worktrees.sh --apply` after every hand-back and checks its warning at every `STATE.md` rewrite.

## Maintaining AgentKit

**Upstream first.** A factory-level rule ( board workflow, ticket format, branch rules, merge, review and deploy handling, delegation, the verify pattern, scripts ) is changed **here** first. Then `scripts/init.sh` is re-run in every repository that uses the plugin; the rendered sections update in place between their markers. Repo-specific content ( ports, umbrella branches, tools, domain rules ) lives in the repository outside the markers, in a `### Repo-specific` subsection. Keep your own list of adopting repositories in `REPOS.local.md` ( gitignored ) or wherever suits you.

**Every change, in one commit:**

1. Bump `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` ( patch for docs and fixes, minor for a new rule, script or skill, major for anything an adopting repo must change by hand, such as the `lang` default in 0.5.0 ).
2. Add the entry to `CHANGELOG.md`, one bullet per change with its reason and the files it touched.
3. Copy that entry into the **Changelog** section at the end of this README. The two lists are identical, heading level aside; this must print nothing:

   ```bash
   diff <( sed -n '/^## Changelog$/,$p' README.md | tail -n +3 | sed 's/^### /## /' ) <( tail -n +3 CHANGELOG.md )
   ```

4. **A significant change also updates the README sections it touches.** Significant is anything a reader of this page would otherwise get wrong: a skill, script, subcommand, flag, config key, environment variable, template placeholder, column or label added, removed or renamed; a rule added or changed; a changed workflow ( who deploys, how a card moves, what a builder may do ). Wording fixes inside a skill are not significant; the changelog entry is enough.

## Licence

MIT, see [LICENSE](LICENSE). The changelog below is the same as [CHANGELOG.md](CHANGELOG.md).

## Changelog

### 0.12.0

- Effort is a second dial next to the model, set on every spawn ( `low` deployers and bookkeeping, `medium` mechanical work, `high` builders and judgement, `xhigh` foundations or a fix that failed at `high` ), and both are re-routed when a subagent's scope changes: model and effort are fixed at spawn and a message keeps them, so the agent stops at a hand-over file and the next part starts as a new agent with the fitting pair; resume by message only while both still fit ( reason: agents kept on their starting model after the scope changed did geometry on a model too weak for it, or spent the strong model on bookkeeping ). `STATE.md` records model / effort per agent. Files: `skills/factory/SKILL.md` ( section 3, review ), `templates/*/CLAUDE.delegation.md`, `templates/*/AGENTS.collaboration.md`, `templates/STATE.md`, `README.md`.

### 0.11.0

- `scripts/worktrees.sh`: removes merged, clean, unlocked worktrees no process works in, and merged local ( and with `--remote` remote ) branches; dry run by default; warns above `agentsMax` + 2 worktrees. Worktrees now go right after the merge, branches after Done ( reason: cleanup waited for Done, owners leave cards in review, and worktrees piled up by the dozen ). Orchestrator runs it after every hand-back.

### 0.10.0

- Model routing extended ( reason: a full board of parallel builders on the strong models can use most of a weekly limit within a day, and the cheapest model is not good enough for work whose quality rests on form ): Sonnet never generates 3D geometry; the tier above Opus runs only when the owner asks for it by name or after several rejected revisions on Opus, only for the form-critical steps, resumed by message instead of restarted; a ticket is split into a cascade ( top tier, Opus, Sonnet ) run one after another; the model is named when a result is shown. Files: `skills/factory/SKILL.md` ( section 3 ), `templates/*/CLAUDE.delegation.md`, `README.md`.
- Budget: the weekly limit comes before the 5-hour window. The orchestrator asks the owner for the weekly usage before a batch and each day, records it in `STATE.md` and plans against it ( above 70 %: two builders at most; above 85 %: wind down with hand-overs, nothing new without a yes ). `agentsMax` is a hard cap that counts every subagent, also under "full speed". Automated waiting notifications are answered in one line. Files: `skills/factory/SKILL.md` ( section 5 ), `templates/*/CLAUDE.delegation.md`, `README.md`.

### 0.9.2

- Headless rule extended to every process that could open an audio device, not only browsers: Blender runs with `-noaudio`, ffmpeg never plays back, Python / Node audio libraries stay off ( reason: a Blender authoring run without the flag opened CoreAudio on every start and the owner heard the output device switch while all headless browsers were already muted and audio-gated ) ( templates' Branches section, factory skill 5b, README ).

### 0.9.1

- Owner override for the capacity measurement: `FACTORY_OWNER=afk|active` or the machine-wide file `/tmp/factory-owner` holding `afk` or `active` wins over the idle-time measurement; an `afk` file older than 12 h is ignored ( reason: the owner said "I am away now, go" and the factory still waited 30 minutes for the idle detector; conversely a second machine or a remote session has no idle signal ). The orchestrator writes `afk` when the owner announces leaving and removes the file ( or writes `active` ) when they return; the reasons list names the override ( `capacity.sh`, README ).

### 0.9.1

- The board's view and workflows join the automatic setup ( reason: after the columns, the owner still had to rename the view, switch it to Board and check the workflows by hand ). `project.sh view` makes one Board view named `kanban` ( `.factory.json` key `view` ): GitHub's default table "View 1" is renamed and switched through `updateProjectV2View`, a same-named view is switched, otherwise one is created and the owner's views stay. `project.sh workflows` lists the built-in workflows and warns when Auto-add, Item closed or Auto-close is on. `create` and `init.sh` run both. Found to have no API, so still manual: the project's "Default repository" setting and switching a workflow on or off ( `project.sh`, `init.sh`, factory-init skill, README ).

### 0.9.0

- Reports to the owner over several tickets are a bullet list, one bullet per ticket with its number, title and one sentence on what the ticket does for the owner, then state and open points; cross-ticket facts ( capacity, deployed entry file ) in one closing paragraph; never two tickets in one paragraph; every report ends with the next step as a yes / no or a / b / c question ( recommendation first ) and, when nothing is left until an agent reports, with "standing by until the agents report" ( reason: a report that put a decision, four running builders and a new ticket into one paragraph could not be read, and a title like "dusk continuous" explained nothing to the owner ) ( templates' Autonomy sections, delegation templates, factory skill before section 2, README rules ).

### 0.8.1

- The board is found or created by the kit, not by the owner ( reason: init demanded a project number and told the owner to add seven columns by hand, although the API can do both ). New `scripts/project.sh`: `create` uses the project linked to the repository, else the owner's project titled like the repository ( and links it ), else creates one named after the repository and links it, listing the owner's other projects so an existing board is chosen over a second one; `columns` gives the Status field the preset's columns through `updateProjectV2Field` ( empty board: exactly the seven, defaults dropped; board with cards: append only with `--force` ). `init.sh` runs `create` when no `--project` is given and `columns` otherwise. Rule in the factory-init skill: look at the boards that exist before creating one; an existing board for the repository is used and its columns mapped under `columns` in `.factory.json`, extended only where the workflow's column is missing. Still manual, no API: the first view's Board layout and the "Auto-add" workflows ( `project.sh`, `init.sh`, factory-init skill, README ).

### 0.8.0

- The kit measures the machine and sets the number of agents and headless browsers itself, instead of fixed caps the orchestrator guesses ( reason: a fixed six builders and three browsers stalled the owner's machine under load and left it idle at night ). New `scripts/capacity.sh [--json] [--no-disk]` ( macOS first, Linux fallbacks, no sudo ): 1-minute load against the cores, thermal limit ( `pmset -g therm` ), memory pressure, free percentage and swap, GPU utilisation ( `ioreg` IOAccelerator, `nvidia-smi` ), headless browsers of the testing build already running, disk MB/s and tps; it starts at the maxima and reduces ( load over 0.8 × cores, memory warn / critical, GPU over 70 / 90 %, thermal limit, disk over `diskMBs` ), never below 1, and prints a table with the reasons, or `{ agents, headless, free_headless, owner, reasons, measures, caps }`.
- Owner activity decides the headroom: input within `idleMinutes` ( default 10 ) or a connection on one of `ownerPorts` is **active** ( agents −2, headless −2, GPU threshold 60 % ); idle, the hardware limits alone decide; from `afkMinutes` ( default 30 ) on, **AFK**: up to `agentsMax` + 2 while load and GPU allow, so the factory runs flat out overnight. When the owner says the machine is slow, the orchestrator halves the recommendation until told otherwise.
- New `.factory.json` keys `agentsMax` ( 6 ), `headlessMax` ( 4; `headlessCap` read as its alias ), `diskMBs` ( 1500 ), `ownerPorts` ( [] ), `idleMinutes` ( 10 ), `afkMinutes` ( 30 ); `init.sh` writes them only where missing. `run.sh` takes its headless cap from `capacity.sh` and re-measures while it waits ( env `HEADLESS_CAP` overrides ); `board.sh state` prints the capacity under Limits; `STATE.md` gets `Capacity ( last measured )` and `Owner override` lines.
- Rules: factory skill section 5c "Dynamic capacity" ( `capacity.sh` before every spawn and every 30 minutes with the stale check, spawn only while `agents` is above the running count, `free_headless` 0 pauses browser work, not agents ), and the matching lines in the templates' Autonomy and Branches sections and the delegation template ( factory, kanban and factory-init skills, templates, `STATE.md` template, README ).
- The deploy is done by a **deployer agent** on the cheapest model: after a batch's merges the orchestrator triggers it, it verifies the integration tip, builds and runs the gated deploy script with read-back under the merge lock, and returns one line ( sha, entry file, read-back ) that the orchestrator records in `STATE.md`; the rule stays once per batch, never two at once, never a builder ( reason: the deploy's logs and waiting cost the orchestrator's tokens for a mechanical step ) ( templates, delegation templates, factory and kanban skills, README ).
- `init.sh` works while GitHub's GraphQL is rate-limited: the repository from the `origin` remote, the project's name and link from the section it rendered before ( reason: a busy factory exhausts GraphQL and `init.sh` then stopped before writing anything ) ( `init.sh` ).

### 0.7.3

- Stalled agents are detected and replaced without the owner ( reason: a finishing agent stood for two hours with no commit, no running process and no message, and the owner noticed first ). `board.sh stale [--minutes N] [--json]`: per git worktree the minutes since the last commit and the last file change, whether a process runs inside it, the verdict `STALE`, and the merge lock with its age. Heartbeat rule for builders: a commit or a one-line note at least every 30 minutes, a one-line "waiting on X for Y" instead of silence, never more than 20 minutes on a lock or another agent without reporting. Watchdog rule for the orchestrator ( factory skill 4c ): `board.sh stale` every 30 minutes, one ping at 45 minutes without progress, stop and a successor on the same worktree 20 minutes later, never wait on an agent for more than an hour. `STATE.md`'s Running table gets a `Last progress` column ( templates, delegation templates, factory and kanban skills, README ).

### 0.7.2

- Maintenance rule for the plugin itself: every change bumps `version`, gets a `CHANGELOG.md` entry, and the same entry is copied into the README's Changelog section; a significant change ( a new or removed skill, script, config key, env variable, column, template placeholder or rule, or a changed workflow ) also updates the README sections it touches, in the same commit ( README "Maintaining AgentKit", the Upstream-first paragraphs of the skills and templates ).
- README reworked to the current state: who does what ( owner, orchestrator, shift lead, builder, finisher ), the batch cycle, the complete `.factory.json` reference ( `ownerName`, `repo`, `deploy` ), the scripts' environment variables, the templates and `STATE.md`, and the changelog in full.

### 0.7.1

- The deploy is the orchestrator's step, once per batch, never a builder's: builders merge, then the orchestrator runs the verify command on the integration branch's tip and deploys it once through the repository's single deploy script ( gates: generated data present, served page read back naming this build's entry file, other read-backs the repo defines ), and writes sha and entry file into `STATE.md`. Reason: builders deploying after their own merge shipped a build lacking another merge's generated files, and deployed intermediate umbrella states within minutes ( templates, delegation templates, factory skill, kanban skill, `STATE.md` template, README ).

### 0.7.0

- Belongs-there acceptance for visible changes: built from the existing module set ( no second type of an element ), the builder hands over context captures beside the nearest neighbours ( same scale, same state, plus the domain's overview views ), the reviewer judges "looks as if it had always been there" and names the neighbour comparison in the review comment, never accepts on the absence of the old flaw; an automatic neighbour check joins the verify command where the repo has one ( templates, ticket template, kanban skill, factory skill 4b and checklist, delegation templates, README ).

### 0.6.1

- Headless checks never run the owner's installed browser bundle ( the OS then treats every headless instance as the browser running; focus, keyboard and audio session go to the wrong process ): a separate build ( Chrome for Testing in a cache folder ) through the repo's launcher with an env override for the path ( templates, factory skill 5b, factory-init, `run.sh`, README ).

### 0.6.0

- `STATE.md`: the orchestrator's state sheet at the repo root ( Running with the shift lead, Waiting, Queue, Owner decisions open, Limits, Last hand-backs, Notes ), rewritten at every hand-back, spawn and owner decision; `init.sh` gitignores it and creates the skeleton ( `templates/STATE.md` ). Long sessions renew themselves: compaction and shift-lead subagents, never a new session from the owner ( factory skill 4a, delegation templates ).
- `board.sh state [--json]`: a draft of `STATE.md` from the board ( In Progress (Agent), In Review with the merged line, Ready top 10, Backlog top 5, the owner's cards, cards without a column ) in two calls; the REST part still prints when GraphQL is rate-limited.
- Headless checks never touch the owner's machine: muted, windowless, no audio context, one launcher per repo, `headlessCap` ( default 3 ) and a load guard, both enforced by `run.sh` before it starts the command ( templates, factory skill 5b, factory-init ).

### 0.5.5

- `mergelock.sh`: the lock is keyed on the repository's common git dir, so all worktrees of a repository share one lock (it was per worktree, which serialised nothing).

### 0.5.4

- `board.sh tidy`: removes cards without a column whose issue is a sub-issue of a package (GitHub's auto-add puts them back). `factory-init` tells the owner to switch the project's "Auto-add sub-issues to project" ( and any "Auto-add to project" ) workflow off (UI only).

### 0.5.3

- Budget levers: two-phase tickets (Opus builder, Sonnet finisher), `scripts/mergelock.sh`, read-by-range with a module map, trimmed tool output, no new builder in the last hour of a window (factory skill section 5a, delegation and collaboration templates).

### 0.5.2

- Work packages: one card per topic on the board, detail tickets as sub-issues off the board, one builder / branch / verify / merge / deploy per package while every sub-issue keeps its checks, assumptions, numbers and merged line (kanban and factory skills, both templates).
- Overlap search before creating a ticket: extend an existing ticket instead of opening a twin.

### 0.5.1

- Budget section in the factory skill and the delegation templates: six builders at once, Sonnet for mechanical tickets, Opus for milestones, trimmed verification, behaviour at the usage window.
- Rule in the templates and the factory skill: a deploy ships only the built site and static assets; never an executable server-side file, no server configuration, no new credentials; free space from FTP commands, the owner's panel, or reported as unknown.

### 0.5.0

- Language presets (`lang`: `en` default, `de`) for column names, labels and ticket wording; `scripts/lang.sh`; templates moved to `templates/<lang>/`. **Breaking:** repositories that relied on the former German defaults must set `"lang": "de"` in `.factory.json` (`init.sh --lang de` writes it), otherwise `board.sh` looks for the English column names.
- `board.sh`: `project` is required, the owner defaults to the repository's owner; the merged line follows the preset.
- New rules from production, in templates and skills: merge-test-push `&&` chains; clean tree after a build; generated data out of git; deploy verified by reading the served page; dependencies in new worktrees; review findings become tickets; numbers in a comment and in the plan's done line; the orchestrator's queue memo; usage-limit pauses; Monitor re-arming; a hands-off list at kickoff; the orchestrator's review comment on the ticket.
- Docs and manifests carry no personal or project names; a private `REPOS.local.md` (gitignored) replaces the registry table in the README.
- Owner pronouns in the templates are neutral.

### 0.4.0

- Renamed from agent-factory to AgentKit.

### 0.3.0

- Assumptions over questions: the **Annahmen** section in the ticket template, the rule in the Autonomy section and the factory skill.

### 0.2.0

- Upstream-first rule, repo registry, repo-specific items preserved by `init.sh --replace-existing`.

### 0.1.0

- Skills `kanban`, `factory`, `factory-init`; scripts `board.sh`, `init.sh`, `run.sh`, `picdiff.mjs`, `verify-report.sh`, `watch.sh`; templates.
