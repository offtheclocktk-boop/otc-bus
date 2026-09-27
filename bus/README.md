# OTC Bus (local job bus)

A local, file-based job queue. An agent or script enqueues a job, a worker on your machine runs it with the **Grok Build CLI** (`grok`), and the result is written to an outbox plus a terminal DONE/FAIL event. The filesystem (`pending/`, `archive/`, `events/`) is the source of truth, so every job is inspectable and reproducible.

Current version: **2.0.0** (part of the [OTC Agent Coordination Kit](https://github.com/offtheclocktk-boop/otc-agent-kit)). Windows-first (PowerShell 5.1+). Scheduled Task helpers are Windows-only.

See [SPEC.md](SPEC.md) for the formal job and file specification and [DESIGN-NOTES.md](DESIGN-NOTES.md) for the reasoning behind some of the hard-coded behavior.

## Install (Windows)

```powershell
# from a clone of this repository
powershell -NoProfile -ExecutionPolicy Bypass -File .\bus\install.ps1
# or choose the destination explicitly
powershell -NoProfile -ExecutionPolicy Bypass -File .\bus\install.ps1 -Destination D:\OffTheClock\bus
```

`install.ps1` copies the `otc-*.ps1` scripts into the destination folder (default `C:\OffTheClock\bus`). Runtime folders are created on first run. It does not install the `grok` CLI; install that separately and make sure `grok` is on `PATH` (or set `cli` in `state.json` to its full path).

## Layout (runtime)

| Path | Role |
|------|------|
| `pending/{id}.json` | Queue (oldest first) |
| `failed/{id}.json` | Exhausted retries |
| `failed/{id}.STOP.txt` | Kill switch: the job is never run or re-enqueued |
| `archive/inbox/` | Completed job specs |
| `archive/outbox/` | Per-id results |
| `events/terminal.jsonl`, `events/terminal-{id}.json` | Terminal DONE/FAIL events |
| `events/timing.jsonl` | Per-job duration (feeds p50/p95 in status) |
| `inbox.jsonl` / `outbox.jsonl` | Compatibility append logs |
| `progress.json` | Live heartbeat |
| `state.json` | `idle` / `running` / `error` |
| `logs/bridge.log` | Worker log |

## Scripts

| Script | Role |
|------|------|
| `otc-enqueue.ps1` | Enqueue helper (exclusive `CreateNew`, ASCII sanitize, supersede guard) |
| `otc-bridge.ps1` | Worker (`-Id`, `-MaxJobs`, `-Watch`, `-WorkDir`) |
| `otc-wait.ps1` | Wait for a result by id (exit 0 ok / 1 fail / 2 timeout) |
| `otc-status.ps1` | Compact status JSON including timing p50/p95 |
| `otc-events-tail.ps1` | Print recent terminal events |
| `otc-notify-drain.ps1` | Turn terminal events into `NOTIFY-LATEST.txt` and an optional webhook POST |
| `otc-watch-install.ps1` | Scheduled Task `OTC-Bus-Watch` (worker in watch mode at logon) |
| `otc-notify-install.ps1` | Scheduled Task `OTC-Bus-Notify-Drain` |
| `install.ps1` | Copy the scripts into an install folder |

## Enqueue and run

```powershell
cd C:\OffTheClock\bus
.\otc-enqueue.ps1 -Id t050-demo -Kind investigate -Task 'Reply with exactly: hello' -Done 'notes say hello' -TimeoutSec 120 -MaxAttempts 2
.\otc-bridge.ps1
# specific job:           .\otc-bridge.ps1 -Id t050-demo
# batch:                  .\otc-bridge.ps1 -MaxJobs 5
# unlimited drain:        .\otc-bridge.ps1 -MaxJobs 0
# watch:                  .\otc-bridge.ps1 -Watch -PollSec 5 -MaxJobs 1
# wait for result:        .\otc-wait.ps1 -Id t050-demo -TimeoutSec 600
# compact status:         .\otc-status.ps1
# install logon watch:    .\otc-watch-install.ps1
# remove watch task:      .\otc-watch-install.ps1 -Uninstall
# stuck lock:             .\otc-bridge.ps1 -Force
# migrate old inbox.jsonl: .\otc-bridge.ps1 -Migrate
```

### Working directory

`grok` runs in the first of these that exists:

1. `-WorkDir <path>` passed to `otc-bridge.ps1`
2. the `OTC_WORKDIR` environment variable
3. `C:\OffTheClock` (legacy default)
4. the bus folder itself

Point it at the root of the project(s) your jobs work on.

### Notifying the requester

Pass `-NotifyAgentId <id>` when enqueuing. The id is copied onto the terminal event so a router (your assistant's routine, `otc-notify-drain.ps1 -WebhookUrl ...`, or anything that reads `events/`) can tell the right agent that the job finished. The bus itself never sends messages; it only writes events.

## Acceptance checks

Optional `job.accept` (pass as `-AcceptJson`):

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

| Field | Meaning |
|-------|---------|
| `pathsExist` | Explicit required files. Missing means **hard fail** (`missing path: ...`). When present, the default existence check on job `paths[]` is skipped. |
| `strictPaths` | Applies only to the default check of job `paths[]` (when `pathsExist` is absent). By default, missing `paths[]` entries are a warning and do not fail the job. `strictPaths: true` makes them hard fails. |
| `noBacktickIn` | Files that must not contain a backtick (U+0060). Default: every source file in `paths` with one of these extensions: `.lua .ps1 .py .js .ts .tsx .jsx .cs .cpp .h .java .go .rs`. Catches pasted Markdown fences. |
| `fileContains` | Each `{path, text}` must exist and contain the substring. |
| `forbidContains` | Each `{path, text}` must not contain the substring (skipped if the file is missing). |
| `forbidRegex` | Each `{path, pattern}` must not match the regex (skipped if the file is missing). |

Default (no `accept`): warn if `paths` are missing; fail on backticks in source files listed in `paths`.

## History

- **2.0.0**: scripts moved into `bus/` inside the kit repository (breaking path change); `-WorkDir` / `OTC_WORKDIR`, neutral worker prompt, `install.ps1`, guard for missing `USERPROFILE`.
- **1.2.6**: `forbidContains` / `forbidRegex`, STOP files honored, enqueue sanitize and supersede guard, timing p50/p95, notify-install script.
- **1.2.3**: exclusive enqueue via `FileMode.CreateNew`, `otc-status.ps1`, `otc-watch-install.ps1`, `pathsExist` vs `strictPaths` clarified.
- **1.2.1**: `-MaxJobs`, `-Watch` / `-PollSec`, `failed/` after `maxAttempts`, `otc-wait.ps1`.
- **1.2**: `pending/` queue, `archive/`, stale lock auto-clear (~20 min), `progress.json` heartbeat, acceptance checks, idempotent success, job `kind` (`implement` | `investigate` | `review`).
