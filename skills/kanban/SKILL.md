---
name: kanban
description: The GitHub Projects kanban workflow of a dark-factory repository - the seven columns, who moves which card, assignees, labels, the ticket template, branch naming and umbrella branches, cleanup, and the exact gh commands (scripts/board.sh). Use whenever you create, read, move or review a ticket, or start work on one.
---

# Kanban: the board is the single source of truth

Every change in the repository has a ticket on its GitHub Project board. Pull before starting; the local checkout is not necessarily the latest state.

## Upstream first

A change to a factory-level rule ( board workflow, ticket format, branch rules, merge and review handling, delegation, verify pattern, scripts ) is made in the AgentKit plugin first: templates, skills, scripts, and a `version` bump in `.claude-plugin/plugin.json`. Then `scripts/init.sh` is re-run in every repository that uses the plugin. Repo-specific content ( ports, umbrella branches, tools, domain rules ) stays in the repository, outside the `<!-- factory:... -->` markers. Never edit the text between the markers in a repository.

## Settings: `.factory.json`

Read from the repo root. `project` is required, the rest is optional. `factory-init` creates it.

```json
{ "project": 1, "owner": "<github handle, default: the repo's owner>", "reviewer": "<default: owner>", "repo": "owner/name",
  "lang": "en",
  "columns": { "epics": "Epics", "backlog": "Backlog", "ready": "Ready", "human": "In Progress (Human)",
               "agent": "In Progress (Agent)", "review": "In Review", "done": "Done" },
  "labels": { "merged": "merged" }, "terms": { "mergedLine": "Merged" },
  "verify": [ { "name": "Build", "cmd": "npm run build" } ], "umbrella": [], "headlessCap": 3 }
```

`lang` picks the preset ( `scripts/lang.sh` ). `en`, the default, is used in this document. `de` names the columns Epics, Backlog, Bereit, In Arbeit (Mensch), In Arbeit (Agent), Zur Review, Fertig, the labels `idee` and `gemergt`, the line `**Gemergt:**`, and the ticket headings **So prüfst du's**, **Annahmen**, **Nach Review geändert – bitte neu prüfen**, **Vorschau**. Read the repository's rendered AGENTS.md section for the names in force; `board.sh` reads them from `.factory.json`.

## Columns and who moves what

| Column | Holds | Moved by |
|---|---|---|
| **Epics** | Umbrella tickets grouping many smaller ones; sub-tickets link to them; often name an umbrella branch | owner; agents may edit an epic's text and add sub-tickets, never remove a sub-ticket or anything the owner specified without their explicit approval |
| **Backlog** | Ideas and tickets, sorted by the owner, most important on top | owner sorts. Agents never reorder it |
| **Ready** | Fully specified, not started | agents may move Backlog -> Ready once a ticket is fully specified |
| **In Progress (Human)** | Manual work for the owner: settings, accounts, a server, external assets. Assigned to the owner | agent or owner |
| **In Progress (Agent)** | Only what an agent is actively coding right now. Queued tickets go to Ready, blocked ones stay in Backlog. Unassigned | agent |
| **In Review** | Branch pushed ( and, with autonomy, merged and labelled `merged` ); assigned to the ticket's author | agent |
| **Done** | The owner's review is done; **Done means approval** | **only the owner**. Never set it, never touch a card already there |

Rules:

- Take the next ticket from the top of **Ready**, else from the top of **Backlog**. Never reorder either. `board.sh next` prints it.
- **Before creating a ticket, search the open ones for overlap** ( `gh issue list --search "<words> in:title"` and the Ready / Backlog columns ). Same files and the same goal: extend the existing ticket ( a new section, a "Changed after review" section if it is in review ) instead of opening a second one. Two halves of one problem are one ticket.
- **Work packages ( topic cards ).** Tickets that share files or an order are grouped into one package ticket per topic: it is the only card on the board, the owner sorts topics, not dozens of cards. The detail tickets become its sub-issues ( `POST /repos/{o}/{r}/issues/{n}/sub_issues`, or a checklist of `#n` links ) and leave the board. One package = one builder, one branch, one worktree, one verify, one merge, one deploy. Every sub-issue keeps its own checks, **Assumptions**, numbers comment and a `**Merged:** <sha>` line with the package's merge; the package card carries one box per sub-issue plus the verify / deploy box and goes to In Review when all are done. A sub-issue that needs another base ( `main` instead of the umbrella ) gets its own branch inside the package. Packages are cut by the orchestrator when the owner approves them; the owner can still pull a single sub-issue out and put it on the board. GitHub's "Auto-add sub-issues to project" ( and any "Auto-add to project" ) workflow must be off ( UI only, see `factory-init` ); `board.sh tidy` takes stray sub-issue cards off the board.
- Read a card's current status before moving it. Agents move cards only to Ready, In Progress (Agent) or In Review.
- Every change request the owner mentions goes into its ticket and onto the board right away: update the checklist or open a new short ticket, and move the card back to In Progress (Agent) if it was in review. Never keep working on a ticket in In Review: move it back first and remove the review assignee.
- A card goes to In Review only once its branch is pushed, and is assigned to the ticket's author immediately ( `board.sh move` does both ).
- **Autonomy:** after reviewing its own work ( all checks in the ticket done, the verify command passes, smoke test of the merged tree ) an agent merges the branch itself into `main`, or into the umbrella branch the ticket or epic names. The card still goes to In Review, gets the label `merged` and a line `**Merged:** <sha> in <branch>` in the ticket ( `board.sh merged` ). Changes the owner asks for afterwards go through the same branch and are merged again.
- Only the owner moves a card to Done.
- When you name a ticket to the owner, name its title too: "#31 ( Title )", never a bare number.

## Labels

`idea` ( not yet specified ), `feature`, `bug`, `documentation`, `merged` ( agent merged, waiting for the owner's review ). `factory-init` creates them.

## Ticket template ( short )

Tickets are written in the repository's ticket language ( the `lang` preset ); docs and code comments are English. Closed tickets keep the same format.

```
<1-2 sentences: the goal>

**How to check**
- [ ] <a concrete check the owner can do in the browser, headset or with one command>
- [ ] <visible changes: context captures next to the nearest existing neighbours ( same distance, same state ): <paths>; what differs and why>

**Assumptions**                                 ( what the agent decided itself because the repo did not answer it )
- <assumption> — <why> — <what it touches>

**Changed after review – please re-check**       ( only when something changed after a review )
- [ ] <only what has to be looked at again>

**Branch:** `feat/<id>-<slug>` (local: `git fetch && git checkout feat/<id>-<slug> && <local run command>`)
**Preview:** <preview link or `None (CI / docs / tooling / framework change only)`>
```

- Pure framework, CI, docs or tooling changes get no dummy preview link, and the check is a CLI, build or test step under "How to check". Visible changes link straight to the local URL or preview.
- **Assumptions over questions.** An open point is looked up in the repo first ( plan, tickets, canon, the owner's earlier decisions and art direction, code ). If it is not there, the agent assumes, puts one line per assumption under **Assumptions** ( the assumption, why, what it touches ), prominently, and keeps going; the owner corrects afterwards. Ask only when an assumption would be irreversible or expensive to undo ( money, accounts, deleting the owner's work, a canon-level fact ), all questions at once at kickoff.
- **Numbers.** A ticket that changes performance, precision or a measurable look gets a comment with the measured numbers before and after ( "Numbers" ), and links to the captures. A plan's milestone gets a dated done line with those numbers in the plan.
- Changes requested after a review never go into the original checklist; they get their own section "Changed after review – please re-check". A fix pass after the owner's review runs on the same branch; the card goes back to In Progress (Agent) first.
- Reference assets the owner supplies ( images, files ) are committed with speaking names in the project's reference folder and also attached with `gh issue create --attach`.
- A finished check report ( `scripts/verify-report.sh` ) can be added as a comment: `scripts/verify-report.sh | gh issue comment <n> --body-file -`.
- The orchestrator's review goes on the ticket as a comment ( "Review (Orchestrator)" ): what was checked with numbers, what the owner has to judge, what follow-up tickets were opened. For a visible change it names the **neighbour comparison** ( "Nachbarvergleich" in `de` ) with the capture paths and says whether the element looks as if it had always been there; "the old flaw is gone" is never the acceptance.

## Branches

One ticket or one work package, one branch, one git worktree; never bundle unrelated tickets. Name: `<type>/<id>-<short-slug>` ( a package: `feat/<package id>-package-<slug>` ) with type `feat`, `fix`, `ci`, `docs` ( also `refactor`, `chore` ). The id is the ticket's number. Commits are Conventional Commits with scopes, e.g. `feat(scope): ...`.

- Branch from the current `main`, unless the ticket or its epic names an **umbrella branch** ( stacked work: a long-lived branch that collects an epic's tickets ): then branch from that and merge back into it. The umbrella and `main` are merged into each other once per batch of tickets, with the verify command on the merged tree each time; the umbrella itself reaches `main` when the owner says so.
- Commit work in progress early and often; a restarted session must not lose it.
- A new worktree needs its dependencies installed before any check runs in it; a check that fails for a missing module proves nothing.
- Squash only onto the branch's own base ( `git reset --soft $( git merge-base HEAD origin/main )` ), never onto an `origin/main` that a fetch has moved: the squashed tree would silently undo what was merged meanwhile.
- Bring `main` in by merging it into the branch, never by rebasing a pushed branch. No force-push.
- **Merge, test, push in one `&&` chain**, never with `;`. A push must never go out before the test result is read.
- A build must leave the working tree clean: a file the build regenerates is ignored or committed, never left dirty at merge time.
- Generated data ( tiles, caches, renders, datasets ) stays out of git whatever its size; the ticket says where it lives and how it is rebuilt. Hosting is the owner's decision.
- A deploy is finished when the served page has been read back and names this build's entry file. Deploy scripts upload the entry page every time.
- **Cleanup only after the card is in Done** ( until then the owner can still ask for changes ): `git push origin --delete <branch>`, `git worktree remove <path>`.
- Several agents run at once: each dev server gets its own port ( the app's fixed default or `--port <n>` ), and an agent stops only the processes it started, by PID. The owner's own dev server port is never touched.
- Merging into a worktree another agent works in changes files under it: say so in the ticket, and prefer to merge when that agent is between steps.
- Headless browser checks run muted, windowless and without an audio context, through the repository's one launcher, under `scripts/run.sh <timeout s> <cmd>`, which waits while `headlessCap` ( default 3 ) headless browsers run or the load is above the core count ( `factory` skill, 5b ).

## `board.sh` and the gh commands

`scripts/board.sh` lives in this plugin ( `${CLAUDE_PLUGIN_ROOT}/scripts/board.sh` ); run it inside the target repo.

```
board.sh ids <project> <owner>        # project id, Status field id, option ids; reports missing columns (read-only)
board.sh list [column]                # cards (read-only)
board.sh next                         # top of Ready, else Backlog (read-only)
board.sh status <issue>               # column, assignees, labels (read-only)
board.sh add <issue-url> "<column>"   # put an issue on the board
board.sh move <issue> "<column>"      # reads the status first; refuses Done (as target or source); In Review assigns the author, leaving it removes the assignee
board.sh merged <issue> <sha> <branch>  # **Merged:** line + label merged + author as assignee
board.sh tidy                         # cards without a column whose issue is a sub-issue: off the board
board.sh state [--json]               # draft of STATE.md: In Progress (Agent), In Review + merged with the merged line, Ready top 10, Backlog top 5,
                                      #   the owner's cards, cards without a column; 1 GraphQL + 1 REST call (read-only)
```

The raw commands behind it ( use them when the script does not fit ):

```bash
gh project field-list <n> --owner <o> --format json                  # ids of the Status field and its options
gh project item-list <n> --owner <o> --format json --limit 300       # cards: .items[].id, .status, .content.number, .title
gh project item-add <n> --owner <o> --url <issue url> --format json --jq .id
gh project item-edit --id <item> --project-id <project id> --field-id <status field id> --single-select-option-id <option id>
gh issue create --title "..." --label feature --body-file ticket.md [--attach file.png]
gh issue edit <n> --add-label merged --add-assignee <login> --remove-assignee <login> --body-file ticket.md
gh label create merged --color 0E8A16
gh issue view <n> --json projectItems,assignees,labels            # what the watcher polls
```

`gh` needs the `project` scope: `gh auth refresh -s project`.
