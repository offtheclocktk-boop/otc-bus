# OTC Bus Spec (bridge 2.0.0)

## Goals
Local JSONL/pending-file bus so an assistant agent (or any script) can queue work for the Grok Build CLI on your own PC. The assistant stays responsive while longer jobs run in a local worker. Each agent runs under its own product sign-in and uses that product's own plan limits. The kit never switches, pools or rotates accounts, API keys or subscriptions.

## Layout
```
bus/
  otc-bridge.ps1      # worker (MaxJobs / Watch / single Id)
  otc-enqueue.ps1     # enqueue into pending/
  otc-wait.ps1        # poll outbox until result or timeout
  pending/{id}.json   # queued jobs (oldest first)
  failed/{id}.json    # exhausted maxAttempts
  archive/inbox/      # completed job specs
  archive/outbox/     # per-id results
  inbox.jsonl         # compatibility append log (migrated into pending/)
  outbox.jsonl        # compatibility result log
  progress.json       # live heartbeat for current job
  state.json          # idle|running|error + lastId/lastError
  logs/bridge.log
```

## Bridge flags
- `-Id <id>` process specific pending job (ignores `-MaxJobs`)
- `-Force` break running lock once at start of run
- `-Migrate` migrate inbox.jsonl → pending/ and compact
- `-MaxJobs <n>` process up to N pending jobs per cycle (FIFO). Default 1. `0` = unlimited
- `-Watch` after draining, poll pending every `-PollSec` until Ctrl+C / kill
- `-PollSec <n>` watch idle interval (default 5, min 2). Re-migrates inbox each wake
- `-ApprovalArgs <args[]>` grok permission flags placed before `-p` (else `$env:OTC_GROK_APPROVAL_ARGS` as a JSON array or space-separated string, else `--always-approve`)
- `-WorkDir <path>` working directory for `grok` (else `$env:OTC_WORKDIR`, else `C:\OffTheClock` if present, else the bus folder)

## Retries / failed/
On soft fail (`ok=false`): increment `attempts` on pending JSON and set `retryAfter` (UTC) to now + 30 s x attempts, capped at 300 s. Jobs whose `retryAfter` is in the future are skipped by drain cycles (an explicit `-Id` still runs them). When `attempts >= maxAttempts` (job field, default 2), move to `failed/{id}.json`. Successful jobs still archive to `archive/inbox/`.

**No retry on usage limits.** If `grok` failed (non-zero exit or empty output) and its output matches a quota, usage-limit, rate-limit or HTTP 429 message, the job moves straight to `failed/` after that single attempt, and `state.lastError` starts with `usage/rate limit (quota or HTTP 429) - not retried:`.

## Stale lock
If `state.status=running` and `updatedAt` older than 20 minutes, lock is treated as stale (or use `-Force`). Busy lock is checked only at start of a run (not between jobs in a multi-job cycle).

## Watch mode cost
Watch mode is a local file check: every `-PollSec` seconds it lists `pending/`. No model is called while idle, so idle watching uses no tokens. The worker only runs jobs that were queued into `pending/` by the user or by an agent acting for the user.

## Heartbeat
While grok runs, bridge refreshes `progress.json` and `state.updatedAt` about every 15s.

## Acceptance
Optional job.accept:
```json
{
  "pathsExist": ["C:\\work\\app\\src\\main.py"],
  "noBacktickIn": ["C:\\work\\app\\src\\main.py"],
  "fileContains": [{"path":"C:\\work\\app\\src\\version.py","text":"1.1.0"}],
  "forbidContains": [{"path":"C:\\work\\app\\src\\main.py","text":"TODO"}],
  "forbidRegex": [{"path":"C:\\work\\app\\src\\main.py","pattern":"print\\("}],
  "strictPaths": true
}
```
Default: warn if `paths` missing; fail on backticks in source files listed in `paths` (`.lua .ps1 .py .js .ts .tsx .jsx .cs .cpp .h .java .go .rs`).

## Job fields
`id`, `task`, `paths[]`, `done`, `timeoutSec`, `kind` (`implement`|`investigate`|`review`), `accept`, `attempts` (default 0), `maxAttempts` (default 2), `notifyAgentId` (optional)

## Wait helper
`otc-wait.ps1 -Id <id> [-TimeoutSec 600] [-PollSec 2]`: exit 0 if `ok=true`, 1 if `ok=false`, 2 on timeout. Prints result JSON to stdout.

## STOP files
If `failed/{id}.STOP.txt` exists, the bridge archives the pending job without running it and emits a failed terminal event (`STOP: <reason>`). `otc-enqueue.ps1` refuses to enqueue that id. `-Force` does not override a STOP file.

## Idempotency
If outbox already has `ok=true` for id, bridge archives pending and exits 0 without re-calling grok.

## Terminal notify invariant (v1.2.5+, HARD-CODED)

On every terminal job outcome (success, exhausted fail, idempotent success), `otc-bridge.ps1` **always** writes:
- `events/terminal.jsonl` (append)
- `events/terminal-{id}.json` (latest per id)

This is bridge code, not an agent reminder. Consumers (an assistant routine, `otc-notify-drain.ps1`, external tools) read those files. Optional job field `notifyAgentId` is recorded on the event for routers.
