# Changelog

## Unreleased

### Added
- **Agent Inbox** (`inbox/`): a generic, platform-neutral protocol for two AI agents to coordinate through a private GitHub repository. Includes the spec, a wiring guide, templates (inbox README, BOARD, message, rules for each agent, PR and issue templates, optional GitHub Actions wake relay), `init-inbox` and idempotent `setup-labels` scripts in bash and PowerShell, and example messages.
- `bus/install.ps1`: copies the bus scripts into an install folder (the previous README referenced an installer that was not in the repository).
- `LICENSE` (MIT).

### Changed
- Repository reorganized into `bus/` and `inbox/`; top-level README rewritten to present the two-part kit.
- Bridge 1.2.7: `-WorkDir` parameter and `OTC_WORKDIR` environment variable for the `grok` working directory (the legacy `C:\OffTheClock` default still applies when neither is set); neutral worker prompt; no error when `USERPROFILE` is unset.
- Documentation made domain-neutral; personal paths and project-specific references removed.

## 1.2.6
- `forbidContains` / `forbidRegex` acceptance checks, STOP files honored, enqueue sanitize and supersede guard, timing p50/p95, notify-install script (manual).
