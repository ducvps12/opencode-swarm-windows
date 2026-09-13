[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [switch]$SkipTests
)
$ErrorActionPreference='Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$config = Get-Content (Join-Path $ScriptDir 'swarm.config.json') -Raw | ConvertFrom-Json
$info = Get-Content (Join-Path $RunRoot 'run.json') -Raw | ConvertFrom-Json
$repo = [string]$info.repoRoot
$base = [string]$info.baseBranch

$dirty = & git -C $repo status --porcelain
if ($dirty) { throw 'Main worktree is dirty. Commit/stash before merging swarm branches.' }

& git -C $repo switch $base
if ($LASTEXITCODE -ne 0) { throw "Could not switch to $base" }

foreach ($r in $info.roles) {
    $state = if (Test-Path $r.status) { (Get-Content $r.status -Raw).Trim() } else { 'PENDING' }
    if ($state -ne 'DONE') { throw "Role $($r.name) is not DONE ($state). Refusing to merge." }
    Write-Host "[+] Merging $($r.branch)" -ForegroundColor Cyan
    & git -C $repo merge --no-ff $r.branch -m "merge swarm role $($r.name) [$($info.runId)]"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Merge conflict while merging $($r.name). Resolve manually or run: git -C `"$repo`" merge --abort" -ForegroundColor Red
        exit 1
    }
}

if (-not $SkipTests -and [string]$config.testCommand) {
    Write-Host "[>] Running test command: $($config.testCommand)" -ForegroundColor Yellow
    Push-Location $repo
    try {
        Invoke-Expression ([string]$config.testCommand)
        if ($LASTEXITCODE -ne 0) { throw 'Test command failed after merge.' }
    } finally { Pop-Location }
}

Write-Host 'Merged all DONE swarm branches.' -ForegroundColor Green
Write-Host 'Review the combined diff before pushing.'
