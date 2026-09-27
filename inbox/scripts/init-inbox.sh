#!/usr/bin/env bash
# Generate a ready-to-commit Agent Inbox repository layout from the kit templates.
# Nothing is pushed; review the output, then commit it to your private inbox repo.
#
# Usage:
#   ./init-inbox.sh --dir PATH --agent-a coordinator --agent-b builder \
#       [--owner "the owner"] [--repo OWNER/REPO] [--with-workflow] [--force]
#
# --with-workflow  also write .github/workflows/wake-<agent-a>.yml (webhook wake-up)
# --force          overwrite files that already exist in PATH
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tpl="$script_dir/../templates"

dir=""; agent_a=""; agent_b=""; owner="the owner"; repo="OWNER/agent-inbox"; with_workflow=0; force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) dir="${2:-}"; shift 2 ;;
    --agent-a) agent_a="${2:-}"; shift 2 ;;
    --agent-b) agent_b="${2:-}"; shift 2 ;;
    --owner) owner="${2:-}"; shift 2 ;;
    --repo) repo="${2:-}"; shift 2 ;;
    --with-workflow) with_workflow=1; shift ;;
    --force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$dir" ] || { echo "missing --dir" >&2; exit 2; }
slug_re='^[a-z0-9][a-z0-9-]{0,39}$'
for pair in "agent-a:$agent_a" "agent-b:$agent_b"; do
  name="${pair%%:*}"; value="${pair#*:}"
  [ -n "$value" ] || { echo "missing --$name" >&2; exit 2; }
  [[ "$value" =~ $slug_re ]] || { echo "invalid --$name '$value' (use lowercase letters, digits, hyphens)" >&2; exit 2; }
done
[ "$agent_a" != "$agent_b" ] || { echo "--agent-a and --agent-b must differ" >&2; exit 2; }
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "invalid --repo '$repo' (expected OWNER/REPO)" >&2; exit 2; }
case "$owner" in *$'\n'*|"") echo "invalid --owner" >&2; exit 2 ;; esac

render() { # render <template> <destination>
  local src="$tpl/$1" dest="$dir/$2" content
  if [ -e "$dest" ] && [ "$force" -eq 0 ]; then
    echo "skip (exists): $2"; return 0
  fi
  mkdir -p "$(dirname "$dest")"
  content="$(cat "$src"; printf x)"; content="${content%x}"
  content="${content//\{\{AGENT_A\}\}/$agent_a}"
  content="${content//\{\{AGENT_B\}\}/$agent_b}"
  content="${content//\{\{OWNER\}\}/$owner}"
  content="${content//\{\{INBOX_REPO\}\}/$repo}"
  printf '%s' "$content" > "$dest"
  echo "wrote $2"
}

mkdir -p "$dir"
render README.md README.md
render BOARD.md BOARD.md
render RULES-FOR-AGENT-A.md "RULES-FOR-${agent_a}.md"
render RULES-FOR-AGENT-B.md "RULES-FOR-${agent_b}.md"
render message.md messages/_TEMPLATE.md
mkdir -p "$dir/messages/for-${agent_a}" && touch "$dir/messages/for-${agent_a}/.gitkeep"
render github/pull_request_template.md .github/pull_request_template.md
render github/ISSUE_TEMPLATE/for-agent-b.md ".github/ISSUE_TEMPLATE/for-${agent_b}.md"
if [ "$with_workflow" -eq 1 ]; then
  render github/workflows/wake-agent-a.yml ".github/workflows/wake-${agent_a}.yml"
fi

cat <<NEXT

Next steps:
  1. Review the files in $dir, then commit and push them to $repo (keep it private).
  2. Create labels:   $script_dir/setup-labels.sh --repo $repo --agent-a $agent_a --agent-b $agent_b
  3. Wire wake-ups:   see inbox/CONNECT-YOUR-AGENTS.md
NEXT
