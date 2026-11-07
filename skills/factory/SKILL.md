---
name: factory
description: The orchestrator loop for a dark-factory Claude Code session - read the board and plan, take the top of Ready (else Backlog), start a background subagent per ticket with its own branch, worktree, ports, model and effort, review each result with the repo's verify command, merge, hand the card to In Review marked merged, and keep going. Use when the owner kicks off work on a board ("work through the board", "start the next tickets", "run the factory", "/factory <plan or epic>").
---

# Factory: the orchestrator loop

You are the orchestrating session. Builders are background subagents. The board ( see the `kanban` skill ) is the source of truth; the repository's AGENTS.md "Collaboration" section and `.factory.json` hold its rules and settings ( column names follow the `lang` preset; this document uses the `en` names ). Helpers: `${CLAUDE_PLUGIN_ROOT}/scripts/` ( `board.sh`, `watch.sh`, `run.sh`, `verify-report.sh`, `picdiff.mjs` ).

## Upstream first

A change to a factory-level rule ( board workflow, ticket format, branch rules, merge and review handling, delegation, verify pattern, scripts ) is made in the AgentKit plugin first: templates, skills, scripts, and a `version` bump in `.claude-plugin/plugin.json`. Then `scripts/init.sh` is re-run in every repository that uses the plugin. Repo-specific content ( ports, umbrella branches, tools, domain rules ) stays in the repository, outside the `<!-- factory:... -->` markers. Never edit the text between the markers in a repository.

## 0. Kickoff ( once )

1. `git fetch`, read `AGENTS.md`, `CLAUDE.md`, `.factory.json`, and the plan or epic the owner named. Read the board: `board.sh list`. Check `ListAgents` and the transcripts of peer sessions ( `~/.claude/projects/<project>/<session>.jsonl`, read-only; read the end to tell finished from waiting for an answer ) so you never duplicate a session the owner already opened.
2. **Assumptions over questions.** Open points are answered from the repo first ( the plan, the tickets, rulings / canon, the owner's earlier decisions and art direction, the code ). What the repo does not answer, you assume, in line with that direction, and have it written under **Assumptions** in the ticket ( one line each: the assumption, why, what it touches ). Ask the owner only when an assumption would be irreversible or expensive to undo ( money, accounts, deleting their work, a canon-level fact many things build on ), and then **all questions at once, in one message, now**. A wrong assumption costs a change, a stalled ticket costs a night.
3. **Ask for a hands-off list** in the same message: areas the owner wants to decide in person before any agent touches them. Record it and keep every builder out of them, drafts included.
4. **Write the queue memo** and keep it current: running builders ( ticket, branch, worktree, ports, model ), queued tickets in dependency order with the reason for the order ( "A and B both edit file X: B after A" ), the owner's constraints, and the per-batch merge rule. Put it where it survives the conversation ( your memory directory or a scratch file ), never only in the chat: the conversation can be compacted at any time, and everything else lives in the tickets and on the branches.
5. Keep the machine awake while work runs: on macOS start `caffeinate -dimsu` in the background ( note its PID, stop it when the work is finished or the session ends ).
6. Start the watcher ( below ).

## 1. The loop

Repeat until Ready and Backlog hold nothing you may take ( or the owner's scope is done ):

1. **Pick:** the top of Ready, else the top of Backlog ( `board.sh next` ). Never reorder. Skip what needs the owner ( below ), blocked tickets stay in Backlog. If a ticket is vague, specify it ( short ticket, `kanban` template ) and move it to Ready first. Tickets that edit the same files run in sequence; the queue memo says which.
2. **Prepare:** `board.sh move <n> "In Progress (Agent)"`. Branch `<type>/<id>-<slug>` from `main`, or from the umbrella branch the ticket or epic names. One worktree per ticket: `git worktree add ../<repo>-<id> -b <branch> <base>`, then the repo's install step in it. Pick a port block no other running agent uses ( the app's default or `--port <n>` ); never the owner's own dev server port.
3. **Delegate:** start a **background subagent** ( Agent tool, `run_in_background` ) per ticket. Several tickets run in parallel when they do not touch the same files; stacked ones run in order. Give each agent the ticket text, the branch, the worktree path, its ports, the verify command, the list of peer ports and worktrees, and these rules: assume and record under **Assumptions** in the ticket instead of asking ( ask only for what is irreversible or expensive to undo, see kickoff ), commit early and often on the branch, push it, never touch other worktrees, stop only processes you started ( by PID ), headless browsers only under `run.sh`, merge-test-push in one `&&` chain, a clean tree after a build, no generated data in git, never move cards to Done, report with what was done, what was checked with numbers, what is open, and every assumption.
   - **Model and reasoning effort per ticket ( set `effort` explicitly ):**
     - Opus, `high`: large tickets and milestones ( the default for builders ).
     - Opus, `xhigh`: foundations that later work builds on ( a new API, coordinate maths, a data model ).
     - Sonnet, `medium`: small, mechanical, well-specified tickets.
     - A plan may set it per milestone; that wins. You ( the orchestrator ) run at `high` and raise it only for a real judgement call: reviewing an API, a milestone that missed its target.
4. **Review** when the agent reports: read the diff against the ticket's checks ( footprint: files, sizes, nothing generated or binary that does not belong ), run the repo's verify command in the agent's worktree ( `verify-report.sh`, or the commands in `.factory.json` ), look at screenshots or output for visible changes ( `picdiff.mjs` before / after ). Read the builder's **Assumptions**: check each fits the plan and art direction ( send it back if not ), make sure they are in the ticket. Then post the review on the ticket as a comment ( "Review (Orchestrator)": what was checked with numbers, what the owner has to judge, side effects such as tools the builder installed on the machine ) and list the assumptions in your report to the owner so they can correct them. Flaws you find beyond the ticket's scope become new short tickets, not side fixes. Send fixes back to the same agent ( SendMessage ) or start a follow-up; do not merge on a FAIL.
5. **Merge:** merge `main` ( or the umbrella branch ) into the ticket branch first, run the verify command on the merged tree ( smoke test ), then merge into `main` or the umbrella branch and push, in one `&&` chain. Merge when no other agent is in the middle of a step in the target's worktree; say in the ticket if you merged into a worktree someone works in. No force-push, no rebase of pushed branches. If the repository deploys per merged milestone ( `.factory.json` `deploy` or the plan says so ), deploy from the merged tree and read the served page back.
6. **Hand back:** `board.sh merged <n> <sha> <branch>` ( line, label `merged`, assignee ), then `board.sh move <n> "In Review"`. Paste the verify report into the ticket ( `verify-report.sh | gh issue comment <n> --body-file -` ). Changes the owner asks for later go through the same branch and are merged again; move the card back to In Progress (Agent) first, with a "Changed after review" section.
7. **Next:** start the next tickets yourself and update the queue memo. Do not wait for the owner between tickets of an approved plan.

Never run two performance measurements ( frame times, benchmarks, profilers ) at once: they distort each other. Queue them, or use a lock file. Functional checks may run in parallel on separate ports.

## 2. What needs the owner

Stop and ask only for these, and keep working on everything else:

- moving a card to **Done** ( never do it; never touch a card already there )
- money, accounts, credentials, server settings, hardware, external assets ( such a ticket goes to In Progress (Human), assigned to them )
- canon-like world facts: anything that decides what is true in the product's world, story or domain ( the repo says where its canon lives )
- hosting of large generated data ( where gigabytes of tiles, renders or datasets live; the builder keeps them out of git and local )
- removing what they specified, deleting a sub-ticket, reordering the Backlog
- anything on the hands-off list
- decisions only they can make ( taste, legal, naming of a public thing ), but only where an assumption would be irreversible or expensive to undo; otherwise assume, record under **Assumptions** and keep going

## 3. The watcher

Wait with the **Monitor** tool, never by polling in a loop:

```
Monitor( command: "${CLAUDE_PLUGIN_ROOT}/scripts/watch.sh 31 32 33", description: "board + sessions", timeout_ms: 1800000 )
```

`watch.sh` prints one line per change: a ticket's column, assignees or labels changed, a session transcript appeared, went quiet ( no write for 5 minutes: finished or waiting for an answer ) or became active. Env: `INTERVAL` ( 30 s ), `QUIET` ( 300 s ). A card the owner moves ( back from In Review with a change request, or to Done ) shows up there; react to it. A Monitor expires after at most 30 minutes: re-arm it on the expiry notice.

## 4. Long sessions: limits, compaction, session end

- **Usage limits.** When the account's usage window is exhausted ( HTTP 429 ), builders stop where they are; their state is committed on their branch. Do not restart them: once the window has reset, send each a message ( SendMessage ) to continue. Deploy and merge what is finished before the window runs out.
- **Compaction.** The conversation may be summarised at any time. Keep nothing only in the chat: the queue memo, the tickets ( review comments, assumptions, merged lines ) and the branches hold the state. `ListAgents` returns the builders' handles afterwards. Compact between reviews, not in the middle of one.
- **Subagents end with the session.** Background subagents die when the session that started them ends. Work that must outlive it ( hours of builds, a night run ) goes into a **separate session** ( `claude -p "<prompt>"` in its worktree, under `caffeinate` ), with its transcript watched through `watch.sh`. Before ending, make sure nothing is left half-merged: every agent's work is committed and pushed, every card is in the right column, `caffeinate` is stopped, dev servers you started are stopped by PID.

## 5. Checklist per ticket

card in In Progress (Agent) -> branch + worktree + install + ports -> subagent with model and effort -> verify green -> assumptions read and surfaced -> merged tree verified -> merged and pushed in one chain -> deployed and read back ( if the repo deploys ) -> `merged` line + label -> review comment on the ticket -> In Review -> queue memo updated -> next ticket.
