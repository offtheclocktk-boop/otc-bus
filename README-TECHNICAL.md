# OTC Bus v1.2.6

Local pending-file + JSONL bus: **Grok Bot** queues jobs → **Grok Build CLI** runs them (dual token pool on one SuperGrok sub).

## Quick install (Windows)

```powershell
# from the unzipped folder
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Creates `C:\OffTheClock\bus` (and optional Grok CLI). Also mirrored under `%USERPROFILE%\OffTheClock\bus`.

## Layout

| Path | Role |
|------|------|
| `pending/{id}.json` | Queue (oldest first) |
| `failed/{id}.json` | Exhausted retries |
| `archive/inbox/` | Completed job specs |
| `archive/outbox/` | Per-id results |
| `inbox.jsonl` / `outbox.jsonl` | Compat append logs |
| `progress.json` | Live heartbeat |
| `state.json` | `idle` / `running` / `error` |
| `otc-enqueue.ps1` | Enqueue helper (exclusive `CreateNew`) |
| `otc-bridge.ps1` | Worker (`-MaxJobs` / `-Watch`) |
| `otc-wait.ps1` | Wait for result by id |
| `otc-status.ps1` | Compact status JSON |
| `otc-watch-install.ps1` | Scheduled Task `OTC-Bus-Watch` |

## Enqueue + run

```powershell
cd C:\OffTheClock\bus
.\otc-enqueue.ps1 -Id t050-demo -Kind investigate -Task 'Reply with exactly: hello' -Done 'notes say hello' -TimeoutSec 120 -MaxAttempts 2
.\otc-bridge.ps1
# or: .\otc-bridge.ps1 -Id t050-demo
# batch: .\otc-bridge.ps1 -MaxJobs 5
# unlimited drain: .\otc-bridge.ps1 -MaxJobs 0
# watch: .\otc-bridge.ps1 -Watch -PollSec 5 -MaxJobs 1
# wait for result: .\otc-wait.ps1 -Id t050-demo -TimeoutSec 600
# compact status: .\otc-status.ps1
# install logon watch (unlimited drain): .\otc-watch-install.ps1
# remove watch task: .\otc-watch-install.ps1 -Uninstall
# stuck lock: .\otc-bridge.ps1 -Force
# migrate old inbox.jsonl: .\otc-bridge.ps1 -Migrate
```

## What’s new in 1.2.3

- **Exclusive enqueue** — `pending/{id}.json` via `FileMode.CreateNew` (no Test-Path TOCTOU)
- **`otc-status.ps1`** — one-line JSON: status, pending/failed counts + ids, progress, watch task
- **`otc-watch-install.ps1`** — Scheduled Task `OTC-Bus-Watch` runs `-Watch -PollSec 5 -MaxJobs 0`; `-Uninstall` removes it
- **Acceptance** — `pathsExist` vs `strictPaths` spelled out (see below)
- BridgeVersion **1.2.3**

## What’s new in 1.2.1

- **`-MaxJobs`** — process N jobs per invocation (0 = unlimited); `-Id` still single-job
- **`-Watch` / `-PollSec`** — drain then poll until Ctrl+C; idle heartbeat + re-migrate each wake
- **`failed/`** — after `maxAttempts` soft fails, job leaves pending
- **`otc-wait.ps1`** — poll outbox/archive until result (exit 0/1/2)
- Enqueue sets `attempts=0` and optional `-MaxAttempts`

## What’s new in 1.2

- **pending/** queue (no full-inbox rescan for “last line”)
- **archive/** for completed jobs + results
- **Stale lock** auto-clear after ~20m (`-Force` anytime)
- **progress.json** heartbeat every ~15s while grok runs
- **Acceptance checks** (`accept.pathsExist`, `noBacktickIn`, `fileContains`, `strictPaths`)
- **Idempotent** success: already-ok outbox → archive + exit 0
- **otc-enqueue.ps1** helper
- Job `kind`: `implement` | `investigate` | `review`

## Acceptance: `pathsExist` vs `strictPaths`

Optional `job.accept`:

```json
{
  "pathsExist": ["C:\\path\\file.lua"],
  "noBacktickIn": ["C:\\path\\file.lua"],
  "fileContains": [{"path":"C:\\path\\file.lua","text":"1.1.0"}],
  "strictPaths": true
}
```

| Field | Meaning |
|-------|---------|
| `pathsExist` | Explicit required files. Missing → **hard fail** (`missing path: …`). When this field is present, the default existence check on job `paths[]` is skipped. |
| `strictPaths` | Only the default check of job `paths[]` (when `pathsExist` is absent). Default: missing `paths[]` entries are a **warning** (`path not found (warn)`) and do **not** fail the job. `strictPaths: true` promotes those warnings to hard fails. Does **not** change `pathsExist` (already hard). |
| `noBacktickIn` | Files that must not contain backtick (U+0060). Default: all `.lua` files listed in `paths`. |
| `fileContains` | Each `{path, text}` must exist and contain the substring. |

Default (no `accept`): warn if `paths` missing; fail on backticks in `.lua` paths.

Open-core / free. Monetize Grounded mods via Nexus DP + donations; optional paid Pro tooling later — not a paid raw JSONL bridge SKU.
