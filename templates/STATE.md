# STATE

The orchestrator's state sheet ( AgentKit ). Local to this machine, gitignored. Rewritten, not appended, at every hand-back, every spawn and every owner decision. A fresh session reads this first, then `board.sh state`.

## Running

Shift lead: <agent / none>

| Ticket | Title | Agent / model | Worktree | Ports | Started | Phase |
|---|---|---|---|---|---|---|

## Waiting

- <ticket> → <waits for what>

## Queue

1. <ticket ( title )> — <reason if blocked>

## Owner decisions open

- <decision> — recommendation: <…>

## Limits

- Builders: <cap> at once
- Headless browsers: <headlessCap> at once, machine-wide; no new run while the 1-minute load is above the core count
- Ports: <ticket → port>
- Locked files: <file → ticket>
- Owner's ports, never touched: <…>

## Last hand-backs

| Ticket | Sha | Deployed entry | Date |
|---|---|---|---|

## Notes

- <date>: <self-set rule or incident>
