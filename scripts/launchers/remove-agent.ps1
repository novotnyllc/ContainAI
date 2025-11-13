# Remove agent container with optional auto-push

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$ContainerName,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoPush,
    
    [Parameter(Mandatory=$false)]
    [switch]$KeepBranch,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\..\utils\common-functions.ps1"

if ($Help) {
    Write-Host "Usage: remove-agent.ps1 <container-name> [-NoPush] [-KeepBranch]"
    Write-Host ""
    Write-Host "Remove an agent container and its associated resources."
    Write-Host "Automatically pushes changes to local remote before removal."
    Write-Host "Cleans up the agent branch in the host repository (unless -KeepBranch is used)."
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -NoPush       Skip git push before removal"
    Write-Host "  -KeepBranch   Don't delete the agent branch from host repo"
    Write-Host "  -Help         Show this help"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\remove-agent.ps1 copilot-myrepo-main"
    Write-Host "  .\remove-agent.ps1 codex-myapp-feature -NoPush"
    Write-Host "  .\remove-agent.ps1 claude-project-dev -KeepBranch"
    exit 0
}

# Check arguments
if (-not $ContainerName) {
    Write-Host "❌ Error: Container name required" -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage: remove-agent.ps1 <container-name> [-NoPush]"
    Write-Host ""
    Write-Host "Available containers:"
    docker ps -a --filter "label=coding-agents.type=agent" --format "  • {{.Names}}" 2>$null
    exit 1
}

# Validate container name
if (-not (Test-ValidContainerName $ContainerName)) {
    Write-Host "❌ Error: Invalid container name: $ContainerName" -ForegroundColor Red
    Write-Host "   Container names must start with alphanumeric and contain only: a-z, A-Z, 0-9, _, ., -" -ForegroundColor Yellow
    exit 1
}

# Check Docker
if (-not (Test-DockerRunning)) { exit 1 }

# Remove container and optionally clean up branch
Remove-ContainerWithSidecars -ContainerName $ContainerName -SkipPush:$NoPush -KeepBranch:$KeepBranch
