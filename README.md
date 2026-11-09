# AgentKit

A Claude Code plugin that runs a repository as a **dark factory**: agents take tickets from a GitHub Projects kanban board, build on their own branch and worktree, verify, merge, and hand the card back for review. An orchestrating session starts the next tickets itself, reviews and deploys, and stops only for what truly needs the owner: approving a card as done, money, accounts, hardware, facts of the product's world, and removing something the owner specified.

It is three skills, eight scripts, the rule templates in two languages and a state-sheet skeleton. Nothing in it is specific to a framework or a language; the repository supplies its own verify command and, if it deploys, its own single deploy script.

## How it works

1. **The board is the source of truth.** Seven columns: Epics, Backlog, Ready, In Progress (Human), In Progress (Agent), In Review, Done. The owner sorts the Backlog; agents take from the top of Ready, else Backlog, and never reorder. Tickets that share files become one **work package**: one topic card on the board, the detail tickets as its sub-issues off it.
2. **One ticket or package, one branch, one worktree, one port block.** Branches are `<type>/<id>-<slug>`, from `main` or from the umbrella branch the ticket's epic names.
3. **Two phases per ticket.** An Opus builder designs, implements and stops at a short handover; a Sonnet finisher runs the full verify, takes the captures, writes the ticket and merges under the repository's merge lock. Merge, verify and push run in one `&&` chain.
4. **The orchestrator reviews and deploys.** It checks the diff against the ticket, runs the verify command, reads the builder's assumptions, judges visible changes against their neighbours, posts a review comment, and hands the card to In Review with the label `merged` and a `**Merged:** <sha> in <branch>` line. After a batch of merges it verifies the tip once and deploys it once. Only the owner moves a card to Done.
5. **Assumptions over questions.** What the repository does not answer, the agent decides, records under **Assumptions** in the ticket, and keeps going. Questions that must be asked are asked all at once, at kickoff, together with a hands-off list.
6. **The state lives outside the chat.** `STATE.md` at the repo root ( gitignored ) holds who runs what, the queue, open owner decisions and limits. A fresh or compacted session reads it, runs `board.sh state`, and continues; shift-lead subagents keep the root session thin, and nobody asks the owner for a new session.

### Who does what

| Role | Is | Does |
|---|---|---|
| **Owner** | The human | Sorts the Backlog, answers the kickoff questions, names the hands-off list, judges cards in In Review, moves cards to Done, decides money, accounts, hosting, canon and taste. |
| **Orchestrator** | The Claude Code session the owner opens | Kickoff, picks tickets, prepares branch / worktree / ports, starts builders, reviews, merges stragglers, deploys once per batch, keeps `STATE.md`, waits with Monitor on `watch.sh`. |
| **Shift lead** | A long-lived orchestrator subagent, one per batch | Runs the loop for its batch, hands back decisions and short summaries, rewrites `STATE.md` when its context grows and makes way for the next. |
| **Builder** | A background subagent, Opus by default, Sonnet for mechanical tickets | Builds the ticket on its branch, commits early, records assumptions, hands over with context captures. Never deploys, never moves a card to Done. |
| **Finisher** | A Sonnet subagent | Full verify, captures, the ticket's checks and numbers, merge under the lock, `board.sh merged`. |

### The batch cycle

```
pick ( board.sh next ) -> In Progress (Agent) -> branch + worktree + install + ports -> builder ( model, effort )
  -> handover -> finisher: verify, captures, ticket, merge under mergelock.sh, push in one && chain
  -> orchestrator review: diff vs ticket, verify-report.sh, picdiff.mjs, neighbour comparison, assumptions
  -> board.sh merged + review comment -> In Review -> STATE.md rewritten -> next ticket
per batch: verify on the tip of main / umbrella -> one deploy through the repo's deploy script -> served page read back -> sha + entry file in STATE.md
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
gh project list --owner <you>                   # find or create the board, note its number
claude                                          # then: /factory-init
#   it asks for the project number, language preset, verify command, local run command, umbrella branches and the owner's dev port;
#   writes the AGENTS.md / CLAUDE.md sections, .factory.json, the labels and the STATE.md skeleton, and reports columns missing
#   on the board ( add them under Project settings > Status; switch the "Auto-add" workflows off )
gh issue create --label feature --title "..." --body-file ticket.md     # ticket in the template of the kanban skill
scripts/board.sh add <issue-url> "Ready"
claude                                          # then: "run the factory" or /factory <plan or epic>
```

## The three skills

| Skill | What it is |
|---|---|
| `kanban` | The board workflow: columns and who moves what, assignees, labels, overlap search before filing, work packages, the ticket template ( checks, Assumptions, "Changed after review", branch, preview ), branch naming and umbrella branches, the merge and deploy rules, cleanup after Done, and the exact `gh` commands behind `board.sh`. |
| `factory` | The orchestrator loop: kickoff ( `STATE.md`, `board.sh state`, assumptions, hands-off list, `caffeinate`, the watcher ), pick / prepare / delegate / review / merge / hand back / next, what needs the owner, the Monitor watcher, long sessions ( usage limits, compaction, shift leads ), the neighbour test for visible changes, the budget rules ( six builders, model mix, two phases, merge lock, read by range ), headless checks that never touch the owner's machine, and the per-ticket checklist. |
| `factory-init` | Finds or creates the board, asks the owner's settings in one message, runs `init.sh`, tells the owner which project workflows to switch off, checks that `CLAUDE.md` imports `AGENTS.md`, commits. |

## Scripts

All in `scripts/`, called by path ( `${CLAUDE_PLUGIN_ROOT}/scripts/...` inside Claude Code ), run inside the target repository.

| Script | Does |
|---|---|
| `board.sh ids <project> <owner> \| list [column] \| next \| status <n> \| add <url> "<col>" \| move <n> "<col>" \| merged <n> <sha> <branch> \| tidy \| stale [--minutes N] [--json] \| state [--json]` | Board operations with the guards built in: never sets Done, never touches a card in Done, assigns the author on In Review and removes the assignee on leaving it. `tidy` takes stray sub-issue cards off the board. `stale` ( no GitHub call ) lists every git worktree with minutes since its last commit and last file change, whether a process runs inside it, and the verdict `STALE` ( both ages over N, default 45, no process ), plus the merge lock and its age ( a lock over 30 minutes with no `mergelock.sh` process is stale ); the watchdog's eyes. `state` prints a draft of `STATE.md` from the board in one GraphQL and one REST call. |
| `init.sh --project <n> [--lang en\|de] [--owner <handle>] [--name "<Full Name>"] [--verify "<cmd>"] [--run "<cmd>"] [--umbrella "a, b"] [--replace-existing] [--dry-run]` | What `factory-init` runs. Idempotent: sections are replaced between `<!-- factory:collaboration:start/end -->` and `<!-- factory:delegation:start/end -->` markers. Writes `.factory.json`, the labels, the `STATE.md` skeleton and its `.gitignore` line, then runs `board.sh ids`. Existing `.factory.json` values are the defaults for omitted flags. |
| `lang.sh` | The `en` and `de` presets for column names, labels and ticket wording. Sourced by the other scripts, never run. |
| `run.sh <timeout s> <cmd...>` | Watchdog for headless work: TERM after the timeout, then kills orphaned headless Chromes. Waits first while `headlessCap` headless browsers run or the 1-minute load is above the core count. Also for a dev server in the background ( `FACTORY_LOAD_WAIT=0` ). |
| `verify-report.sh [--quick] [--timeout 900]` | Runs the `verify` list of `.factory.json`, each under `run.sh`, and prints a ticket section with PASS / FAIL per check in the preset's wording. `--quick` skips `"slow": true` entries. Exit 1 on any FAIL. |
| `picdiff.mjs <A> <B> [--out dir] [--threshold 24] [--fail pct]` | Share of differing pixels between two captures or two folders of PNGs, decoded in headless Chrome, no image library. `--out` writes a sheet per pair, `--fail` makes it exit 1 above the share. |
| `mergelock.sh <cmd...>` | One lock per repository ( keyed on the common git dir, so every worktree shares it ) around merge, verify and push: a second builder waits instead of verifying twice. |
| `watch.sh [issue ...]` | One line per change for Claude Code's Monitor tool: a card's column, assignees or labels; a session transcript appearing, going quiet or becoming active. |

### Environment variables the scripts read

| Variable | Script | Meaning |
|---|---|---|
| `FACTORY_JSON` | all | Path of the settings file ( default `<repo>/.factory.json` ). |
| `FACTORY_OWNER=1` | `board.sh` | Lifts the Done guards; for the owner's own shell only. |
| `FACTORY_LOAD_WAIT` | `run.sh` | Seconds to wait for the cap and load guard ( default 600, `0` = no guard ). |
| `FACTORY_CHROME_PATTERN` | `run.sh` | Pattern that identifies headless Chromes ( default `puppeteer_dev_chrome_profile` ). |
| `FACTORY_LOCK`, `MERGELOCK_WAIT` | `mergelock.sh` | Lock path ( default `/tmp/factory-<repo>.lock` ) and the longest wait in seconds ( default 3600 ). |
| `CHROME` | `picdiff.mjs` | Path of the Chrome to decode with ( default: the installed one; headless checks of a repo should point it at a Chrome for Testing build ). |
| `INTERVAL`, `QUIET`, `TRANSCRIPTS` | `watch.sh` | Poll interval ( 30 s ), quiet threshold ( 300 s ), transcript directory ( derived from the repo path ). |

## Templates and `STATE.md`

`templates/<lang>/AGENTS.collaboration.md` is rendered into the repository's `AGENTS.md` ( the Collaboration section: upstream first, board, autonomy, tickets, branches ), `templates/<lang>/CLAUDE.delegation.md` into `CLAUDE.md` ( the Delegation section: how the orchestrator uses Claude Code's tools ). Placeholders: `{{OWNER}}`, `{{OWNER_NAME}}`, `{{PROJECT}}`, `{{PROJECT_NAME}}`, `{{PROJECT_URL}}`, `{{VERIFY}}`, `{{LOCAL_RUN}}`, `{{UMBRELLA_NOTE}}`, `{{TRANSCRIPT_DIR}}`, `{{PLUGIN_URL}}`. Repo-specific facts ( ports, where the plan lives, the deploy command, canon ) go outside the markers in a `### Repo-specific` subsection; `init.sh --replace-existing` moves them there from an old unmarked section.

`templates/STATE.md` is the orchestrator's state sheet, copied to the repo root by `init.sh` and gitignored. Fixed sections: Running ( with the shift lead ), Waiting, Queue, Owner decisions open, Limits, Last hand-backs ( ticket, sha, deployed entry file, date ), Notes. It is rewritten, never appended, at every hand-back, spawn and owner decision.

## `.factory.json`

Lives at the repo root. `project` is required; everything else has a default. `init.sh` writes it, `board.sh`, `run.sh`, `verify-report.sh` and `watch.sh` read it.

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
  "headlessCap": 3,
  "columns": { "ready": "Ready" },
  "labels": { "merged": "merged" },
  "terms": { "mergedLine": "Merged" }
}
```

- `lang` selects the preset for columns, labels and the wording of the ticket template and the verify report. `en`: Epics, Backlog, Ready, In Progress (Human), In Progress (Agent), In Review, Done; labels `idea`, `merged`; line `**Merged:**`. `de`: Epics, Backlog, Bereit, In Arbeit (Mensch), In Arbeit (Agent), Zur Review, Fertig; labels `idee`, `gemergt`; line `**Gemergt:**`. Any single name can be overridden in `columns`, `labels` or `terms`.
- `verify` entries are `{ name, cmd, slow }` or a plain command string; `slow` entries are skipped by `verify-report.sh --quick`.
- `deploy` is read by the orchestrator ( the `factory` skill ), not by a script: it names the one script that deploys a verified tip and carries the repository's own gates.
- `headlessCap` is the machine-wide number of headless browsers `run.sh` allows at once ( default 3 ).

## Rules learned in production

These are in the templates and skills; the short version, grouped.

**Git, merge, build**

- **Merge, test, push in one `&&` chain.** A `;` once pushed a branch before its smoke test had been read.
- **Merge under the lock.** `mergelock.sh` serialises merge, verify and push per repository; waiting is free, a second verify is not.
- **A build must leave the tree clean.** A file the build regenerates is ignored or committed, never left dirty at merge time.
- **Generated data stays out of git**, however small the estimate was. Record where it lives and how it is rebuilt; hosting is the owner's call.
- **New worktrees need their dependencies installed** before any check runs in them.

**Deploy**

- **The orchestrator deploys, once per batch, never a builder.** Builders that each deployed after their own merge shipped a build missing another merge's generated files and broke the live page; the deploy is one step from the verified tip through one gated script.
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

**Sessions and state**

- **The orchestrator keeps `STATE.md`**: running agents, waits, queue, open owner decisions, limits, last hand-backs, notes, rewritten at every hand-back, spawn and owner decision. Long sessions lost exactly what was in no ticket.
- **A fresh session reads `STATE.md`, then `board.sh state`**, and never asks the owner to open a new one: compaction plus the sheet is lossless, and shift-lead subagents keep the root session thin.
- **A stalled agent is found by the orchestrator, not by the owner.** A finishing agent once stood for two hours with no commit, no process and no message. Builders now commit or post a line at least every 30 minutes and say what they wait on ( never more than 20 minutes on a lock or another agent unreported ); the orchestrator runs `board.sh stale` every 30 minutes, pings at 45 minutes without progress, stops and replaces the agent on the same worktree 20 minutes later, and never waits on an agent for more than an hour. `STATE.md` shows `Last progress` per agent.
- **Usage limits pause builders; they do not kill them.** Resume each with a message after the window resets.

**Budget**

- **Six builders at once, Sonnet for the mechanical tickets.** The usage limit is a shared token budget per window; eight Opus builders empty it in three hours and idle for two.
- **Two phases per ticket.** Opus builds, a Sonnet finisher verifies, captures, writes the ticket, merges under the lock: a third of the tokens at a fifth of the price.
- **Read by range, never whole.** A generated module map tells builders where to look in big files.
- **No new builder in the last hour of a window**: it would pay its read-in twice.

**Headless checks**

- **Headless checks never touch the owner's machine**: muted, windowless, no audio context, one launcher, at most `headlessCap` at once and none above the core count in load. A muted headless browser that opened an audio context still made the owner's speakers pop.
- **Headless checks never use the owner's installed browser bundle**: the OS then thinks the owner's browser is running and it will not start; use a separate build ( Chrome for Testing ) through the one launcher, path overridable by env.

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
