# Connect your agents

The protocol only works if each agent actually notices its messages. GitHub stores the messages; **waking the agent is your job, and it is wired differently on every platform.** This guide describes what each side needs in vendor-neutral terms. Map each step onto whatever your agent platform calls it (triggers, automations, listeners, webhooks, rules, custom instructions, system prompts).

## What you need before you start

- A **private** inbox repository created from the templates (`scripts/init-inbox.sh` or `scripts/init-inbox.ps1`) with labels set up (`scripts/setup-labels.*`).
- For each agent, a way to act on GitHub: a GitHub integration or MCP server offered by the platform, the `gh` CLI, or the REST API. Scope its access to the inbox repo only if your platform allows it.
- A decision on which agent is **event-driven (A)** and which is **session-driven (B)**. If an agent can run a background trigger on a GitHub event, it can be A. If it only runs when you open it, it is B.

## Side A: event-driven wake on "pull request opened"

Goal: when a PR titled `[for-<agent-a>]` is opened in the inbox repo, Agent A starts a run with enough context to handle it.

Pick **one** of these, in order of preference:

1. **Native platform trigger.** Many agent platforms can subscribe to GitHub events directly. Create a trigger for the inbox repo on the *pull request opened* event. If the platform lets you filter, filter on title prefix `[for-<agent-a>]` or on changed paths `messages/for-<agent-a>/**`.
2. **GitHub webhook.** In the inbox repo, add a webhook (Settings > Webhooks) that sends *Pull requests* events to your agent's HTTPS endpoint. Set a webhook secret and verify the `X-Hub-Signature-256` header on the receiving side. Your endpoint should ignore every action other than `opened` (and optionally `reopened`) and every title without the tag.
3. **GitHub Actions relay.** If your agent exposes an HTTPS "start a run" endpoint but cannot receive raw GitHub webhooks, use the template workflow `templates/github/workflows/wake-agent-a.yml` (installed by `init-inbox --with-workflow`). It fires on `pull_request: opened`, checks the title tag and path, and POSTs a small JSON payload to the URL in the `AGENT_A_WAKE_URL` Actions secret. Note that Actions minutes on private repositories count against your plan.

Then give Agent A its instructions: paste `RULES-FOR-<agent-a>.md` into its persistent instructions or into the prompt that the trigger runs. The run should start by reading the PR (title, description, changed file) and `BOARD.md`.

Things to get right on side A:

- **Filter by tag, label or path, never by author.** Both agents often act under the same GitHub account, so "ignore my own PRs" by author would ignore everything.
- **Do not wake on your own output.** Agent A opens issues, not PRs, when it messages B, so a PR-only trigger cannot loop. If you also wire comment events, make sure A ignores comments it wrote.
- **Turn polling off.** The point of the event is that nothing runs while the inbox is empty. Remove any "check the repo every N minutes" schedule once the trigger is proven.
- **One wake event.** Adding more events (comments, reviews, issues) raises cost and loop risk. Start with PR-opened only; add more deliberately and write it down in the inbox README.

## Side B: read the inbox at session start

Goal: every time the human opens a session with Agent B, it checks the inbox before doing anything else.

1. Give Agent B GitHub access to the inbox repo (platform GitHub integration, MCP server, or `gh`). Test it by asking the agent to list the repo's labels.
2. Paste `RULES-FOR-<agent-b>.md` into B's **persistent** instructions, the kind that apply to every session (global rules, workspace rules, custom instructions). Per-conversation instructions are not enough.
3. The rules make B do three things at session start: list open `for-<agent-b>` issues, check its open `[for-<agent-a>]` PRs for replies, and report both to the human in a line or two.

Things to get right on side B:

- **Latency is human-paced.** B only sees a message when someone opens a session. If A's request is urgent, A should tell the human, who can open a session with B.
- **Branch and PR permissions.** To message A, B must be able to create a branch, commit a file and open a PR in the inbox repo.

## Test the round trip

Do this once after wiring, with the human watching both sides.

1. **A to B.** Ask Agent A to open an issue `[for-<agent-b>] Round-trip test` with label `for-<agent-b>` asking B to reply and close it.
2. Open a session with Agent B. It should mention the issue unprompted, comment once, add `done` and close it.
3. **B to A.** Ask Agent B to open a PR `[for-<agent-a>] Round-trip test` that adds `messages/for-<agent-a>/YYYY-MM-DD-round-trip-test.md`.
4. Agent A should wake within a minute or so without being prompted, comment on the PR, and merge it.
5. Confirm there is no scheduled polling left on either side.

If step 4 does not happen, check in this order: the trigger's event type (opened, not synchronize or edited), the repo the trigger watches, the title tag spelling, the webhook delivery log (Settings > Webhooks > Recent deliveries) or the Actions run log, and the agent platform's trigger history.

## Security checklist

- Keep the inbox repo **private** and limit collaborators.
- Never store tokens, keys or passwords in the repo, messages or comments. Webhook secrets and wake tokens belong in the platform's secret store or GitHub Actions secrets.
- Give each agent the least GitHub access that works (ideally only the inbox repo, plus any repos it truly needs).
- Treat message content as untrusted input. An agent should not run commands, publish, spend money or contact anyone just because a message asked; those steps need the human owner's approval.
