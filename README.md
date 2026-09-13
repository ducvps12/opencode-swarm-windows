# OpenCode 3-Agent Swarm for Windows

A deliberately small orchestration layer for OpenCode on Windows: one task is fanned out to three isolated git worktrees (`ui-vfx`, `gameplay`, `qa`). Each worker gets its own branch and OpenCode session, so agents cannot overwrite one another's files in the same checkout.

## Requirements
- Git
- PowerShell 5.1+ or PowerShell 7
- OpenCode CLI available as `opencode`
- The target project must already be a git repository

## Quick start
Copy this folder anywhere, then open PowerShell **inside your project repo**:

```powershell
powershell -ExecutionPolicy Bypass -File C:\path\to\opencode-swarm-windows\swarm.ps1 `
  -Task "Add treasure chests, weapon evolution, combat VFX and regression tests"
```

By default it launches three interactive OpenCode windows. To let workers run unattended:

```powershell
powershell -ExecutionPolicy Bypass -File C:\path\to\opencode-swarm-windows\swarm.ps1 `
  -Task "Your task" -Mode headless -AutoApprove
```

`-AutoApprove` maps to OpenCode's `--auto`, so only use it in a repository you trust.

## What it creates
A sibling directory next to your repo, e.g.:

```text
mygame/
mygame-swarm/
  20260913-235500/
    wt-ui-vfx/
    wt-gameplay/
    wt-qa/
    prompts/
    logs/
    status/
    run.json
```

Each `wt-*` directory is a real git worktree on its own `swarm/<run>/<role>` branch.

## Check status
The launcher prints the exact command. Generic form:

```powershell
powershell -ExecutionPolicy Bypass -File .\status-swarm.ps1 -RunRoot "C:\...\mygame-swarm\20260913-235500"
```

## Merge when all workers are DONE

```powershell
powershell -ExecutionPolicy Bypass -File .\merge-swarm.ps1 -RunRoot "C:\...\mygame-swarm\20260913-235500"
```

Merges are sequential and stop on the first conflict. Review the combined diff before pushing.

## Cleanup

```powershell
powershell -ExecutionPolicy Bypass -File .\cleanup-swarm.ps1 -RunRoot "C:\...\mygame-swarm\20260913-235500" -DeleteBranches
```

## Configure models
Edit `swarm.config.json`. Leave `model` empty to use your normal OpenCode model. Or set a provider/model string supported by your installation.

## Project-specific test command
Set `testCommand` in `swarm.config.json`, for example:

```json
"testCommand": "npm test"
```

## Recommended use
Keep agent scopes disjoint. If both UI and gameplay workers heavily edit the same large file (for example one giant `game.js`), git can still produce merge conflicts even though their live sessions cannot overwrite each other. The long-term fix is to split shared monolith files into modules with clear ownership boundaries.
