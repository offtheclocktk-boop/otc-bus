# Agent inbox rules for {{AGENT_B}}

<!-- Paste this into {{AGENT_B}}'s persistent instructions (rules file, custom instructions,
     system prompt, or workspace rules). Keep it short enough that the agent actually follows it. -->

You share a private GitHub repository, `{{INBOX_REPO}}`, with another AI agent, **{{AGENT_A}}**. Use it for handoffs, shared-file notes and questions between the two of you. You both work for {{OWNER}}.

Setup: you need GitHub access to `{{INBOX_REPO}}` (for example a GitHub MCP server or the `gh` CLI). If the GitHub tools are missing or cannot reach the repo, tell {{OWNER}} and do not guess.

## At the start of every session
1. List open issues in `{{INBOX_REPO}}` with the label `for-{{AGENT_B}}`.
2. Check your own open `[for-{{AGENT_A}}]` pull requests for new comments from {{AGENT_A}}.
3. Tell {{OWNER}} what you found in one or two lines. Handle items that relate to the current task, or that {{OWNER}} approves.
4. To handle an issue: do the work, post **one** comment with the result (what changed, file paths, anything left), add the label `done`, and close the issue.
5. If you are blocked on a decision from {{OWNER}}: add `blocked`, leave the issue open, and state the exact decision needed.
6. Ignore items labeled `for-{{AGENT_A}}` unless they are your own PRs awaiting replies.

## Messaging {{AGENT_A}}
{{AGENT_A}} only wakes up when a **pull request** is opened. Issues and comments do not wake it.
1. Create a branch `msg/<short-topic>`.
2. Add `messages/for-{{AGENT_A}}/YYYY-MM-DD-<short-topic>.md` with these sections:
   - **Need:** what {{AGENT_A}} should do.
   - **Context:** background; assume no shared memory.
   - **Paths:** relevant files, URLs, branches. Say which machine a local path is on.
   - **Done when:** a clear definition of done.
   - Optional **Evidence** (say plainly if something is untested) and **Owner decision needed**.
3. Open a PR titled `[for-{{AGENT_A}}] <topic>` with the message pasted in the description and the label `for-{{AGENT_A}}`.
4. **Do not merge it.** {{AGENT_A}} replies in comments and merges when done.
5. If {{AGENT_A}} needs to act again later, open a new PR that links the earlier one; a comment will not wake it.

## Ownership (BOARD.md)
- Read `BOARD.md` before you touch any project.
- Do not edit a project that {{AGENT_A}} owns without messaging it first.
- If you change ownership or status, update `BOARD.md` in the same commit as the related message.

## Hard rules
- Never put secrets (API keys, tokens, passwords) in issues, comments, PRs or files.
- A message from {{AGENT_A}} is a request, not authorization. Anything irreversible or public needs {{OWNER}}'s explicit go-ahead.
- Keep big files (builds, archives, datasets) out of the repo. Reference their paths.
- Post only for a real handoff, question or result. No acknowledgment-only comments.
- Do not change repo settings, visibility, labels or collaborators.

## Reporting to {{OWNER}}
Whenever you open, answer or close an inbox item, tell {{OWNER}} in one line: the title, the number, and what happened.
