#Requires -Version 5.1
<#
.SYNOPSIS
  End-to-end test of the OTC Bus with a stand-in grok CLI. No model calls, no network.
.DESCRIPTION
  Copies the bus scripts into a temporary folder, points state.json at a stand-in
  "grok" script, and checks: happy path, approval flag handling, no retry on
  quota / usage-limit / HTTP 429 output, retry backoff, and status output.
  Runs on Windows PowerShell 5.1 and PowerShell 7 (Windows, Linux, macOS).
.EXAMPLE
  pwsh -NoProfile -File .\bus\tests\e2e.ps1
#>
[CmdletBinding()]
param([switch]$Keep)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$busSrc = Split-Path -Parent $PSScriptRoot
$root = Join-Path ([IO.Path]::GetTempPath()) ('otc-bus-e2e-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$bus = Join-Path $root 'bus'
$work = Join-Path $root 'work'
New-Item -ItemType Directory -Path $bus, $work -Force | Out-Null
Get-ChildItem -LiteralPath $busSrc -Filter 'otc-*.ps1' -File | Copy-Item -Destination $bus

# Stand-in grok: records its arguments and working directory, behaves per FAKE_GROK_MODE.
$argsFile = Join-Path $root 'grok-args.txt'
$cwdFile = Join-Path $root 'grok-cwd.txt'
$fake = Join-Path $root 'fake-grok.ps1'
@"
[IO.File]::WriteAllLines('$argsFile', [string[]]@(`$args))
[IO.File]::WriteAllText('$cwdFile', (Get-Location).Path)
switch (`$env:FAKE_GROK_MODE) {
  '429'   { Write-Error 'Error: HTTP 429 Too Many Requests - rate limit exceeded'; exit 1 }
  'quota' { 'You have reached your usage limit for this plan.'; exit 2 }
  'boom'  { Write-Error 'unexpected failure'; exit 1 }
  default { 'hello'; exit 0 }
}
"@ | Set-Content -LiteralPath $fake -Encoding ASCII
([ordered]@{ root = $bus; status = 'idle'; lastId = $null; lastError = $null; cli = $fake; bridge = ''; updatedAt = $null } | ConvertTo-Json -Compress) | Set-Content -LiteralPath (Join-Path $bus 'state.json') -Encoding ASCII

$script:fail = 0
function Check([string]$Name, [bool]$Cond) {
  if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name"; $script:fail++ }
}
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Get-GrokArgs { @(Get-Content -LiteralPath $argsFile) }

$savedApproval = $env:OTC_GROK_APPROVAL_ARGS
Remove-Item Env:OTC_GROK_APPROVAL_ARGS -ErrorAction SilentlyContinue
Push-Location $bus
try {
  $pending = Join-Path $bus 'pending'; $failed = Join-Path $bus 'failed'

  # 1. Happy path, default approval flag, -WorkDir, notifyAgentId on the terminal event
  $env:FAKE_GROK_MODE = 'ok'
  .\otc-enqueue.ps1 -Id ok-1 -Kind investigate -Task 'Reply with exactly: hello' -NotifyAgentId coordinator | Out-Null
  .\otc-bridge.ps1 -WorkDir $work | Out-Null; $code = $LASTEXITCODE
  .\otc-wait.ps1 -Id ok-1 -TimeoutSec 5 | Out-Null; $wcode = $LASTEXITCODE
  Check 'happy path: bridge and wait exit 0' ($code -eq 0 -and $wcode -eq 0)
  Check 'default approval flag is --always-approve' ((Get-GrokArgs)[0] -eq '--always-approve')
  Check '-WorkDir honored' ((Get-Content -LiteralPath $cwdFile -Raw).Trim() -eq (Resolve-Path $work).Path)
  Check 'terminal event carries notifyAgentId' ((Read-Json (Join-Path $bus 'events/terminal-ok-1.json')).notifyAgentId -eq 'coordinator')

  # 2. Approval flags from the environment (JSON array) and from the parameter
  $env:OTC_GROK_APPROVAL_ARGS = '["--permission-mode","dontAsk","--allow","Bash(git *)","--sandbox","workspace"]'
  .\otc-enqueue.ps1 -Id ok-2 -Kind investigate -Task 'hi' | Out-Null; .\otc-bridge.ps1 | Out-Null
  $a = Get-GrokArgs
  Check 'OTC_GROK_APPROVAL_ARGS passed intact' ($a[0] -eq '--permission-mode' -and $a[3] -eq 'Bash(git *)' -and $a[5] -eq 'workspace' -and ($a -notcontains '--always-approve'))
  .\otc-enqueue.ps1 -Id ok-3 -Kind investigate -Task 'hi' | Out-Null; .\otc-bridge.ps1 -ApprovalArgs '--sandbox', 'strict' | Out-Null
  $a = Get-GrokArgs
  Check '-ApprovalArgs overrides the environment' ($a[0] -eq '--sandbox' -and $a[1] -eq 'strict' -and ($a -notcontains 'dontAsk'))
  Remove-Item Env:OTC_GROK_APPROVAL_ARGS

  # 3. HTTP 429 / rate-limit output: never retried
  $env:FAKE_GROK_MODE = '429'
  .\otc-enqueue.ps1 -Id rl-429 -Kind investigate -Task 'hi' -MaxAttempts 3 | Out-Null; .\otc-bridge.ps1 | Out-Null
  $f429 = Join-Path $failed 'rl-429.json'
  Check '429: moved straight to failed/' ((Test-Path $f429) -and -not (Test-Path (Join-Path $pending 'rl-429.json')))
  Check '429: exactly one attempt' ((Test-Path $f429) -and (Read-Json $f429).attempts -eq 1)
  Check '429: clear lastError' ((Read-Json (Join-Path $bus 'state.json')).lastError -like 'usage/rate limit*not retried*')
  Check '429: failed terminal event' ((Read-Json (Join-Path $bus 'events/terminal-rl-429.json')).ok -eq $false)
  .\otc-wait.ps1 -Id rl-429 -TimeoutSec 3 | Out-Null
  Check '429: otc-wait exits 1' ($LASTEXITCODE -eq 1)

  # 4. Usage-limit text on stdout: never retried
  $env:FAKE_GROK_MODE = 'quota'
  .\otc-enqueue.ps1 -Id rl-quota -Kind investigate -Task 'hi' -MaxAttempts 3 | Out-Null; .\otc-bridge.ps1 | Out-Null
  Check 'usage limit: moved straight to failed/' ((Test-Path (Join-Path $failed 'rl-quota.json')) -and -not (Test-Path (Join-Path $pending 'rl-quota.json')))

  # 5. Ordinary failure: retried, but only after a backoff
  $env:FAKE_GROK_MODE = 'boom'
  .\otc-enqueue.ps1 -Id soft-1 -Kind investigate -Task 'hi' -MaxAttempts 2 | Out-Null; .\otc-bridge.ps1 | Out-Null
  $p = Join-Path $pending 'soft-1.json'
  Check 'soft fail: stays pending with attempts=1 and retryAfter' ((Test-Path $p) -and (Read-Json $p).attempts -eq 1 -and (Read-Json $p).retryAfter)
  $out = .\otc-bridge.ps1 6>&1 | Out-String
  Check 'soft fail: run inside the backoff window skips the job' ((Test-Path $p) -and (Read-Json $p).attempts -eq 1 -and $out -match 'retry backoff')
  .\otc-bridge.ps1 -Id soft-1 | Out-Null
  Check 'soft fail: explicit -Id runs now and exhausts to failed/' ((Test-Path (Join-Path $failed 'soft-1.json')) -and -not (Test-Path $p))

  # 6. Status
  $s = .\otc-status.ps1 | ConvertFrom-Json
  Check 'status: bridge 2.0.0, 3 failed, 0 pending' ($s.bridge -eq '2.0.0' -and $s.failed -eq 3 -and $s.pending -eq 0)
} finally {
  Pop-Location
  Remove-Item Env:FAKE_GROK_MODE -ErrorAction SilentlyContinue
  if ($null -ne $savedApproval) { $env:OTC_GROK_APPROVAL_ARGS = $savedApproval }
  if (-not $Keep) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Output "kept: $root" }
}
Write-Output ("failures={0}" -f $script:fail)
exit $script:fail
