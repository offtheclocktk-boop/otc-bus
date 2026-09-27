#Requires -Version 5.1
<#
.SYNOPSIS
  Drain bus terminal events into a human-readable NOTIFY-LATEST.txt (and optional webhook POST).
  Hard product companion to otc-bridge Emit-TerminalEvent - not an agent memory.
#>
[CmdletBinding()]
param(
  [string]$BusRoot = '',
  [string]$WebhookUrl = '',
  [switch]$Watch,
  [int]$PollSec = 5
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $BusRoot) { $BusRoot = $PSScriptRoot }
$EventsDir = Join-Path $BusRoot 'events'
$Mark = Join-Path $BusRoot 'logs\notify-drain.mark'
$Latest = Join-Path $BusRoot 'NOTIFY-LATEST.txt'
$LogDir = Join-Path $BusRoot 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path $EventsDir)) { New-Item -ItemType Directory -Path $EventsDir -Force | Out-Null }

function Get-Mark {
  if (Test-Path $Mark) { return [DateTime]::Parse((Get-Content $Mark -Raw).Trim(), $null, [Globalization.DateTimeStyles]::RoundtripKind) }
  return [DateTime]::UtcNow.AddDays(-1)
}
function Set-Mark([DateTime]$dt) {
  [IO.File]::WriteAllText($Mark, $dt.ToUniversalTime().ToString('o'), [Text.UTF8Encoding]::new($false))
}

function Drain-Once {
  $since = Get-Mark
  $files = @(Get-ChildItem $EventsDir -Filter 'terminal-*.json' -File -EA SilentlyContinue | Sort-Object LastWriteTimeUtc)
  $newMark = $since
  foreach ($f in $files) {
    if ($f.LastWriteTimeUtc -le $since) { continue }
    $obj = Get-Content $f.FullName -Raw | ConvertFrom-Json
    $lines = @(
      ('OTC TERMINAL {0}' -f $obj.at),
      ('id={0} ok={1} bridge={2}' -f $obj.id, $obj.ok, $obj.bridge),
      ('version={0}' -f $obj.version),
      ('detail={0}' -f $obj.detail),
      ('paths={0}' -f (($obj.paths) -join '; ')),
      ('notifyAgentId={0}' -f $obj.notifyAgentId)
    )
    $text = ($lines -join "`n") + "`n"
    [IO.File]::WriteAllText($Latest, $text, [Text.UTF8Encoding]::new($false))
    Add-Content (Join-Path $LogDir 'notify-drain.log') $text.Trim() -Encoding UTF8
    if ($WebhookUrl) {
      try {
        Invoke-RestMethod -Method Post -Uri $WebhookUrl -ContentType 'application/json' -Body (($obj | ConvertTo-Json -Compress -Depth 8)) | Out-Null
      } catch {
        Add-Content (Join-Path $LogDir 'notify-drain.log') ("webhook err: " + $_.Exception.Message) -Encoding UTF8
      }
    }
    Write-Host ("drained {0} ok={1}" -f $obj.id, $obj.ok)
    if ($f.LastWriteTimeUtc -gt $newMark) { $newMark = $f.LastWriteTimeUtc }
  }
  Set-Mark $newMark
}

Drain-Once
while ($Watch) {
  Start-Sleep -Seconds ([Math]::Max(2, $PollSec))
  Drain-Once
}
