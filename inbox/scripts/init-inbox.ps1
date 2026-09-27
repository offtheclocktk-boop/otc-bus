#Requires -Version 5.1
<#
.SYNOPSIS
  Generate a ready-to-commit Agent Inbox repository layout from the kit templates.
.DESCRIPTION
  Nothing is pushed; review the output, then commit it to your private inbox repo.
  Existing files are skipped unless -Force is given.
.EXAMPLE
  .\init-inbox.ps1 -Dir ..\..\..\agent-inbox -AgentA coordinator -AgentB builder -Owner 'Sam' -Repo sam/agent-inbox
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Dir,
  [Parameter(Mandatory)][string]$AgentA,
  [Parameter(Mandatory)][string]$AgentB,
  [string]$Owner = 'the owner',
  [string]$Repo = 'OWNER/agent-inbox',
  [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$slug = '^[a-z0-9][a-z0-9-]{0,39}$'
if ($AgentA -cnotmatch $slug) { throw "invalid -AgentA '$AgentA' (use lowercase letters, digits, hyphens)" }
if ($AgentB -cnotmatch $slug) { throw "invalid -AgentB '$AgentB' (use lowercase letters, digits, hyphens)" }
if ($AgentA -eq $AgentB) { throw '-AgentA and -AgentB must differ' }
if ($Repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw "invalid -Repo '$Repo' (expected OWNER/REPO)" }
if ([string]::IsNullOrWhiteSpace($Owner) -or $Owner -match '[\r\n]') { throw 'invalid -Owner' }

$tpl = Join-Path (Split-Path -Parent $PSScriptRoot) 'templates'
if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
$Dir = (Resolve-Path -LiteralPath $Dir).Path
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Rendered([string]$Template, [string]$Destination) {
  $src = Join-Path $tpl $Template
  $dest = Join-Path $Dir $Destination
  if ((Test-Path -LiteralPath $dest) -and -not $Force) { Write-Host "skip (exists): $Destination"; return }
  $parent = Split-Path -Parent $dest
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  $text = [System.IO.File]::ReadAllText($src, $utf8)
  $text = $text.Replace('{{AGENT_A}}', $AgentA).Replace('{{AGENT_B}}', $AgentB)
  $text = $text.Replace('{{OWNER}}', $Owner).Replace('{{INBOX_REPO}}', $Repo)
  [System.IO.File]::WriteAllText($dest, $text, $utf8)
  Write-Host "wrote $Destination"
}

Write-Rendered 'README.md' 'README.md'
Write-Rendered 'BOARD.md' 'BOARD.md'
Write-Rendered 'RULES-FOR-AGENT-A.md' "RULES-FOR-$AgentA.md"
Write-Rendered 'RULES-FOR-AGENT-B.md' "RULES-FOR-$AgentB.md"
Write-Rendered 'message.md' 'messages/_TEMPLATE.md'
$keepDir = Join-Path (Join-Path $Dir 'messages') ("for-{0}" -f $AgentA)
if (-not (Test-Path -LiteralPath $keepDir)) { New-Item -ItemType Directory -Path $keepDir -Force | Out-Null }
$keep = Join-Path $keepDir '.gitkeep'
if (-not (Test-Path -LiteralPath $keep)) { [System.IO.File]::WriteAllText($keep, '', $utf8) }
Write-Rendered 'github/pull_request_template.md' '.github/pull_request_template.md'
Write-Rendered 'github/ISSUE_TEMPLATE/for-agent-b.md' (".github/ISSUE_TEMPLATE/for-{0}.md" -f $AgentB)

Write-Host ''
Write-Host 'Next steps:'
Write-Host ("  1. Review the files in {0}, then commit and push them to {1} (keep it private)." -f $Dir, $Repo)
Write-Host ("  2. Create labels:  {0} -Repo {1} -AgentA {2} -AgentB {3}" -f (Join-Path $PSScriptRoot 'setup-labels.ps1'), $Repo, $AgentA, $AgentB)
Write-Host '  3. Wire wake-ups:  see inbox/CONNECT-YOUR-AGENTS.md'
