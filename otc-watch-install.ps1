#Requires -Version 5.1
<#
.SYNOPSIS
  Install or uninstall Scheduled Task OTC-Bus-Watch (bridge -Watch -PollSec 5 -MaxJobs 0).
#>
[CmdletBinding()]
param(
  [switch]$Uninstall,
  [string]$BusRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $BusRoot) { $BusRoot = $PSScriptRoot }
$TaskName = 'OTC-Bus-Watch'
$BridgePath = Join-Path $BusRoot 'otc-bridge.ps1'
$PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Get-ExistingTask {
  try { return Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { return $null }
}

if ($Uninstall) {
  $existing = Get-ExistingTask
  if (-not $existing) {
    Write-Host "not installed: $TaskName"
    exit 0
  }
  try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } catch { }
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  Write-Host "uninstalled $TaskName"
  exit 0
}

if (-not (Test-Path -LiteralPath $BridgePath)) {
  throw "bridge not found: $BridgePath"
}
if (-not (Test-Path -LiteralPath $PsExe)) {
  throw "powershell.exe not found: $PsExe"
}

$arg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Watch -PollSec 5 -MaxJobs 0' -f $BridgePath
$action = New-ScheduledTaskAction -Execute $PsExe -Argument $arg -WorkingDirectory $BusRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -DontStopOnIdleEnd `
  -StartWhenAvailable `
  -Hidden `
  -MultipleInstances IgnoreNew `
  -RestartCount 3 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero)
$who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $who -LogonType Interactive -RunLevel Limited
$desc = 'OTC Bus watch: otc-bridge.ps1 -Watch -PollSec 5 -MaxJobs 0'

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $desc -Force | Out-Null
try { Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch {
  Write-Warning ("task registered but start failed: {0}" -f $_.Exception.Message)
}
Write-Host "installed $TaskName -> $PsExe $arg"
exit 0
