# Remove agent container with optional auto-push

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$ContainerName,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoPush,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\..\utils\common-functions.ps1"

if ($Help) {
    Write-Host "Usage: remove-agent.ps1 <container-name> [-NoPush]"
    Write-Host ""
    Write-Host "Remove an agent container and its associated resources."
    Write-Host "Automatically pushes changes to local remote before removal."
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -NoPush    Skip git push before removal"
    Write-Host "  -Help      Show this help"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\remove-agent.ps1 copilot-myrepo-main"
    Write-Host "  .\remove-agent.ps1 codex-myapp-feature -NoPush"
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

# Check Docker
if (-not (Test-DockerRunning)) { exit 1 }

# Remove container
Remove-ContainerWithSidecars -ContainerName $ContainerName -SkipPush:$NoPush
