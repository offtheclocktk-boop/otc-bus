#Requires -Version 5.1
[CmdletBinding()]
param([string]$BusRoot='', [switch]$Uninstall, [int]$PollSec=60)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $BusRoot){$BusRoot=$PSScriptRoot}
$TaskName='OTC-Bus-Notify-Drain'
$drain=Join-Path $BusRoot 'otc-notify-drain.ps1'
if(-not (Test-Path $drain)){ throw "missing $drain" }
if($Uninstall){ Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -EA SilentlyContinue; Write-Host "uninstalled $TaskName"; return }
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arg="-NoProfile -ExecutionPolicy Bypass -File `"$drain`" -BusRoot `"$BusRoot`" -Watch -PollSec $PollSec"
Register-ScheduledTask -TaskName $TaskName -Action (New-ScheduledTaskAction -Execute $ps -Argument $arg) -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)) -Principal (New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited) -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName -EA SilentlyContinue
Write-Host "installed $TaskName (Watch PollSec=$PollSec)"
