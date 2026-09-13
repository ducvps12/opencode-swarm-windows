[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Task,

    [ValidateSet('interactive','headless')]
    [string]$Mode = '',

    [switch]$AutoApprove,
    [switch]$AllowDirty,
    [string]$BaseBranch = ''
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Config = Get-Content (Join-Path $ScriptDir 'swarm.config.json') -Raw | ConvertFrom-Json

function Exec([string]$File, [string[]]$CommandArgs, [string]$WorkingDir = '') {
    $old = Get-Location
    try {
        if ($WorkingDir) { Set-Location $WorkingDir }
        & $File $CommandArgs
        if ($LASTEXITCODE -ne 0) { throw "$File exited with code $LASTEXITCODE" }
    } finally { Set-Location $old }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git was not found in PATH.' }
if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) { throw 'opencode was not found in PATH.' }

$RepoRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
if (-not $RepoRoot) { throw 'Run swarm.ps1 from inside a git repository.' }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$RepoName = Split-Path $RepoRoot -Leaf

if (-not $AllowDirty) {
    $dirty = & git -C $RepoRoot status --porcelain
    if ($dirty) { throw 'Main worktree is dirty. Commit/stash first, or rerun with -AllowDirty (not recommended).' }
}

if (-not $BaseBranch) { $BaseBranch = (& git -C $RepoRoot branch --show-current).Trim() }
if (-not $BaseBranch) { throw 'Could not determine the current branch. Pass -BaseBranch explicitly.' }

if (-not $Mode) { $Mode = [string]$Config.defaultMode }
$UseAuto = $AutoApprove.IsPresent -or [bool]$Config.autoApprove

$RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
$Parent = Split-Path $RepoRoot -Parent
$SwarmHome = Join-Path $Parent ("{0}-swarm" -f $RepoName)
$RunRoot = Join-Path $SwarmHome $RunId
$PromptRoot = Join-Path $RunRoot 'prompts'
$LogRoot = Join-Path $RunRoot 'logs'
$StatusRoot = Join-Path $RunRoot 'status'
New-Item -ItemType Directory -Force -Path $PromptRoot,$LogRoot,$StatusRoot | Out-Null

$rolesOut = @()
foreach ($role in $Config.roles) {
    $name = [string]$role.name
    $branch = "swarm/$RunId/$name"
    $worktree = Join-Path $RunRoot ("wt-{0}" -f $name)
    $promptFile = Join-Path $PromptRoot ("{0}.md" -f $name)
    $rolePromptPath = Join-Path $ScriptDir ([string]$role.promptFile)
    $rolePrompt = Get-Content $rolePromptPath -Raw
    $fullPrompt = @"
$rolePrompt

# SHARED TASK
$Task

# BASELINE
- Base branch: $BaseBranch
- Role branch: $branch
- Worktree: $worktree

Do the work now. Do not just propose steps. Inspect files, edit, and verify.
"@
    Set-Content -Path $promptFile -Value $fullPrompt -Encoding UTF8

    Write-Host "[+] Creating $name -> $branch" -ForegroundColor Cyan
    Exec git @('-C',$RepoRoot,'worktree','add','-b',$branch,$worktree,$BaseBranch)

    $launcher = Join-Path $RunRoot ("launch-{0}.ps1" -f $name)
    $log = Join-Path $LogRoot ("{0}.log" -f $name)
    $status = Join-Path $StatusRoot ("{0}.txt" -f $name)
    $model = [string]$role.model

    $launcherBody = @'
param($Worktree,$PromptFile,$LogFile,$StatusFile,$Mode,$UseAuto,$Model,$RoleName)
$ErrorActionPreference='Continue'
Set-Content $StatusFile 'RUNNING'
$prompt = Get-Content $PromptFile -Raw
Set-Location $Worktree
try {
    if ($Mode -eq 'headless') {
        $args = @('run','--dir',$Worktree)
        if ($UseAuto -eq 'True') { $args += '--auto' }
        if ($Model) { $args += @('--model',$Model) }
        $args += $prompt
        & opencode @args 2>&1 | Tee-Object -FilePath $LogFile
    } else {
        $args = @($Worktree,'--prompt',$prompt)
        if ($UseAuto -eq 'True') { $args += '--auto' }
        if ($Model) { $args += @('--model',$Model) }
        & opencode @args 2>&1 | Tee-Object -FilePath $LogFile
    }

    git add -A
    $changes = git status --porcelain
    if ($changes) {
        git commit -m "swarm($RoleName): complete assigned task"
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
    }
    Set-Content $StatusFile 'DONE'
} catch {
    $_ | Out-String | Tee-Object -FilePath $LogFile -Append
    Set-Content $StatusFile ('FAILED: ' + $_.Exception.Message)
    exit 1
}
'@
    Set-Content -Path $launcher -Value $launcherBody -Encoding UTF8

    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,
              '-Worktree',$worktree,'-PromptFile',$promptFile,'-LogFile',$log,
              '-StatusFile',$status,'-Mode',$Mode,'-UseAuto',([string]$UseAuto),
              '-Model',$model,'-RoleName',$name)

    Write-Host "[>] Launching $name ($Mode)" -ForegroundColor Green
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args | Out-Null

    $rolesOut += [pscustomobject]@{name=$name;branch=$branch;worktree=$worktree;prompt=$promptFile;log=$log;status=$status}
}

$runInfo = [pscustomobject]@{
    runId=$RunId
    repoRoot=$RepoRoot
    repoName=$RepoName
    baseBranch=$BaseBranch
    task=$Task
    mode=$Mode
    autoApprove=$UseAuto
    roles=$rolesOut
}
$runInfo | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $RunRoot 'run.json') -Encoding UTF8

Write-Host ''
Write-Host 'Swarm launched.' -ForegroundColor Green
Write-Host "Run root: $RunRoot"
Write-Host "Status:   powershell -ExecutionPolicy Bypass -File `"$ScriptDir\status-swarm.ps1`" -RunRoot `"$RunRoot`""
Write-Host "Merge:    powershell -ExecutionPolicy Bypass -File `"$ScriptDir\merge-swarm.ps1`" -RunRoot `"$RunRoot`""
