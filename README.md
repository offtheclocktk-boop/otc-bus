# OTC Bus

**Local job bus that doubles your AI coding throughput.**

OTC Bus queues work for the **Grok Build CLI** on a separate token pool while your main assistant stays thin and responsive. Same subscription family, two lanes of work: chat stays fast; heavy implement/investigate jobs run Off-The-Clock.

## Why it exists

AI assistants burn the same token budget whether they are answering "what key do I press?" or rewriting a 600-line Unreal Lua mod. OTC Bus splits that:

- **Enqueue** a job from your assistant / scripts
- **Bridge** runs `grok` against a pending queue
- **Outbox + events** report DONE/FAIL with timing
- Your main chat does install, playtest, and decisions - not hour-long silent rebuilds

Built for Windows first (PowerShell), designed to be boring, reliable infrastructure.

## Features (v1.2.6)

- Exclusive enqueue (`pending/{id}.json`, no racey Test-Path)
- Watch mode + optional Scheduled Task
- Acceptance checks: `pathsExist`, `fileContains`, `forbidContains`, `forbidRegex`, backtick guards
- STOP files that Force cannot revive
- Supersede guard (no accidental re-runs of finished jobs)
- ASCII sanitize before CLI argv
- Terminal events + timing p50/p95 in status
- Idempotent success handling

## Quick start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
cd C:\OffTheClock\bus
.\otc-enqueue.ps1 -Id demo-1 -Kind investigate -Task 'Reply with exactly: hello' -Done 'notes say hello'
.\otc-bridge.ps1
.\otc-status.ps1
```

## Who this is for

- Indie / solo builders using Grok Bot + Grok Build
- Anyone who wants **reproducible, file-based** job queues instead of vibes
- Modders shipping Nexus packs while keeping the assistant responsive

## License

Open / free to use. See repo files for details.