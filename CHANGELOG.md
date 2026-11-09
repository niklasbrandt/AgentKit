# Changelog

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
