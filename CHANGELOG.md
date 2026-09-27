# Changelog

## 2.0.0 — 2026-09-27

The repository is now the **OTC Agent Coordination Kit** (renamed from `otc-bus` to `otc-agent-kit`): the OTC Bus local job bus plus the new Agent Inbox.

### Breaking
- Bus scripts moved from the repository root into `bus/`. Update any scripts, links or install steps that referenced the old root paths. Installed copies (for example `C:\OffTheClock\bus`) are not affected until you reinstall.

### Added
- **Agent Inbox** (`inbox/`): a generic, platform-neutral protocol for two AI agents to coordinate through a private GitHub repository. Includes the spec, a wiring guide, templates (inbox README, BOARD, message, rules for each agent, PR and issue templates), `init-inbox` and idempotent `setup-labels` scripts in bash and PowerShell, and example messages.
- **Use within each provider's terms** section in the README (with pointers from the inbox protocol and the bus README): one account per person, own sign-in, within plan limits; no pooling or rotating of accounts, keys or subscriptions.
- Bridge: `grok` approval flags are configurable with `-ApprovalArgs` or `OTC_GROK_APPROVAL_ARGS`. The default stays `--always-approve`; `--permission-mode dontAsk` with allow rules, or a `--sandbox` profile, is documented as recommended.
- Bridge: jobs whose `grok` output shows a quota, usage-limit, rate-limit or HTTP 429 error are not retried; they move straight to `failed/` with a clear `lastError`. Other retries now wait for a short backoff (30 s per attempt, capped at 5 minutes).
- `bus/tests/e2e.ps1`: end-to-end test with a stand-in `grok`, including the no-retry-on-429 case.
- `bus/install.ps1`: copies the bus scripts into an install folder (the previous README referenced an installer that was not in the repository).
- `LICENSE` (MIT).

### Changed
- Repository reorganized into `bus/` and `inbox/`; top-level README rewritten to present the two-part kit.
- Bridge 2.0.0: `-WorkDir` parameter and `OTC_WORKDIR` environment variable for the `grok` working directory (the legacy `C:\OffTheClock` default still applies when neither is set); neutral worker prompt; no error when `USERPROFILE` is unset.
- Documentation made domain-neutral; personal paths and project-specific references removed.
- Documented that idle watch mode is a local file check that uses no tokens, and that the worker only runs jobs the user queued.

## 1.2.6
- `forbidContains` / `forbidRegex` acceptance checks, STOP files honored, enqueue sanitize and supersede guard, timing p50/p95, notify-install script (manual).
