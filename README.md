# AgentKit

A Claude Code plugin that runs a repository as a **dark factory**: agents take tickets from a GitHub Projects kanban board, build on their own branch and worktree, verify, merge, and hand the card back for review. An orchestrating session starts the next tickets itself and only stops for what truly needs the owner: approving a card as done, money, accounts, hardware, facts of the product's world, and removing something the owner specified.

It is three skills, a handful of shell scripts and two templates. Nothing in it is specific to a framework or a language; the repository supplies its own verify command.

## How it works

1. **The board is the source of truth.** Seven columns: Epics, Backlog, Ready, In Progress (Human), In Progress (Agent), In Review, Done. The owner sorts the Backlog; agents take from the top of Ready, else Backlog, and never reorder.
2. **One ticket, one branch, one worktree, one port block.** Branches are `<type>/<id>-<slug>`, from `main` or from an umbrella branch the ticket's epic names.
3. **Agents verify, then merge their own work.** The repository's verify command must pass on the merged tree. The card goes to In Review with the label `merged` and a `**Merged:** <sha> in <branch>` line. Only the owner moves a card to Done.
4. **Assumptions over questions.** What the repository does not answer, the agent decides, records under **Assumptions** in the ticket, and keeps going. Questions that must be asked are asked all at once, at kickoff.
5. **The orchestrator reviews.** When a builder reports, the orchestrating session checks the diff against the ticket, runs the verify command, reads the builder's assumptions, posts a review comment with what the owner still has to judge, and starts the next ticket.

## Install

```bash
claude plugin marketplace add niklasbrandt/AgentKit
claude plugin install agentkit@agentkit
```

Inside Claude Code: `/plugin marketplace add niklasbrandt/AgentKit`, then `/plugin install agentkit@agentkit`. To try a checkout without installing: `claude --plugin-dir <path to this repo>`.

Requirements: `gh` (once: `gh auth refresh -s project`), `jq`, `python3`. `node` plus `puppeteer-core` and a Chrome only for `picdiff.mjs`.

**Cursor, Antigravity, or no plugin host:** the rules are plain Markdown. Run `scripts/init.sh` from a checkout of this repo inside the target repo, or copy `templates/<lang>/AGENTS.collaboration.md` into the repo's `AGENTS.md` and fill the `{{...}}` placeholders by hand. The skills in `skills/` are Markdown you can paste into `.cursor/rules` or `.agents/skills/`; call `board.sh` by path.

## Quick start

```bash
cd my-repo
gh auth refresh -s project                      # once
gh project list --owner <you>                   # find or create the board, note its number
claude                                          # then: /factory-init
#   it asks for the project number, verify command, local run command, language; writes AGENTS.md / CLAUDE.md sections,
#   .factory.json and the labels, and reports columns missing on the board (add them under Project settings > Status)
gh issue create --label feature --title "..." --body-file ticket.md     # ticket in the template of the kanban skill
scripts/board.sh add <issue-url> "Ready"
claude                                          # then: "run the factory" or /factory <plan or epic>
```

## The three skills

| Skill | What it is |
|---|---|
| `kanban` | The board workflow: columns, who moves what, assignees, labels, the ticket template, branch naming, umbrella branches, cleanup after Done, and the exact `gh` commands (`scripts/board.sh`). |
| `factory` | The orchestrator loop: take the top of Ready, one background subagent per ticket with its own branch, worktree, ports, model and effort, review with the verify command, merge, hand the card to In Review marked `merged`, start the next. Includes the rules learned in production: merge-test-push chains, the queue memo, usage-limit pauses, compaction, review findings as tickets. |
| `factory-init` | Writes the Collaboration section of AGENTS.md and the Delegation section of CLAUDE.md from `templates/<lang>/`, creates labels and `.factory.json`, checks the board's columns. |

## Scripts

All in `scripts/`, called by path (`${CLAUDE_PLUGIN_ROOT}/scripts/...` inside Claude Code).

| Script | Does |
|---|---|
| `board.sh ids \| list \| next \| status <n> \| add <url> "<col>" \| move <n> "<col>" \| merged <n> <sha> <branch>` | Board operations with the guards built in: never sets Done, never touches a card in Done, assigns the author on In Review. |
| `init.sh` | What `factory-init` runs. Idempotent: sections are replaced between `<!-- factory:...:start/end -->` markers. |
| `lang.sh` | The `en` and `de` presets for column names, labels and ticket wording. Sourced by the other scripts. |
| `run.sh <timeout s> <cmd...>` | Watchdog: TERM after the timeout, then kills orphaned headless Chromes. Also for a dev server in the background. |
| `verify-report.sh [--quick]` | Runs the `verify` list of `.factory.json` and prints a ticket section with PASS / FAIL per check. |
| `picdiff.mjs <A> <B> [--out dir] [--fail pct]` | Share of differing pixels between two captures or folders, decoded in headless Chrome, no image library. |
| `watch.sh [issue ...]` | One line per change (card column, assignees, labels; session transcripts going quiet or appearing) for Claude Code's Monitor tool. |

## `.factory.json`

Lives at the repo root. `project` is required; everything else has a default.

```json
{
  "project": 1,
  "owner": "<github handle, default: the repository's owner>",
  "reviewer": "<default: owner>",
  "lang": "en",
  "localRun": "npm install && npm run dev",
  "verify": [ { "name": "Build", "cmd": "npm run build" },
              { "name": "Pictures", "cmd": "node picdiff.mjs before after --fail 6", "slow": true } ],
  "umbrella": [],
  "columns": { "ready": "Ready" },
  "labels": { "merged": "merged" },
  "terms": { "mergedLine": "Merged" }
}
```

`lang` selects the preset for columns, labels and the wording of the ticket template and the verify report. `en`: Epics, Backlog, Ready, In Progress (Human), In Progress (Agent), In Review, Done; labels `idea`, `merged`; line `**Merged:**`. `de`: Epics, Backlog, Bereit, In Arbeit (Mensch), In Arbeit (Agent), Zur Review, Fertig; labels `idee`, `gemergt`; line `**Gemergt:**`. Any single name can be overridden in `columns`, `labels` or `terms`.

## Upstream first

A factory-level rule (board workflow, ticket format, branch rules, merge and review handling, delegation, the verify pattern, scripts) is changed **here** first, with a `version` bump in `.claude-plugin/plugin.json`. Then `scripts/init.sh` is re-run in every repository that uses the plugin; the rendered sections update in place between their markers. Repo-specific content (ports, umbrella branches, tools, domain rules) lives in the repository outside the markers, in a `### Repo-specific` subsection.

Keep your own list of adopting repositories in `REPOS.local.md` (gitignored) or wherever suits you.

## Rules learned in production

These are in the templates and skills; the short version:

- **Merge, test, push in one `&&` chain.** A `;` once pushed a branch before its smoke test had been read.
- **A build must leave the tree clean.** A file the build regenerates is ignored or committed, never left dirty at merge time.
- **Generated data stays out of git**, however small the estimate was. Record where it lives and how it is rebuilt; hosting is the owner's call.
- **A deploy is done when the served page is checked**, not when the upload returns. A deploy that skipped unchanged-size files served a stale entry page for two days while every new bundle was uploaded.
- **New worktrees need their dependencies installed** before any check runs in them.
- **Review findings become tickets**, not side fixes: a flaw found while reviewing ticket A beyond its scope gets its own short ticket.
- **Numbers, not adjectives.** Performance, precision and look changes get the measured before and after in a comment; plan milestones get a dated done line with those numbers.
- **The orchestrator's state lives outside the conversation**: a queue memo (running builders with ports and worktrees, queued tickets in dependency order, which tickets must not run at once), the tickets, the branches. The conversation can be compacted at any time.
- **Usage limits pause builders; they do not kill them.** Resume each with a message after the window resets.
- **Ask for a hands-off list at kickoff**: areas the owner wants to decide in person first; do not touch them, not even with drafts.
- **Never two performance measurements at once.**
- **Six builders at once, Sonnet for the mechanical tickets.** The usage limit is a shared token budget per window; eight Opus builders empty it in three hours and idle for two.
- **Work packages, not forty cards.** Tickets that share files become one topic card with sub-issues; the owner sorts topics, one builder runs the package on one branch, every sub-issue keeps its own checks and merged line.
- **Search before you file.** Two halves of one problem are one ticket; extend, don't duplicate.
- **Nothing executable on a server, ever.** A deploy ships the built site and static assets; free space comes from FTP commands, the owner's panel, or is reported as unknown.

## Changelog and licence

See [CHANGELOG.md](CHANGELOG.md). MIT, see [LICENSE](LICENSE).
