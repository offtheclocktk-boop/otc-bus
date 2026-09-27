# OTC Agent Coordination Kit

Version 2.0.0 · [Releases](https://github.com/offtheclocktk-boop/otc-agent-kit/releases) · MIT license

Two small, file-based tools for getting AI agents to hand work off reliably:

1. **OTC Bus** ([`bus/`](bus/)): a local job bus. An agent enqueues a job, a worker on your machine runs it with the Grok Build CLI, and the requester gets a DONE/FAIL event. The filesystem is the source of truth.
2. **Agent Inbox** ([`inbox/`](inbox/)): a cross-agent inbox on GitHub. Two agents on different platforms message each other through pull requests and issues in a shared private repository, woken by events instead of polling.

The bus hands work **to a worker on your machine**. The inbox hands work **between agents anywhere**. Use either on its own, or both together.

## How the two parts fit together

```
  Agent Inbox (private GitHub repo)
  +--------------------------------------------------------------+
  |  PR    "[for-agent-a] ..."  --- wakes instantly --->  Agent A  |  event-driven
  |  Issue "[for-agent-b] ..."  --- read at session --->  Agent B  |  session-driven
  +--------------------------------------------------------------+
                              |
                Agent A enqueues heavy work
                              v
  OTC Bus (your machine, PowerShell)
  pending/{id}.json --> otc-bridge.ps1 --> grok CLI
                              |
          outbox + events/terminal-{id}.json (DONE/FAIL)
                              |
          Agent A reports the result on the PR and merges it
```

A typical chain: Agent B opens a `[for-agent-a]` pull request. Agent A wakes, enqueues a bus job with `-NotifyAgentId`, and keeps its own context small while the worker does the heavy lifting. When the bus writes the terminal event, Agent A posts the result on the pull request and merges it, which archives the message.

## Part 1: OTC Bus (local job bus)

Keeps your main assistant responsive by moving long implement/investigate/review jobs to a local worker with its own token pool.

- Exclusive enqueue (`pending/{id}.json`, created atomically)
- Worker modes: single job, batch (`-MaxJobs`), or watch (`-Watch`), with an optional Windows Scheduled Task
- Acceptance checks: `pathsExist`, `fileContains`, `forbidContains`, `forbidRegex`, backtick guard
- Retries with `maxAttempts`, then `failed/`; STOP files that cannot be overridden
- Supersede guard, ASCII sanitizing of prompts, idempotent success handling
- Terminal events on every outcome, plus timing p50/p95 in `otc-status.ps1`

### Quick start (Windows PowerShell)

```powershell
git clone https://github.com/offtheclocktk-boop/otc-agent-kit.git
cd otc-agent-kit
powershell -NoProfile -ExecutionPolicy Bypass -File .\bus\install.ps1     # copies scripts to C:\OffTheClock\bus
cd C:\OffTheClock\bus
.\otc-enqueue.ps1 -Id demo-1 -Kind investigate -Task 'Reply with exactly: hello' -Done 'notes say hello'
.\otc-bridge.ps1 -WorkDir C:\path\to\your\project
.\otc-wait.ps1 -Id demo-1
.\otc-status.ps1
```

Full reference: [bus/README.md](bus/README.md). Spec: [bus/SPEC.md](bus/SPEC.md).

## Part 2: Agent Inbox (cross-agent GitHub inbox)

Lets two independent agents coordinate without sharing a platform. Each agent has a slug (for example `coordinator` and `builder`), a title tag `[for-<slug>]`, and a label `for-<slug>`.

- **To the event-driven agent:** open a PR that adds `messages/for-<slug>/YYYY-MM-DD-<topic>.md`. A PR-opened listener wakes it instantly. It replies in comments and merges when done.
- **To the session-driven agent:** open a labeled issue. It checks its issues at the start of every session, replies once, and closes with `done`.
- **Shared rules:** a message format (Need / Context / Paths / Done when), a `BOARD.md` ownership table, no secrets, no acknowledgment-only chatter, and a human owner who approves anything irreversible.

### Quick start

```bash
gh repo create <owner>/agent-inbox --private --clone
inbox/scripts/init-inbox.sh --dir ./agent-inbox --agent-a coordinator --agent-b builder --repo <owner>/agent-inbox
git -C agent-inbox add -A && git -C agent-inbox commit -m "Set up agent inbox" && git -C agent-inbox push
inbox/scripts/setup-labels.sh --repo <owner>/agent-inbox --agent-a coordinator --agent-b builder
```

Then wire each agent's wake-up and paste its rules file into its instructions: [inbox/CONNECT-YOUR-AGENTS.md](inbox/CONNECT-YOUR-AGENTS.md). PowerShell versions of both scripts are included. Full spec: [inbox/PROTOCOL.md](inbox/PROTOCOL.md).

## Requirements

| Part | Needs |
|---|---|
| OTC Bus | Windows with PowerShell 5.1+ (or PowerShell 7). The Grok Build CLI (`grok`) on `PATH`. The Scheduled Task helpers are Windows-only. |
| Agent Inbox | A GitHub account and a private repository, the GitHub CLI (`gh`) authenticated, bash 4+ or PowerShell 5.1+ for the scripts, and two agents that can use GitHub (native integration, MCP server, or `gh`). |

## Repository layout

```
.
├── README.md                 this file
├── LICENSE
├── CHANGELOG.md
├── bus/                      Part 1: OTC Bus (local job bus)
│   ├── README.md             usage, layout, acceptance checks
│   ├── SPEC.md               job and file specification
│   ├── DESIGN-NOTES.md       why some behavior is hard-coded
│   ├── install.ps1           copy scripts into an install folder
│   ├── otc-enqueue.ps1       enqueue a job
│   ├── otc-bridge.ps1        worker
│   ├── otc-wait.ps1          wait for a result
│   ├── otc-status.ps1        compact status JSON
│   ├── otc-events-tail.ps1   recent terminal events
│   ├── otc-notify-drain.ps1  events -> NOTIFY-LATEST.txt / webhook
│   ├── otc-notify-install.ps1  Scheduled Task for the drain
│   └── otc-watch-install.ps1   Scheduled Task for the worker
└── inbox/                    Part 2: Agent Inbox (cross-agent GitHub inbox)
    ├── README.md
    ├── PROTOCOL.md           the spec
    ├── CONNECT-YOUR-AGENTS.md  wiring the wake-ups
    ├── templates/            files for your inbox repo
    ├── scripts/              init-inbox and setup-labels (bash + PowerShell)
    └── examples/             sample messages
```

Runtime data created by the bus (`pending/`, `archive/`, `events/`, `logs/`, `state.json`, and so on) is ignored by `.gitignore` and should never be committed.

## Security

- Never commit tokens, API keys or passwords, and never put them in inbox messages. Keep webhook secrets in your platform's secret store or GitHub Actions secrets.
- Keep the inbox repository private and give each agent the least GitHub access that works.
- Inbox messages are requests between agents, not authorization. Publishing, deploying, deleting, spending and contacting people still need the human owner's approval.

## License

MIT. See [LICENSE](LICENSE).
