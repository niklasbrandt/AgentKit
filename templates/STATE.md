# STATE

The orchestrator's state sheet ( AgentKit ). Local to this machine, gitignored. Rewritten, not appended, at every hand-back, every spawn and every owner decision. `Last progress` is the time of the agent's last commit, note or message ( `board.sh stale` shows it per worktree ); the watchdog reads it every 30 minutes, and re-measures the capacity ( `capacity.sh` ) with it. A fresh session reads this first, then `board.sh state`.

## Running

Shift lead: <agent / none>

| Ticket | Title | Agent / model / effort | Worktree | Ports | Started | Last progress | Phase |
|---|---|---|---|---|---|---|---|

## Waiting

- <ticket> → <waits for what, since when>

## Queue

1. <ticket ( title )> — <reason if blocked>

## Owner decisions open

- <decision> — recommendation: <…>

## Limits

- Capacity ( last measured ): <time> agents <n>, headless <n> ( free <n> ); owner <active / idle Nm / afk>; <the reasons, from `capacity.sh`>
- Owner override: <none / "machine slow" since <time>: recommendation halved>
- Builders: at most the measured `agents` ( max `agentsMax` ), checked before every spawn
- Headless browsers: at most the measured `headless` ( max `headlessMax` ), machine-wide; no new run while the 1-minute load is above the core count
- Ports: <ticket → port>
- Locked files: <file → ticket>
- Owner's ports, never touched: <…>

## Last hand-backs

<!-- Deployed entry file: written by the orchestrator after the batch deploy, never by a builder. -->

| Ticket | Sha | Deployed entry | Date |
|---|---|---|---|

## Notes

- <date>: <self-set rule or incident>
