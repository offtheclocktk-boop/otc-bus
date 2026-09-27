#Requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Id,
  [Parameter(Mandatory)][string]$Task,
  [string[]]$Paths = @(),
  [string]$Done = '',
  [int]$TimeoutSec = 300,
  [string]$Kind = 'implement',
  [string]$AcceptJson = '',
  [int]$MaxAttempts = 2,
  [string]$NotifyAgentId = '',
  [string]$BusRoot = '',
  [switch]$AllowSupersede
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $BusRoot) { $BusRoot = $PSScriptRoot }
if ($Id -notmatch '^[a-zA-Z0-9._-]+$') { throw "invalid id: $Id" }
if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }
function Sanitize-PromptText([string]$Text) {
  if ($null -eq $Text) { return '' }
  $Text = $Text.Replace([char]0x2014, '-').Replace([char]0x2013, '-').Replace([char]0x2012, '-')
  $Text = $Text.Replace([char]0x2018, "'").Replace([char]0x2019, "'")
  $Text = $Text.Replace([char]0x201C, '"').Replace([char]0x201D, '"')
  return $Text
}
$PendingDir = Join-Path $BusRoot 'pending'
$FailedDir = Join-Path $BusRoot 'failed'
$ArchiveOutboxDir = Join-Path $BusRoot 'archive\outbox'
$OutboxPath = Join-Path $BusRoot 'outbox.jsonl'
if (-not (Test-Path $PendingDir)) { New-Item -ItemType Directory -Path $PendingDir -Force | Out-Null }
$inbox = Join-Path $BusRoot 'inbox.jsonl'
if (-not (Test-Path -LiteralPath $inbox)) { [IO.File]::WriteAllText($inbox, '', [Text.UTF8Encoding]::new($false)) }
if (Test-Path -LiteralPath (Join-Path $FailedDir ($Id + '.STOP.txt'))) { throw "job STOP'd - refuse enqueue: $Id" }
function Test-IdAlreadyOk([string]$JobId) {
  $arch = Join-Path $ArchiveOutboxDir ($JobId + '.json')
  if (Test-Path -LiteralPath $arch) { try { $o = Get-Content $arch -Raw -Encoding UTF8 | ConvertFrom-Json; if ($o.ok -eq $true) { return $true } } catch {} }
  if (Test-Path -LiteralPath $OutboxPath) {
    foreach ($h in @(Select-String -LiteralPath $OutboxPath -Pattern ('"id"\s*:\s*"' + [regex]::Escape($JobId) + '"') -Encoding UTF8 -EA SilentlyContinue)) {
      try { $o = $h.Line | ConvertFrom-Json; if ($o.id -eq $JobId -and $o.ok -eq $true) { return $true } } catch {}
    }
  }
  return $false
}
if (-not $AllowSupersede -and (Test-IdAlreadyOk $Id)) { throw "id already DONE ok - refuse supersede (pass -AllowSupersede): $Id" }
$Task = Sanitize-PromptText $Task; $Done = Sanitize-PromptText $Done
$job = [ordered]@{ id=$Id; task=$Task; paths=@($Paths); done=$Done; timeoutSec=$TimeoutSec; kind=$Kind; attempts=0; maxAttempts=$MaxAttempts; enqueuedAt=[DateTime]::UtcNow.ToString('o'); bridge='2.0.0' }
if ($AcceptJson) { $job.accept = ($AcceptJson | ConvertFrom-Json) }
if ($NotifyAgentId) { $job.notifyAgentId = $NotifyAgentId }
$json = ($job | ConvertTo-Json -Compress -Depth 12)
$path = Join-Path $PendingDir ($Id + '.json')
try {
  $fs = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $b=[Text.UTF8Encoding]::new($false).GetBytes($json); $fs.Write($b,0,$b.Length) } finally { $fs.Dispose() }
} catch [IO.IOException] { throw "pending job already exists: $Id" }
Add-Content -LiteralPath $inbox -Value $json -Encoding UTF8
Write-Host "enqueued $Id -> $path"
