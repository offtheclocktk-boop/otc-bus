#Requires -Version 5.1
[CmdletBinding()]
param([string]$BusRoot='', [int]$TimingWindow=30)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not $BusRoot) { $BusRoot=$PSScriptRoot }
$PendingDir=Join-Path $BusRoot 'pending'; $FailedDir=Join-Path $BusRoot 'failed'
$StatePath=Join-Path $BusRoot 'state.json'; $ProgressPath=Join-Path $BusRoot 'progress.json'
$TimingPath=Join-Path $BusRoot 'events\timing.jsonl'; $TaskName='OTC-Bus-Watch'
function Get-JsonFileIds([string]$Dir) { if (-not (Test-Path $Dir)) { return @() }; @(Get-ChildItem $Dir -Filter '*.json' -File -EA SilentlyContinue | Sort-Object CreationTimeUtc,Name | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) }) }
function Get-WatchState { try { return [string](Get-ScheduledTask -TaskName $TaskName -EA Stop).State } catch { return 'Missing' } }
function Get-Percentile([double[]]$Values,[double]$P){ if(-not $Values -or $Values.Count-eq 0){return $null}; $s=@($Values|Sort-Object); $n=$s.Count; if($n-eq 1){return [int]$s[0]}; $i=[Math]::Max(0,[Math]::Min($n-1,[int][Math]::Ceiling($P*$n)-1)); return [int]$s[$i] }
function Get-TimingStats([string]$Path,[int]$Window){ if(-not (Test-Path $Path)){ return [ordered]@{count=0;p50Ms=$null;p95Ms=$null;lastMs=$null} }; $list=New-Object Collections.Generic.List[double]; $last=$null; foreach($line in Get-Content $Path -Encoding UTF8 -EA SilentlyContinue){ if([string]::IsNullOrWhiteSpace($line)){continue}; try{ $o=$line|ConvertFrom-Json; if($null -ne $o.ms){ [void]$list.Add([double]$o.ms); $last=[int]$o.ms } }catch{} }; $vals=@($list); if($vals.Count -gt $Window){ $vals=$vals[($vals.Count-$Window)..($vals.Count-1)] }; return [ordered]@{count=$vals.Count;p50Ms=(Get-Percentile $vals 0.5);p95Ms=(Get-Percentile $vals 0.95);lastMs=$last} }
$state=$null; if(Test-Path $StatePath){ try{$state=Get-Content $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}catch{} }
$progress=$null; if(Test-Path $ProgressPath){ try{$progress=Get-Content $ProgressPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{} }
$pendingIds=@(Get-JsonFileIds $PendingDir); $failedIds=@(Get-JsonFileIds $FailedDir); $timing=Get-TimingStats $TimingPath $TimingWindow
$bridge='1.2.7'; if($state -and $state.bridge){$bridge=[string]$state.bridge}
$obj=[ordered]@{bridge=$bridge;status=$(if($state -and $state.status){[string]$state.status}else{'unknown'});lastId=$(if($state){$state.lastId}else{$null});lastError=$(if($state){$state.lastError}else{$null});pending=$pendingIds.Count;failed=$failedIds.Count;pendingIds=$pendingIds;failedIds=$failedIds;phase=$(if($progress){[string]$progress.phase}else{$null});progressId=$(if($progress){$progress.id}else{$null});detail=$(if($progress){[string]$progress.detail}else{$null});watch=(Get-WatchState);timing=$timing;updatedAt=$(if($state){$state.updatedAt}else{$null})}
Write-Output ($obj|ConvertTo-Json -Compress -Depth 6)
