#Requires -Version 5.1
# Print recent terminal events (for agents / debugging)
param([string]$BusRoot = '', [int]$Last = 10)
if (-not $BusRoot) { $BusRoot = $PSScriptRoot }
$log = Join-Path $BusRoot 'events\terminal.jsonl'
if (-not (Test-Path $log)) { Write-Host 'no terminal events yet'; exit 0 }
Get-Content $log -Tail $Last
