#Requires -Version 5.1
<#
.SYNOPSIS
  Wait for an OTC bus job result by id.
.NOTES
  Terminal success: ok=true (exit 0)
  Terminal failure: failed/{id}.json exists, or ok=false with no pending retry (exit 1)
  Soft-fail while pending/{id}.json still exists is NOT terminal — keep polling.
  Timeout: exit 2
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Id,
  [int]$TimeoutSec = 600,
  [int]$PollSec = 2,
  [string]$BusRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $BusRoot) { $BusRoot = $PSScriptRoot }
if ($Id -notmatch '^[a-zA-Z0-9._-]+$') { throw "invalid id: $Id" }
if ($PollSec -lt 1) { $PollSec = 1 }
if ($TimeoutSec -lt 1) { $TimeoutSec = 1 }

$OutboxPath = Join-Path $BusRoot 'outbox.jsonl'
$ArchiveOutboxDir = Join-Path $BusRoot 'archive\outbox'
$PendingDir = Join-Path $BusRoot 'pending'
$FailedDir = Join-Path $BusRoot 'failed'

function Get-LatestOutboxObj {
  param([string]$JobId)
  $best = $null
  $arch = Join-Path $ArchiveOutboxDir ($JobId + '.json')
  if (Test-Path -LiteralPath $arch) {
    try { $best = (Get-Content -LiteralPath $arch -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
  }
  if (Test-Path -LiteralPath $OutboxPath) {
    $lines = Get-Content -LiteralPath $OutboxPath -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 }
    foreach ($line in $lines) {
      try {
        $obj = $line | ConvertFrom-Json
        if ($obj -and ([string]$obj.id -eq $JobId)) { $best = $obj }
      } catch { }
    }
  }
  return $best
}

$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
while ($true) {
  $pendingPath = Join-Path $PendingDir ($Id + '.json')
  $failedPath = Join-Path $FailedDir ($Id + '.json')
  $stillPending = Test-Path -LiteralPath $pendingPath
  $isFailed = Test-Path -LiteralPath $failedPath
  $obj = Get-LatestOutboxObj -JobId $Id

  if ($obj -and ($obj.ok -eq $true) -and (-not $stillPending)) {
    Write-Output ($obj | ConvertTo-Json -Compress -Depth 12)
    exit 0
  }

  if ($isFailed) {
    $payload = $obj
    if (-not $payload) {
      $payload = [pscustomobject]@{ id = $Id; ok = $false; error = 'failed'; bridge = 'wait' }
    }
    Write-Output ($payload | ConvertTo-Json -Compress -Depth 12)
    exit 1
  }

  # Soft-fail: outbox has ok=false but pending still exists for retry — keep waiting
  if ($obj -and ($obj.ok -eq $false) -and (-not $stillPending)) {
    Write-Output ($obj | ConvertTo-Json -Compress -Depth 12)
    exit 1
  }

  if ([DateTime]::UtcNow -ge $deadline) {
    Write-Output (@{ id = $Id; ok = $false; error = 'timeout'; bridge = 'wait'; at = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') } | ConvertTo-Json -Compress)
    exit 2
  }
  Start-Sleep -Seconds $PollSec
}
