#Requires -Version 5.1
<#
.SYNOPSIS
  Create or update the Agent Inbox labels in a GitHub repository.
.DESCRIPTION
  Idempotent: existing labels are updated in place (gh label create --force).
  Requires the gh CLI, authenticated with access to the repository.
.EXAMPLE
  .\setup-labels.ps1 -Repo OWNER/REPO -AgentA coordinator -AgentB builder
.EXAMPLE
  .\setup-labels.ps1 -Repo OWNER/REPO -AgentA coordinator -AgentB builder -Owner 'Sam' -DryRun
#>
[CmdletBinding()]
param(
  [string]$Repo = $env:INBOX_REPO,
  [string]$AgentA = $env:AGENT_A,
  [string]$AgentB = $env:AGENT_B,
  [string]$Owner = $(if ($env:INBOX_OWNER) { $env:INBOX_OWNER } else { 'the owner' }),
  [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$slug = '^[a-z0-9][a-z0-9-]{0,39}$'
foreach ($pair in @(@('AgentA', $AgentA), @('AgentB', $AgentB))) {
  if ([string]::IsNullOrWhiteSpace($pair[1])) { throw ("missing -{0}" -f $pair[0]) }
  if ($pair[1] -cnotmatch $slug) { throw ("invalid -{0} '{1}' (use lowercase letters, digits, hyphens)" -f $pair[0], $pair[1]) }
}
if ($AgentA -eq $AgentB) { throw '-AgentA and -AgentB must differ' }

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'gh CLI not found: https://cli.github.com/' }

if (-not $DryRun) {
  & gh auth status *> $null
  if ($LASTEXITCODE -ne 0) { throw 'gh is not authenticated (run: gh auth login)' }
  if (-not $Repo) {
    $Repo = (& gh repo view --json nameWithOwner --jq .nameWithOwner).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $Repo) { throw 'could not detect repo; pass -Repo OWNER/REPO' }
  }
}
if (-not $Repo) { $Repo = 'OWNER/REPO' }

$labels = @(
  @{ Name = "for-$AgentA"; Color = '1f6feb'; Description = "Message for $AgentA (opened as a pull request)" },
  @{ Name = "for-$AgentB"; Color = '8957e5'; Description = "Message for $AgentB (opened as an issue)" },
  @{ Name = 'done';        Color = '2da44e'; Description = 'Handled and closed' },
  @{ Name = 'blocked';     Color = 'd73a49'; Description = "Waiting on a decision from $Owner" }
)

foreach ($l in $labels) {
  if ($DryRun) {
    Write-Host ("would create/update {0,-24} #{1}  {2}  (repo {3})" -f $l.Name, $l.Color, $l.Description, $Repo)
    continue
  }
  & gh label create $l.Name --repo $Repo --color $l.Color --description $l.Description --force | Out-Null
  if ($LASTEXITCODE -ne 0) { throw ("gh label create failed for {0}" -f $l.Name) }
  Write-Host ("ok {0,-24} #{1}  {2}" -f $l.Name, $l.Color, $l.Description)
}
