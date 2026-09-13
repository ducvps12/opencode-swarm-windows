[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunRoot)
$infoPath = Join-Path $RunRoot 'run.json'
if (-not (Test-Path $infoPath)) { throw "run.json not found under $RunRoot" }
$info = Get-Content $infoPath -Raw | ConvertFrom-Json
$rows = foreach ($r in $info.roles) {
    $state = if (Test-Path $r.status) { (Get-Content $r.status -Raw).Trim() } else { 'PENDING' }
    $head = (& git -C $r.worktree log -1 --pretty='%h %s' 2>$null)
    [pscustomobject]@{Role=$r.name;State=$state;Branch=$r.branch;LastCommit=$head;Log=$r.log}
}
$rows | Format-Table -AutoSize
