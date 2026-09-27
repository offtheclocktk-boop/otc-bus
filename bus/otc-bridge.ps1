#Requires -Version 5.1
<#
.SYNOPSIS
  OTC Bus bridge: pending/ job -> grok CLI -> outbox + archive.
.PARAMETER Id
  Job id to process. If omitted, oldest pending job(s). Ignores -MaxJobs (single id).
.PARAMETER Force
  Break a stale/running lock once at start of run.
.PARAMETER Migrate
  Migrate legacy inbox.jsonl lines into pending/*.json then exit.
.PARAMETER MaxJobs
  Process up to N pending jobs per cycle (FIFO). Default 1. 0 = unlimited.
.PARAMETER Watch
  After draining a cycle, poll pending every -PollSec until Ctrl+C / kill.
.PARAMETER PollSec
  Watch idle poll interval seconds (default 5, min 2).
.PARAMETER WorkDir
  Working directory for the grok CLI. Resolution order: -WorkDir, then the
  OTC_WORKDIR environment variable, then C:\OffTheClock if it exists, then the bus folder.
#>
[CmdletBinding()]
param(
  [string]$Id,
  [switch]$Force,
  [switch]$Migrate,
  [int]$MaxJobs = 1,
  [switch]$Watch,
  [int]$PollSec = 5,
  [string]$WorkDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BusRoot = $PSScriptRoot
$PendingDir = Join-Path $BusRoot 'pending'
$FailedDir = Join-Path $BusRoot 'failed'
$EventsDir = Join-Path $BusRoot 'events'
$ArchiveInboxDir = Join-Path $BusRoot 'archive\inbox'
$ArchiveOutboxDir = Join-Path $BusRoot 'archive\outbox'
$InboxPath = Join-Path $BusRoot 'inbox.jsonl'
$OutboxPath = Join-Path $BusRoot 'outbox.jsonl'
$StatePath = Join-Path $BusRoot 'state.json'
$ProgressPath = Join-Path $BusRoot 'progress.json'
$LogDir = Join-Path $BusRoot 'logs'
$LogPath = Join-Path $LogDir 'bridge.log'
$BridgeVersion = '2.0.0'

function Get-UtcNowIso {
  return [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Ensure-Layout {
  foreach ($p in @($BusRoot, $PendingDir, $FailedDir, $ArchiveInboxDir, $ArchiveOutboxDir, $LogDir, $EventsDir)) {
    if (-not (Test-Path -LiteralPath $p)) {
      New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
  }
  foreach ($f in @($InboxPath, $OutboxPath)) {
    if (-not (Test-Path -LiteralPath $f)) {
      [System.IO.File]::WriteAllText($f, '', [System.Text.UTF8Encoding]::new($false))
    }
  }
}

function Read-State {
  if (-not (Test-Path -LiteralPath $StatePath)) {
    return [pscustomobject]@{
      root      = $BusRoot
      status    = 'idle'
      lastId    = $null
      lastError = $null
      cli       = 'grok'
      bridge    = $BridgeVersion
      updatedAt = $null
    }
  }
  $raw = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8
  return ($raw | ConvertFrom-Json)
}

function Write-StateObject {
  param([Parameter(Mandatory)]$State)
  # Rebuild as ordered hashtable so new fields (bridge) always serialize even on old state.json
  $h = [ordered]@{
    root      = $BusRoot
    status    = $(if ($State.PSObject.Properties.Name -contains 'status') { $State.status } else { 'idle' })
    lastId    = $(if ($State.PSObject.Properties.Name -contains 'lastId') { $State.lastId } else { $null })
    lastError = $(if ($State.PSObject.Properties.Name -contains 'lastError') { $State.lastError } else { $null })
    cli       = $(if ($State.PSObject.Properties.Name -contains 'cli' -and $State.cli) { $State.cli } else { 'grok' })
    bridge    = $BridgeVersion
    updatedAt = $(if ($State.PSObject.Properties.Name -contains 'updatedAt') { $State.updatedAt } else { $null })
  }
  $json = ($h | ConvertTo-Json -Compress)
  [System.IO.File]::WriteAllText($StatePath, $json, [System.Text.UTF8Encoding]::new($false))
}

function Write-ProgressObject {
  param(
    [string]$JobId,
    [string]$Phase,
    [string]$Detail = ''
  )
  $obj = [pscustomobject]@{
    id        = $JobId
    phase     = $Phase
    detail    = $Detail
    bridge    = $BridgeVersion
    updatedAt = Get-UtcNowIso
  }
  $json = $obj | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText($ProgressPath, $json, [System.Text.UTF8Encoding]::new($false))
}

function Write-LogLine {
  param([string]$Message)
  $line = "{0} {1}" -f (Get-UtcNowIso), $Message
  Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Append-Jsonl {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Object
  )
  $line = ($Object | ConvertTo-Json -Compress -Depth 12)
  $line = ($line -replace "[\r\n]+", ' ')
  Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

function ConvertTo-JobObject {
  param($Raw)
  # Normalize to object with id/task/paths/done/timeoutSec/accept/kind
  return $Raw
}

function Get-OutboxRows {
  if (-not (Test-Path -LiteralPath $OutboxPath)) { return @() }
  $rows = @()
  $lines = Get-Content -LiteralPath $OutboxPath -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 }
  foreach ($line in $lines) {
    try { $rows += ($line | ConvertFrom-Json) } catch { }
  }
  return $rows
}

function Test-SuccessfulOutbox {
  param([Parameter(Mandatory)][string]$JobId)
  foreach ($r in @(Get-OutboxRows)) {
    if (($r.id -eq $JobId) -and ($r.ok -eq $true)) { return $true }
  }
  return $false
}

function Save-PendingJob {
  param([Parameter(Mandatory)]$Job)
  $jobId = [string]$Job.id
  if ([string]::IsNullOrWhiteSpace($jobId)) { return }
  $path = Join-Path $PendingDir ($jobId + '.json')
  if (Test-Path -LiteralPath $path) { return }
  if (Test-SuccessfulOutbox -JobId $jobId) { return }
  $json = $Job | ConvertTo-Json -Compress -Depth 12
  [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Migrate-InboxToPending {
  if (-not (Test-Path -LiteralPath $InboxPath)) { return 0 }
  $n = 0
  $lines = Get-Content -LiteralPath $InboxPath -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 }
  foreach ($line in $lines) {
    try {
      $job = $line | ConvertFrom-Json
      $before = @(Get-ChildItem -LiteralPath $PendingDir -Filter '*.json' -ErrorAction SilentlyContinue).Count
      Save-PendingJob -Job $job
      $after = @(Get-ChildItem -LiteralPath $PendingDir -Filter '*.json' -ErrorAction SilentlyContinue).Count
      if ($after -gt $before) { $n++ }
    } catch { }
  }
  # Compact inbox: keep only jobs still pending and not successfully completed
  $kept = New-Object System.Collections.Generic.List[string]
  foreach ($line in $lines) {
    try {
      $job = $line | ConvertFrom-Json
      $jid = [string]$job.id
      if (Test-SuccessfulOutbox -JobId $jid) {
        $arch = Join-Path $ArchiveInboxDir ($jid + '.json')
        if (-not (Test-Path -LiteralPath $arch)) {
          [System.IO.File]::WriteAllText($arch, ($job | ConvertTo-Json -Compress -Depth 12), [System.Text.UTF8Encoding]::new($false))
        }
        continue
      }
      if (Test-Path -LiteralPath (Join-Path $PendingDir ($jid + '.json'))) {
        # already in pending; drop from inbox compact
        continue
      }
      [void]$kept.Add(($job | ConvertTo-Json -Compress -Depth 12))
    } catch {
      [void]$kept.Add($line)
    }
  }
  [System.IO.File]::WriteAllText($InboxPath, (($kept -join "`n") + $(if ($kept.Count -gt 0) { "`n" } else { '' })), [System.Text.UTF8Encoding]::new($false))
  return $n
}

function Get-PendingJobs {
  $files = @(Get-ChildItem -LiteralPath $PendingDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object CreationTimeUtc, Name)
  $jobs = @()
  foreach ($f in $files) {
    try {
      $job = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
      $job | Add-Member -NotePropertyName _pendingPath -NotePropertyValue $f.FullName -Force
      $jobs += $job
    } catch { }
  }
  return $jobs
}

function Archive-PendingJob {
  param(
    [Parameter(Mandatory)][string]$PendingPath,
    [Parameter(Mandatory)][string]$JobId
  )
  $dest = Join-Path $ArchiveInboxDir ($JobId + '.json')
  if (Test-Path -LiteralPath $PendingPath) {
    Move-Item -LiteralPath $PendingPath -Destination $dest -Force
  }
}

function Move-ToFailed {
  param(
    [Parameter(Mandatory)]$Job,
    [Parameter(Mandatory)][string]$PendingPath,
    [Parameter(Mandatory)][string]$JobId
  )
  Ensure-Layout
  $dest = Join-Path $FailedDir ($JobId + '.json')
  $clean = $Job | Select-Object * -ExcludeProperty _pendingPath
  $json = ($clean | ConvertTo-Json -Compress -Depth 12)
  [System.IO.File]::WriteAllText($dest, $json, [System.Text.UTF8Encoding]::new($false))
  if (Test-Path -LiteralPath $PendingPath) {
    Remove-Item -LiteralPath $PendingPath -Force -ErrorAction SilentlyContinue
  }
  Write-LogLine ("{0} moved to failed attempts={1}" -f $JobId, $(if ($Job.PSObject.Properties.Name -contains 'attempts') { $Job.attempts } else { '?' }))
}

function Write-PendingJob {
  param(
    [Parameter(Mandatory)]$Job,
    [Parameter(Mandatory)][string]$PendingPath
  )
  $clean = $Job | Select-Object * -ExcludeProperty _pendingPath
  $json = ($clean | ConvertTo-Json -Compress -Depth 12)
  [System.IO.File]::WriteAllText($PendingPath, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-JobAttempts {
  param([Parameter(Mandatory)]$Job)
  if ($Job.PSObject.Properties.Name -contains 'attempts' -and $null -ne $Job.attempts) {
    try { return [int]$Job.attempts } catch { return 0 }
  }
  return 0
}

function Get-JobMaxAttempts {
  param([Parameter(Mandatory)]$Job)
  if ($Job.PSObject.Properties.Name -contains 'maxAttempts' -and $null -ne $Job.maxAttempts) {
    try {
      $m = [int]$Job.maxAttempts
      if ($m -lt 1) { return 2 }
      return $m
    } catch { return 2 }
  }
  return 2
}

function Resolve-GrokCli {
  param([string]$CliSpec)
  if (-not $CliSpec) { $CliSpec = 'grok' }
  if ([System.IO.Path]::IsPathRooted($CliSpec)) {
    if (Test-Path -LiteralPath $CliSpec) { return (Resolve-Path -LiteralPath $CliSpec).Path }
    return $null
  }
  $cmd = Get-Command $CliSpec -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) { return $cmd.Source }
  if ($env:USERPROFILE) {
    $fallback = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
    if (Test-Path -LiteralPath $fallback) { return $fallback }
  }
  return $null
}

function Resolve-WorkDir {
  # -WorkDir > $env:OTC_WORKDIR > C:\OffTheClock (legacy default, if present) > bus folder
  foreach ($candidate in @($WorkDir, $env:OTC_WORKDIR)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
      if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
      Write-LogLine ("workdir not found, ignoring: {0}" -f $candidate)
    }
  }
  $legacy = 'C:\OffTheClock'
  if (Test-Path -LiteralPath $legacy) { return $legacy }
  return $BusRoot
}

function Get-PathTokensFromText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
  $matches = [regex]::Matches($Text, '(?i)(?:[A-Za-z]:\\|\\\\|/)[^\s"''<>|*?]{2,}')
  $paths = @()
  foreach ($m in $matches) {
    $p = $m.Value.TrimEnd('.,;:)')
    if ($paths -notcontains $p) { $paths += $p }
  }
  return $paths
}


function Sanitize-PromptText {
  param([string]$Text)
  if ($null -eq $Text) { return '' }
  # grok CLI can mis-parse Unicode dashes as option boundaries
  $Text = $Text.Replace([char]0x2014, '-').Replace([char]0x2013, '-').Replace([char]0x2012, '-')
  $Text = $Text.Replace([char]0x2018, "'").Replace([char]0x2019, "'")
  $Text = $Text.Replace([char]0x201C, '"').Replace([char]0x201D, '"')
  return $Text
}

function Build-Prompt {
  param($Job)
  $pathsText = '(none)'
  if ($Job.PSObject.Properties.Name -contains 'paths' -and $Job.paths -and @($Job.paths).Count -gt 0) {
    $pathsText = (@($Job.paths) -join ', ')
  }
  $doneText = '(not specified)'
  if ($Job.PSObject.Properties.Name -contains 'done' -and -not [string]::IsNullOrWhiteSpace([string]$Job.done)) {
    $doneText = [string]$Job.done
  }
  $kind = 'implement'
  if ($Job.PSObject.Properties.Name -contains 'kind' -and $Job.kind) { $kind = [string]$Job.kind }
  $task = [string]$Job.task
  $body = @"
You are Grok Build working a queued job from OTC Bus.
Job kind: $kind
Working files of interest: $pathsText
Definition of done: $doneText
Task:
$task

Respond with the work product. If no files changed, a short textual answer is enough.
"@
  return (Sanitize-PromptText -Text $body)
}

function Test-Acceptance {
  param(
    [Parameter(Mandatory)]$Job,
    $Result = $null
  )
  $failures = New-Object System.Collections.Generic.List[string]

  # Default: listed paths should exist after successful implement jobs
  $paths = @()
  if ($Job.PSObject.Properties.Name -contains 'paths' -and $Job.paths) { $paths = @($Job.paths) }

  $accept = $null
  if ($Job.PSObject.Properties.Name -contains 'accept') { $accept = $Job.accept }

  if ($accept -and ($accept.PSObject.Properties.Name -contains 'pathsExist')) {
    foreach ($p in @($accept.pathsExist)) {
      if (-not (Test-Path -LiteralPath ([string]$p))) { [void]$failures.Add("missing path: $p") }
    }
  } elseif ($paths.Count -gt 0 -and [string]$Job.kind -ne 'investigate') {
    foreach ($p in $paths) {
      if (-not (Test-Path -LiteralPath ([string]$p))) {
        # soft: only fail if job claimed file work; still note
        [void]$failures.Add("path not found (warn): $p")
      }
    }
  }

  # Default: ban backticks in common source outputs (Build often pastes markdown fences)
  $checkFiles = @()
  if ($accept -and ($accept.PSObject.Properties.Name -contains 'noBacktickIn')) {
    $checkFiles = @($accept.noBacktickIn)
  } else {
    foreach ($p in $paths) {
      if ([string]$p -match '\.(lua|ps1|py|js|ts|tsx|jsx|cs|cpp|h|java|go|rs)$') { $checkFiles += $p }
    }
  }
  foreach ($p in $checkFiles) {
    if (Test-Path -LiteralPath ([string]$p)) {
      $text = [System.IO.File]::ReadAllText([string]$p)
      if ($text.Contains([char]96)) { [void]$failures.Add("backtick found in $p") }
    }
  }

  if ($accept -and ($accept.PSObject.Properties.Name -contains 'fileContains')) {
    foreach ($rule in @($accept.fileContains)) {
      $fp = [string]$rule.path
      $needle = [string]$rule.text
      if (-not (Test-Path -LiteralPath $fp)) {
        [void]$failures.Add("fileContains missing: $fp")
        continue
      }
      $text = [System.IO.File]::ReadAllText($fp)
      if ($text -notlike "*$needle*") {
        [void]$failures.Add("fileContains failed: $fp missing '$needle'")
      }
    }
  }

  if ($accept -and ($accept.PSObject.Properties.Name -contains 'forbidContains')) {
    foreach ($rule in @($accept.forbidContains)) {
      $fp = [string]$rule.path
      $bad = [string]$rule.text
      if (-not (Test-Path -LiteralPath $fp)) { continue }
      $text = [System.IO.File]::ReadAllText($fp)
      if ($text -like ("*" + $bad + "*")) {
        [void]$failures.Add("forbidContains hit: $fp contains '$bad'")
      }
    }
  }

  if ($accept -and ($accept.PSObject.Properties.Name -contains 'forbidRegex')) {
    foreach ($rule in @($accept.forbidRegex)) {
      $fp = [string]$rule.path
      $pat = [string]$rule.pattern
      if (-not (Test-Path -LiteralPath $fp)) { continue }
      $text = [System.IO.File]::ReadAllText($fp)
      if ([regex]::IsMatch($text, $pat)) {
        [void]$failures.Add("forbidRegex hit: $fp ~ /$pat/")
      }
    }
  }
  # Treat "path not found (warn)" as soft unless accept.strictPaths
  $strict = $false
  if ($accept -and ($accept.PSObject.Properties.Name -contains 'strictPaths')) {
    $strict = [bool]$accept.strictPaths
  }
  $hard = @()
  foreach ($f in $failures) {
    if (-not $strict -and $f.StartsWith('path not found (warn)')) { continue }
    $hard += $f
  }
  return $hard
}

function Invoke-GrokWithTimeout {
  param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$Prompt,
    [Parameter(Mandatory)][string]$WorkingDirectory,
    [Parameter(Mandatory)][int]$TimeoutSec,
    [Parameter(Mandatory)][string]$JobId,
    [Parameter(Mandatory)]$StateRef
  )

  $tempRoot = $env:TEMP
  if ([string]::IsNullOrWhiteSpace($tempRoot)) { $tempRoot = $env:TMP }
  if ([string]::IsNullOrWhiteSpace($tempRoot)) { $tempRoot = [System.IO.Path]::GetTempPath() }
  $promptFile = Join-Path $tempRoot ("otc-prompt-" + [guid]::NewGuid().ToString() + ".txt")
  $outFile = Join-Path $tempRoot ("otc-out-" + [guid]::NewGuid().ToString() + ".txt")
  $errFile = Join-Path $tempRoot ("otc-err-" + [guid]::NewGuid().ToString() + ".txt")
  $codeFile = Join-Path $tempRoot ("otc-code-" + [guid]::NewGuid().ToString() + ".txt")
  try {
    [System.IO.File]::WriteAllText($promptFile, $Prompt, [System.Text.UTF8Encoding]::new($false))

    $job = Start-Job -ScriptBlock {
      param($Exe, $PromptFile, $WorkingDirectory, $OutFile, $ErrFile, $CodeFile)
      Set-Location -LiteralPath $WorkingDirectory
      $promptText = [System.IO.File]::ReadAllText($PromptFile, [System.Text.UTF8Encoding]::new($false))
      $stdout = ''
      $stderr = ''
      try {
        $all = & $Exe --always-approve --no-plan -p $promptText 2>&1
        $exit = $LASTEXITCODE
        $outLines = New-Object System.Collections.Generic.List[string]
        $errLines = New-Object System.Collections.Generic.List[string]
        foreach ($item in @($all)) {
          if ($item -is [System.Management.Automation.ErrorRecord]) {
            [void]$errLines.Add([string]$item)
          } else {
            [void]$outLines.Add([string]$item)
          }
        }
        $stdout = ($outLines -join "`n")
        $stderr = ($errLines -join "`n")
      } catch {
        $exit = 1
        $stderr = $_.Exception.Message
      }
      if ($null -eq $exit) { $exit = 0 }
      [System.IO.File]::WriteAllText($OutFile, $stdout, [System.Text.UTF8Encoding]::new($false))
      [System.IO.File]::WriteAllText($ErrFile, $stderr, [System.Text.UTF8Encoding]::new($false))
      [System.IO.File]::WriteAllText($CodeFile, ([string]$exit), [System.Text.UTF8Encoding]::new($false))
    } -ArgumentList $Exe, $promptFile, $WorkingDirectory, $outFile, $errFile, $codeFile

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
    while ($true) {
      $finished = Wait-Job -Job $job -Timeout 15
      # heartbeat
      Write-ProgressObject -JobId $JobId -Phase 'grok' -Detail ("waiting; jobState=" + $job.State)
      $StateRef.status = 'running'
      $StateRef.updatedAt = Get-UtcNowIso
      Write-StateObject $StateRef

      if ($finished) { break }
      if ([DateTime]::UtcNow -ge $deadline) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{
          ExitCode = -1
          StdOut   = ''
          StdErr   = ("timeout after {0}s" -f $TimeoutSec)
          TimedOut = $true
        }
      }
    }

    Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    $stdout = ''
    $stderr = ''
    $exitCode = 1
    if (Test-Path -LiteralPath $outFile) { $stdout = [System.IO.File]::ReadAllText($outFile, [System.Text.UTF8Encoding]::new($false)) }
    if (Test-Path -LiteralPath $errFile) { $stderr = [System.IO.File]::ReadAllText($errFile, [System.Text.UTF8Encoding]::new($false)) }
    if (Test-Path -LiteralPath $codeFile) {
      $rawCode = [System.IO.File]::ReadAllText($codeFile, [System.Text.UTF8Encoding]::new($false)).Trim()
      try { $exitCode = [int]$rawCode } catch { $exitCode = 1 }
    }

    return [pscustomobject]@{
      ExitCode = $exitCode
      StdOut   = $stdout
      StdErr   = $stderr
      TimedOut = $false
    }
  } finally {
    Remove-Item -LiteralPath $promptFile, $outFile, $errFile, $codeFile -Force -ErrorAction SilentlyContinue
  }
}


function Emit-TimingEvent {
  param(
    [Parameter(Mandatory)][string]$JobId,
    [Parameter(Mandatory)][bool]$Ok
  )
  if (-not (Test-Path -LiteralPath $EventsDir)) {
    New-Item -ItemType Directory -Path $EventsDir -Force | Out-Null
  }
  $started = $null
  $startedPath = Join-Path $EventsDir ('started-' + $JobId + '.json')
  if (Test-Path -LiteralPath $startedPath) {
    try {
      $sobj = Get-Content -LiteralPath $startedPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($sobj.PSObject.Properties.Name -contains 'at') { $started = [string]$sobj.at }
    } catch { }
  }
  $finished = Get-UtcNowIso
  $ms = $null
  if ($started) {
    try {
      $t0 = [DateTime]::Parse($started, $null, [Globalization.DateTimeStyles]::RoundtripKind)
      $t1 = [DateTime]::Parse($finished, $null, [Globalization.DateTimeStyles]::RoundtripKind)
      $ms = [int]([Math]::Round(($t1 - $t0).TotalMilliseconds))
    } catch { }
  }
  $evt = [ordered]@{
    type       = 'timing'
    id         = $JobId
    ok         = [bool]$Ok
    startedAt  = $started
    finishedAt = $finished
    ms         = $ms
    bridge     = $BridgeVersion
  }
  $line = (($evt | ConvertTo-Json -Compress -Depth 6) -replace "[\r\n]+", ' ')
  Add-Content -LiteralPath (Join-Path $EventsDir 'timing.jsonl') -Value $line -Encoding UTF8
  Write-LogLine ("timing-event id={0} ok={1} ms={2}" -f $JobId, $Ok, $ms)
}
function Emit-TerminalEvent {
  param(
    [Parameter(Mandatory)][string]$JobId,
    [Parameter(Mandatory)][bool]$Ok,
    [string]$Version = '',
    [object]$Paths = $null,
    [string]$Detail = '',
    [string]$NotifyAgentId = ''
  )
  if (-not (Test-Path -LiteralPath $EventsDir)) {
    New-Item -ItemType Directory -Path $EventsDir -Force | Out-Null
  }
  $pathList = @()
  if ($null -ne $Paths) { $pathList = @($Paths) }
  $evt = [ordered]@{
    type          = 'terminal'
    id            = $JobId
    ok            = [bool]$Ok
    version       = $Version
    paths         = $pathList
    detail        = $Detail
    notifyAgentId = $NotifyAgentId
    bridge        = $BridgeVersion
    at            = Get-UtcNowIso
  }
  $line = (($evt | ConvertTo-Json -Compress -Depth 8) -replace "[\r\n]+", ' ')
  Add-Content -LiteralPath (Join-Path $EventsDir 'terminal.jsonl') -Value $line -Encoding UTF8
  [System.IO.File]::WriteAllText((Join-Path $EventsDir ('terminal-' + $JobId + '.json')), $line, [System.Text.UTF8Encoding]::new($false))
  Write-LogLine ("terminal-event id={0} ok={1}" -f $JobId, $Ok)
  try { Emit-TimingEvent -JobId $JobId -Ok $Ok } catch { Write-LogLine ("timing-event-fail id={0} {1}" -f $JobId, $_.Exception.Message) }
}

function Handle-SoftFail {
  param(
    [Parameter(Mandatory)]$Job,
    [Parameter(Mandatory)][string]$JobId,
    [Parameter(Mandatory)]$State,
    [string]$ErrorDetail
  )
  $attempts = (Get-JobAttempts -Job $Job) + 1
  $maxAttempts = Get-JobMaxAttempts -Job $Job
  $Job | Add-Member -NotePropertyName attempts -NotePropertyValue $attempts -Force
  if (-not ($Job.PSObject.Properties.Name -contains 'maxAttempts')) {
    $Job | Add-Member -NotePropertyName maxAttempts -NotePropertyValue $maxAttempts -Force
  }

  $pendingPath = $null
  if ($Job.PSObject.Properties.Name -contains '_pendingPath') { $pendingPath = [string]$Job._pendingPath }

  if ($attempts -ge $maxAttempts) {
    if ($pendingPath) {
      Move-ToFailed -Job $Job -PendingPath $pendingPath -JobId $JobId
    }
    Write-ProgressObject -JobId $JobId -Phase 'failed' -Detail ("attempts={0}/{1} {2}" -f $attempts, $maxAttempts, $ErrorDetail)
    $notifyId = ''
    if ($Job.PSObject.Properties.Name -contains 'notifyAgentId' -and $Job.notifyAgentId) { $notifyId = [string]$Job.notifyAgentId }
    Emit-TerminalEvent -JobId $JobId -Ok $false -Detail $ErrorDetail -NotifyAgentId $notifyId
  } else {
    if ($pendingPath) {
      Write-PendingJob -Job $Job -PendingPath $pendingPath
    }
    Write-ProgressObject -JobId $JobId -Phase 'retry' -Detail ("attempts={0}/{1} {2}" -f $attempts, $maxAttempts, $ErrorDetail)
    Write-LogLine ("{0} soft-fail keep pending attempts={1}/{2}" -f $JobId, $attempts, $maxAttempts)
    $State.status = 'idle'
  }

  if ($attempts -ge $maxAttempts) {
    $State.status = 'error'
  }
  $State.lastId = $JobId
  $State.lastError = $ErrorDetail
  $State.updatedAt = Get-UtcNowIso
  Write-StateObject $State
}

function Invoke-OneJob {
  param(
    [Parameter(Mandatory)]$Job,
    [Parameter(Mandatory)]$State
  )

  $jobId = [string]$Job.id
  $task = [string]$Job.task
  if ([string]::IsNullOrWhiteSpace($jobId) -or ($jobId -notmatch '^[a-zA-Z0-9._-]+$')) {
    $State.status = 'error'
    $State.lastError = 'invalid id'
    $State.updatedAt = Get-UtcNowIso
    Write-StateObject $State
    Write-LogLine 'error invalid id'
    return 2
  }
  if ([string]::IsNullOrWhiteSpace($task)) {
    $State.status = 'error'
    $State.lastId = $jobId
    $State.lastError = 'empty task'
    $State.updatedAt = Get-UtcNowIso
    Write-StateObject $State
    Write-LogLine "error id=$jobId empty task"
    return 2
  }

  $timeoutSec = 300
  if ($Job.PSObject.Properties.Name -contains 'timeoutSec' -and $Job.timeoutSec) {
    try { $timeoutSec = [int]$Job.timeoutSec } catch { $timeoutSec = 300 }
  }
  if ($timeoutSec -le 0) { $timeoutSec = 300 }

  # Honor failed/{id}.STOP.txt - never revive a killed job
  $stopPath = Join-Path $FailedDir ($jobId + '.STOP.txt')
  if (Test-Path -LiteralPath $stopPath) {
    $detail = 'stopped'
    try { $detail = ((Get-Content -LiteralPath $stopPath -Raw -Encoding UTF8).Trim() -replace "[\r\n]+", ' ') } catch { }
    if ($detail.Length -gt 200) { $detail = $detail.Substring(0, 200) }
    if ($Job.PSObject.Properties.Name -contains '_pendingPath' -and $Job._pendingPath) {
      Archive-PendingJob -PendingPath $Job._pendingPath -JobId $jobId
    } elseif (Test-Path -LiteralPath (Join-Path $PendingDir ($jobId + '.json'))) {
      Archive-PendingJob -PendingPath (Join-Path $PendingDir ($jobId + '.json')) -JobId $jobId
    }
    $State.status = 'idle'
    $State.lastId = $jobId
    $State.lastError = 'stopped'
    $State.updatedAt = Get-UtcNowIso
    Write-StateObject $State
    $notify = ''
    if ($Job.PSObject.Properties.Name -contains 'notifyAgentId') { $notify = [string]$Job.notifyAgentId }
    Emit-TerminalEvent -JobId $jobId -Ok $false -Detail ('STOP: ' + $detail) -NotifyAgentId $notify
    Write-ProgressObject -JobId $jobId -Phase 'done' -Detail 'stopped'
    Write-LogLine "$jobId ok=false stopped"
    Write-Warning "job stopped: $jobId"
    return 1
  }

  # Idempotent success
  if (Test-SuccessfulOutbox -JobId $jobId) {
    if ($Job.PSObject.Properties.Name -contains '_pendingPath' -and $Job._pendingPath) {
      Archive-PendingJob -PendingPath $Job._pendingPath -JobId $jobId
    }
    $State.status = 'idle'
    $State.lastId = $jobId
    $State.lastError = $null
    $State.updatedAt = Get-UtcNowIso
    Write-StateObject $State
    Emit-TerminalEvent -JobId $jobId -Ok $true -Detail 'idempotent'
    Write-ProgressObject -JobId $jobId -Phase 'done' -Detail 'idempotent'
    Write-LogLine "$jobId ok=true exit=0 idempotent"
    Write-Host $jobId
    return 0
  }

  $State.status = 'running'
  $State.lastId = $jobId
  $State.lastError = $null
  $State.updatedAt = Get-UtcNowIso
  Write-StateObject $State
  Write-ProgressObject -JobId $jobId -Phase 'start' -Detail ("timeoutSec=" + $timeoutSec)
  try {
    if (-not (Test-Path -LiteralPath $EventsDir)) { New-Item -ItemType Directory -Path $EventsDir -Force | Out-Null }
    $startedObj = [ordered]@{ id = $jobId; at = Get-UtcNowIso; bridge = $BridgeVersion }
    $startedLine = (($startedObj | ConvertTo-Json -Compress -Depth 4) -replace "[\r\n]+", ' ')
    [System.IO.File]::WriteAllText((Join-Path $EventsDir ('started-' + $jobId + '.json')), $startedLine, [System.Text.UTF8Encoding]::new($false))
  } catch { }

  $cliSpec = 'grok'
  if ($State.PSObject.Properties.Name -contains 'cli' -and $State.cli) { $cliSpec = [string]$State.cli }
  $grokExe = Resolve-GrokCli -CliSpec $cliSpec
  if (-not $grokExe) {
    $err = 'grok CLI not found'
    $result = [pscustomobject]@{
      id       = $jobId
      ok       = $false
      exitCode = -1
      files    = @()
      notes    = ''
      error    = $err
      accept   = @()
      bridge   = $BridgeVersion
      at       = Get-UtcNowIso
    }
    Append-Jsonl -Path $OutboxPath -Object $result
    $archOut = Join-Path $ArchiveOutboxDir ($jobId + '.json')
    [System.IO.File]::WriteAllText($archOut, ($result | ConvertTo-Json -Compress -Depth 12), [System.Text.UTF8Encoding]::new($false))
    Write-LogLine "$jobId ok=false exit=-1 $err"
    Handle-SoftFail -Job $Job -JobId $jobId -State $State -ErrorDetail $err
    Write-Warning $err
    return 1
  }

  $prompt = Build-Prompt -Job $Job
  $promptForLog = $prompt
  if ($promptForLog.Length -gt 2000) {
    $promptForLog = $promptForLog.Substring(0, 2000) + '...(truncated)'
  }
  Write-LogLine ("id={0} bridge={1} prompt={2}" -f $jobId, $BridgeVersion, ($promptForLog -replace "[\r\n]+", ' '))

  $workDir = Resolve-WorkDir

  $run = Invoke-GrokWithTimeout -Exe $grokExe -Prompt $prompt -WorkingDirectory $workDir -TimeoutSec $timeoutSec -JobId $jobId -StateRef $State

  $stdout = ''
  if ($run.StdOut) { $stdout = [string]$run.StdOut }
  $stderr = ''
  if ($run.StdErr) { $stderr = [string]$run.StdErr }
  $stdoutTrim = $stdout.Trim()
  if ($stdoutTrim.Length -gt 20000) { $stdoutTrim = $stdoutTrim.Substring(0, 20000) }
  $stderrTrim = $stderr.Trim()
  if ([string]::IsNullOrWhiteSpace($stderrTrim)) { $stderrTrim = $null }

  $exitCode = [int]$run.ExitCode
  $kind = 'implement'
  if ($Job.PSObject.Properties.Name -contains 'kind' -and $Job.kind) { $kind = [string]$Job.kind }
  if ($kind -eq 'investigate') {
    $ok = ($exitCode -eq 0)
  } else {
    $ok = ($exitCode -eq 0) -and (-not [string]::IsNullOrWhiteSpace($stdoutTrim))
  }
  $files = @(Get-PathTokensFromText -Text $stdout)

  $acceptFails = @()
  if ($ok) {
    Write-ProgressObject -JobId $jobId -Phase 'accept' -Detail 'running checks'
    $acceptFails = @(Test-Acceptance -Job $Job -Result $null)
    if ($acceptFails.Count -gt 0) {
      $ok = $false
      if (-not $stderrTrim) { $stderrTrim = ($acceptFails -join '; ') }
      else { $stderrTrim = $stderrTrim + ' | accept: ' + ($acceptFails -join '; ') }
    }
  }

  $result = [pscustomobject]@{
    id       = $jobId
    ok       = [bool]$ok
    exitCode = $exitCode
    files    = $files
    notes    = $stdoutTrim
    error    = $stderrTrim
    accept   = $acceptFails
    bridge   = $BridgeVersion
    at       = Get-UtcNowIso
  }
  Append-Jsonl -Path $OutboxPath -Object $result
  Write-LogLine ("{0} ok={1} exit={2} acceptFails={3}" -f $jobId, $ok, $exitCode, $acceptFails.Count)

  if ($ok) {
    $archOut = Join-Path $ArchiveOutboxDir ($jobId + '.json')
    [System.IO.File]::WriteAllText($archOut, ($result | ConvertTo-Json -Compress -Depth 12), [System.Text.UTF8Encoding]::new($false))
    if ($Job.PSObject.Properties.Name -contains '_pendingPath' -and $Job._pendingPath) {
      Archive-PendingJob -PendingPath $Job._pendingPath -JobId $jobId
    }
    $State.status = 'idle'
    $State.lastError = $null
    $State.lastId = $jobId
    $State.updatedAt = Get-UtcNowIso
    Write-StateObject $State
    Write-ProgressObject -JobId $jobId -Phase 'done' -Detail 'ok'
    $notifyId = ''
    if ($Job.PSObject.Properties.Name -contains 'notifyAgentId' -and $Job.notifyAgentId) { $notifyId = [string]$Job.notifyAgentId }
    $outPaths = @()
    if ($Job.PSObject.Properties.Name -contains 'paths' -and $Job.paths) { $outPaths = @($Job.paths) }
    Emit-TerminalEvent -JobId $jobId -Ok $true -Paths $outPaths -Detail 'ok' -NotifyAgentId $notifyId
    Write-Host $jobId
    return 0
  }

  $errDetail = $stderrTrim
  if (-not $errDetail) { $errDetail = "grok failed exit=$exitCode" }
  $nextAttempts = (Get-JobAttempts -Job $Job) + 1
  $maxAttemptsNow = Get-JobMaxAttempts -Job $Job
  if ($nextAttempts -ge $maxAttemptsNow) {
    $archOut = Join-Path $ArchiveOutboxDir ($jobId + '.json')
    [System.IO.File]::WriteAllText($archOut, ($result | ConvertTo-Json -Compress -Depth 12), [System.Text.UTF8Encoding]::new($false))
  }
  Handle-SoftFail -Job $Job -JobId $jobId -State $State -ErrorDetail $errDetail
  return 1
}

function Invoke-BusyLockCheck {
  param(
    [Parameter(Mandatory)]$State,
    [switch]$ForceUnlock
  )
  $staleMinutes = 20
  if ($State.status -eq 'running' -and $State.updatedAt -and -not $ForceUnlock) {
    try {
      $updated = [DateTime]::Parse([string]$State.updatedAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
      if ($updated.Kind -eq [DateTimeKind]::Unspecified) {
        $updated = [DateTime]::SpecifyKind($updated, [DateTimeKind]::Utc)
      }
      $age = [DateTime]::UtcNow - $updated.ToUniversalTime()
      if ($age.TotalMinutes -lt $staleMinutes) {
        Write-Host "busy id=$($State.lastId) ageMin=$([math]::Round($age.TotalMinutes,1))"
        return $false
      }
      Write-LogLine ("stale-lock cleared ageMin={0} lastId={1}" -f [math]::Round($age.TotalMinutes,1), $State.lastId)
    } catch {
      # continue
    }
  }
  if ($ForceUnlock -and $State.status -eq 'running') {
    Write-LogLine ("force-unlock lastId={0}" -f $State.lastId)
  }
  return $true
}

function Invoke-DrainCycle {
  param(
    [Parameter(Mandatory)]$State,
    [string]$SpecificId,
    [int]$Limit
  )

  $jobs = @(Get-PendingJobs)
  if ($jobs.Count -eq 0) {
    [void](Migrate-InboxToPending)
    $jobs = @(Get-PendingJobs)
  }

  if ($SpecificId) {
    $job = $null
    foreach ($j in $jobs) {
      if ([string]$j.id -eq $SpecificId) { $job = $j; break }
    }
    if (-not $job) {
      $State.status = 'error'
      $State.lastId = $SpecificId
      $State.lastError = "job id not found in pending: $SpecificId"
      $State.updatedAt = Get-UtcNowIso
      Write-StateObject $State
      Write-LogLine "error id=$SpecificId not found in pending"
      Write-Warning "job id not found in pending: $SpecificId"
      return @{ Processed = 0; LastExit = 2; Idle = $false }
    }
    $code = Invoke-OneJob -Job $job -State $State
    return @{ Processed = 1; LastExit = $code; Idle = $false }
  }

  if ($jobs.Count -eq 0) {
    $State.status = 'idle'
    $State.lastError = 'pending empty'
    $State.updatedAt = Get-UtcNowIso
    Write-StateObject $State
    Write-ProgressObject -JobId '' -Phase 'idle' -Detail 'pending empty'
    Write-LogLine 'idle pending empty'
    Write-Host 'idle'
    return @{ Processed = 0; LastExit = 0; Idle = $true }
  }

  $processed = 0
  $lastExit = 0
  $toRun = @($jobs)
  if ($Limit -gt 0 -and $toRun.Count -gt $Limit) {
    $toRun = @($toRun | Select-Object -First $Limit)
  }

  foreach ($j in $toRun) {
    # Refresh state between jobs (busy lock already checked at start)
    $State = Read-State
    $lastExit = Invoke-OneJob -Job $j -State $State
    $processed++
  }

  return @{ Processed = $processed; LastExit = $lastExit; Idle = $false }
}

# --- main ---
Ensure-Layout
if ($PollSec -lt 2) { $PollSec = 2 }

$migrated = Migrate-InboxToPending
if ($Migrate) {
  Write-Host ("migrated=$migrated pending=" + (@(Get-ChildItem $PendingDir -Filter '*.json').Count))
  exit 0
}

$state = Read-State

# Busy lock only at start of run (-Force breaks once)
if (-not (Invoke-BusyLockCheck -State $state -ForceUnlock:$Force)) {
  exit 3
}

$limit = $MaxJobs
if ($Id) { $limit = 1 }

$cycle = Invoke-DrainCycle -State $state -SpecificId $Id -Limit $limit

if (-not $Watch) {
  exit $cycle.LastExit
}

# Watch mode: drain then poll until killed
Write-LogLine ("watch start PollSec={0} MaxJobs={1}" -f $PollSec, $MaxJobs)
while ($true) {
  if ($cycle.Idle -or $cycle.Processed -eq 0) {
    $state = Read-State
    $state.status = 'idle'
    $state.lastError = 'pending empty'
    $state.updatedAt = Get-UtcNowIso
    Write-StateObject $state
    Write-ProgressObject -JobId '' -Phase 'idle' -Detail 'watch waiting'
    Start-Sleep -Seconds $PollSec
  }

  [void](Migrate-InboxToPending)
  $state = Read-State
  # Do not re-check busy lock between wake cycles; Force already applied at start
  $cycle = Invoke-DrainCycle -State $state -SpecificId '' -Limit $MaxJobs
}