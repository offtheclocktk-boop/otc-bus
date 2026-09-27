#!/usr/bin/env bash
# Create or update the Agent Inbox labels in a GitHub repository.
# Idempotent: existing labels are updated in place (gh label create --force).
#
# Usage:
#   ./setup-labels.sh --repo OWNER/REPO --agent-a coordinator --agent-b builder [--owner "the owner"] [--dry-run]
#
# Environment defaults: INBOX_REPO, AGENT_A, AGENT_B, INBOX_OWNER.
# Requires: gh (authenticated with access to the repo).
set -euo pipefail

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

repo="${INBOX_REPO:-}"
agent_a="${AGENT_A:-}"
agent_b="${AGENT_B:-}"
owner="${INBOX_OWNER:-the owner}"
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --agent-a) agent_a="${2:-}"; shift 2 ;;
    --agent-b) agent_b="${2:-}"; shift 2 ;;
    --owner) owner="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

slug_re='^[a-z0-9][a-z0-9-]{0,39}$'
for pair in "agent-a:$agent_a" "agent-b:$agent_b"; do
  name="${pair%%:*}"; value="${pair#*:}"
  if [ -z "$value" ]; then echo "missing --$name" >&2; exit 2; fi
  if ! [[ "$value" =~ $slug_re ]]; then
    echo "invalid --$name '$value' (use lowercase letters, digits, hyphens)" >&2; exit 2
  fi
done
if [ "$agent_a" = "$agent_b" ]; then echo "--agent-a and --agent-b must differ" >&2; exit 2; fi

if ! command -v gh >/dev/null 2>&1; then echo "gh CLI not found: https://cli.github.com/" >&2; exit 1; fi

if [ "$dry_run" -eq 0 ]; then
  if ! gh auth status >/dev/null 2>&1; then echo "gh is not authenticated (run: gh auth login)" >&2; exit 1; fi
  if [ -z "$repo" ]; then
    repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  fi
fi
if [ -z "$repo" ]; then repo="OWNER/REPO"; fi

# name|color|description
labels=(
  "for-${agent_a}|1f6feb|Message for ${agent_a} (opened as a pull request)"
  "for-${agent_b}|8957e5|Message for ${agent_b} (opened as an issue)"
  "done|2da44e|Handled and closed"
  "blocked|d73a49|Waiting on a decision from ${owner}"
)

for entry in "${labels[@]}"; do
  IFS='|' read -r name color desc <<<"$entry"
  if [ "$dry_run" -eq 1 ]; then
    printf 'would create/update %-24s #%s  %s  (repo %s)\n' "$name" "$color" "$desc" "$repo"
  else
    gh label create "$name" --repo "$repo" --color "$color" --description "$desc" --force >/dev/null
    printf 'ok %-24s #%s  %s\n' "$name" "$color" "$desc"
  fi
done
