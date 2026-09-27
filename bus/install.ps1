#Requires -Version 5.1
<#
.SYNOPSIS
  Copy the OTC Bus scripts into an install folder.
.DESCRIPTION
  Copies otc-*.ps1 from this folder into -Destination. Runtime folders (pending/, archive/,
  events/, logs/ ...) are created by the scripts on first run. Existing scripts are only
  overwritten with -Force. Runtime data in the destination is never touched.
  Does not install the grok CLI.
.PARAMETER Destination
  Install folder. Default: C:\OffTheClock\bus on Windows, ~/OffTheClock/bus elsewhere.
.PARAMETER Force
  Overwrite scripts that already exist in the destination (use for upgrades).
#>
[CmdletBinding()]
param(
  [string]$Destination = '',
  [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Destination) {
  $onWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
  if ($onWindows) { $Destination = 'C:\OffTheClock\bus' }
  else { $Destination = Join-Path (Join-Path $HOME 'OffTheClock') 'bus' }
}
if (-not (Test-Path -LiteralPath $Destination)) {
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

$copied = 0; $skipped = 0
foreach ($f in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'otc-*.ps1' -File)) {
  $target = Join-Path $Destination $f.Name
  if ((Test-Path -LiteralPath $target) -and -not $Force) {
    Write-Host ("skip (exists, use -Force to overwrite): {0}" -f $target)
    $skipped++
    continue
  }
  Copy-Item -LiteralPath $f.FullName -Destination $target -Force
  $copied++
}
Write-Host ("installed {0} script(s) to {1} ({2} skipped)" -f $copied, $Destination, $skipped)

if (-not (Get-Command 'grok' -ErrorAction SilentlyContinue)) {
  Write-Warning "grok CLI not found on PATH. Install it, or set 'cli' in state.json to its full path."
}
Write-Host ("next: cd `"{0}`" ; .\otc-enqueue.ps1 -Id demo-1 -Kind investigate -Task 'Reply with exactly: hello' -Done 'notes say hello' ; .\otc-bridge.ps1" -f $Destination)
