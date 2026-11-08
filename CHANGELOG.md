# Changelog

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
