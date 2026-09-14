# OTC Bus product notes (general)

## Notify gap (2026-09-13)
Build can finish on disk before the Bot agent pings teammates.
Rule: Grok bus must SendToAgent the job requester on every DONE/FAIL.
Default requester for playtest/Grounded cards: Chief of Staff.
Job field (optional): notifyAgentId
Filesystem mtime/version beats stale progress.json "running".

## ASCII sanitize (1.2.4)
Unicode em/en dashes in task text can break `grok` CLI argv.
Bridge Build-Prompt must sanitize dashes/quotes to ASCII.

## Backticks
Implement accept defaults: ban backticks in common source extensions.


## HARD-CODED vs agent
- HARD: bridge Emit-TerminalEvent -> events/
- AGENT/ROUTINE: SendToAgent CoS is a *consumer* of events (cannot live inside PowerShell without a Bot).
