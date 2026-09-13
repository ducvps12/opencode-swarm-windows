[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [switch]$DeleteBranches
)
$ErrorActionPreference='Stop'
$info = Get-Content (Join-Path $RunRoot 'run.json') -Raw | ConvertFrom-Json
$repo = [string]$info.repoRoot
foreach ($r in $info.roles) {
    if (Test-Path $r.worktree) {
        if ($PSCmdlet.ShouldProcess($r.worktree,'git worktree remove')) {
            & git -C $repo worktree remove $r.worktree
        }
    }
    if ($DeleteBranches) {
        if ($PSCmdlet.ShouldProcess($r.branch,'git branch -d')) {
            & git -C $repo branch -d $r.branch
        }
    }
}
& git -C $repo worktree prune
Write-Host 'Cleanup complete.'
