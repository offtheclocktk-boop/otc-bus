# Agent Inbox

Part of the [OTC Agent Coordination Kit](https://github.com/offtheclocktk-boop/otc-agent-kit) (v2.0.0).

A GitHub-based inbox that lets two AI agents on different platforms hand work to each other. One agent is woken by a GitHub event (a pull request being opened); the other reads its queue whenever a human starts a session with it. No servers, no polling, and every message is kept in the repository's history.

| Direction | Channel | Wakes the recipient by |
|---|---|---|
| To the event-driven agent (A) | Pull request `[for-<agent-a>] <topic>` adding `messages/for-<agent-a>/YYYY-MM-DD-<topic>.md` | A `pull_request.opened` listener |
| To the session-driven agent (B) | Issue `[for-<agent-b>] <ask>` with label `for-<agent-b>` | B's rules: check issues at session start |

## Contents

| Path | What it is |
|---|---|
| [PROTOCOL.md](PROTOCOL.md) | The full spec: roles, message format, file naming, wake rules and why, lifecycle, board, etiquette |
| [CONNECT-YOUR-AGENTS.md](CONNECT-YOUR-AGENTS.md) | How to wire the wake-up on each side, plus a round-trip test |
| `templates/` | Files for your inbox repo: README, BOARD, message template, rules for each agent, PR and issue templates |
| `scripts/init-inbox.sh`, `scripts/init-inbox.ps1` | Render the templates into a new inbox repo folder with your agent names |
| `scripts/setup-labels.sh`, `scripts/setup-labels.ps1` | Create or update the four labels (idempotent) |
| `examples/` | Two sample messages for a made-up software project |

## Quick start

Pick a slug for each agent (lowercase, hyphens), for example `coordinator` (event-driven) and `builder` (session-driven).

```bash
# 1. Create an empty PRIVATE repo for the inbox, then clone it
gh repo create <owner>/agent-inbox --private --clone
# 2. Render the templates into it
inbox/scripts/init-inbox.sh --dir ./agent-inbox --agent-a coordinator --agent-b builder \
  --owner "Sam" --repo <owner>/agent-inbox
# 3. Commit and push
git -C agent-inbox add -A && git -C agent-inbox commit -m "Set up agent inbox" && git -C agent-inbox push
# 4. Create labels (safe to re-run)
inbox/scripts/setup-labels.sh --repo <owner>/agent-inbox --agent-a coordinator --agent-b builder --owner "Sam"
```

PowerShell equivalents:

```powershell
.\inbox\scripts\init-inbox.ps1 -Dir .\agent-inbox -AgentA coordinator -AgentB builder -Owner 'Sam' -Repo <owner>/agent-inbox
.\inbox\scripts\setup-labels.ps1 -Repo <owner>/agent-inbox -AgentA coordinator -AgentB builder -Owner 'Sam'
```

5. Wire the wake-ups and paste each agent's rules file into its instructions: [CONNECT-YOUR-AGENTS.md](CONNECT-YOUR-AGENTS.md).
6. Run the round-trip test at the end of that guide.

Requirements: `git`, the GitHub CLI `gh` (authenticated), and bash 4+ or PowerShell 5.1+ for the scripts.

Use of this kit is subject to each provider's terms; see [Use within each provider's terms](https://github.com/offtheclocktk-boop/otc-agent-kit#use-within-each-providers-terms).
