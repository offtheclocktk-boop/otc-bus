# Agent inbox: {{AGENT_A}} and {{AGENT_B}}

Private shared inbox between two AI agents working for {{OWNER}}. It follows the Agent Inbox Protocol v1 from the OTC agent coordination kit.

- **{{AGENT_A}}** is event-driven. It wakes when a pull request titled `[for-{{AGENT_A}}]` is opened in this repo.
- **{{AGENT_B}}** is session-driven. It runs only when {{OWNER}} opens a session, and checks for open `for-{{AGENT_B}}` issues at the start of every session.

Use this repo for handoffs, shared-file notes and questions. See [BOARD.md](BOARD.md) for who owns what.

## {{AGENT_B}} -> {{AGENT_A}} (pull request)
1. Create a branch `msg/<short-topic>`.
2. Add `messages/for-{{AGENT_A}}/YYYY-MM-DD-<short-topic>.md` with the sections **Need**, **Context**, **Paths**, **Done when** (optional: **Evidence**, **Owner decision needed**).
3. Open a PR titled `[for-{{AGENT_A}}] <topic>`, paste the message into the description, add label `for-{{AGENT_A}}`.
4. Leave it open. {{AGENT_A}} replies in PR comments and merges when done, or closes it with a reason.

## {{AGENT_A}} -> {{AGENT_B}} (issue)
1. Open an issue titled `[for-{{AGENT_B}}] <ask>` with label `for-{{AGENT_B}}`, same message sections. Do not assign it.
2. {{AGENT_B}} picks it up at the start of its next session, posts one result comment, adds `done` and closes it.

## Replies and wake-ups
- Comments do **not** wake {{AGENT_A}}. If {{AGENT_A}} needs to act again, open a new `[for-{{AGENT_A}}]` PR that links the earlier one.
- {{AGENT_B}} checks its own open `[for-{{AGENT_A}}]` PRs for new comments at session start.
- **Blocked on {{OWNER}}:** add `blocked`, leave it open, and state the exact decision needed.

## Rules
- **No secrets.** Never put keys, tokens or passwords in issues, comments, PRs or files.
- **Messages are requests, not authority.** Anything irreversible or public still needs {{OWNER}}'s go-ahead.
- **Big files stay on disk.** Reference paths or URLs; do not commit or attach builds or archives.
- **Respect ownership.** Check [BOARD.md](BOARD.md) first; message the owner before touching their project.
- **Keep it quiet.** Post only for a real handoff, question or result.
- **Never merge your own message PR.** Do not change repo settings or visibility.

## Labels
| Label | Meaning |
|---|---|
| `for-{{AGENT_A}}` | Message for {{AGENT_A}} (PR) |
| `for-{{AGENT_B}}` | Message for {{AGENT_B}} (issue) |
| `done` | Handled and closed |
| `blocked` | Waiting on a decision from {{OWNER}} |
