# OTC Bus design notes

Short notes on why some behavior is hard-coded in the bridge instead of left to the agent.

## Notify gap
A worker can finish writing files to disk before the requesting agent notices. Relying on the agent to remember to check is unreliable.

- Rule: every terminal outcome (DONE or FAIL) must reach the agent that requested the job.
- Default requester: whoever enqueued the job. Set the optional job field `notifyAgentId` so routers know who to tell.
- File modification times and version strings on disk beat a stale `progress.json` that still says "running".

## Hard-coded vs agent responsibilities
- **Hard-coded (bridge):** `Emit-TerminalEvent` always writes `events/terminal.jsonl` and `events/terminal-{id}.json`.
- **Agent or routine:** actually messaging the requester is a *consumer* of those events. PowerShell alone cannot message an agent; a routine, `otc-notify-drain.ps1 -WebhookUrl`, or another integration does that.

## ASCII sanitize
Unicode em/en dashes and smart quotes in task text can break `grok` CLI argument parsing. Both `otc-enqueue.ps1` and the bridge's prompt builder normalize them to ASCII.

## Usage limits are final
A quota, usage-limit or HTTP 429 response means the provider is asking you to stop. Retrying cannot fix it and only adds load, so the bridge moves such jobs straight to `failed/` with a clear `lastError`. Other failures are retried after a short backoff.

## Approval mode
The bridge passes `--always-approve` by default so queued jobs can run unattended, as in earlier versions. For tighter control, set `-ApprovalArgs` or `OTC_GROK_APPROVAL_ARGS` to `--permission-mode dontAsk` with explicit `--allow` rules and/or a `--sandbox` profile.

## Backticks
Workers sometimes paste Markdown code fences into source files. Implement jobs fail acceptance by default if a listed source file contains a backtick.
