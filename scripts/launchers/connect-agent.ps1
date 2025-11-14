[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$Name,

    [Parameter(Mandatory=$false)]
    [switch]$Help
)

if ($Help) {
    Write-Host "Usage: .\connect-agent.ps1 [-Name container]" 
    Write-Host ""
    Write-Host "Attach to a running coding agent container via the managed tmux session." 
    Write-Host "If -Name is omitted, connect-agent will attach to the only running agent container." 
    Write-Host "Use list-agents.ps1 to see active containers."
    return
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\..\utils\common-functions.ps1"

$containerCmd = Get-ContainerRuntime
if (-not $containerCmd) {
    Write-Host "❌ Could not detect a container runtime (docker or podman)." -ForegroundColor Red
    exit 1
}

function Get-RunningAgentContainers {
    param()
    $result = & $containerCmd ps --filter "label=coding-agents.type=agent" --format "{{.Names}}"
    if ([string]::IsNullOrWhiteSpace($result)) {
        return @()
    }
    return ($result -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

if (-not $Name) {
    $running = Get-RunningAgentContainers
    if ($running.Count -eq 0) {
        Write-Host "No running agent containers found. Launch one with run-<agent> or launch-agent." -ForegroundColor Yellow
        exit 1
    }
    if ($running.Count -gt 1) {
        Write-Host "Multiple agent containers detected. Specify one of:" -ForegroundColor Yellow
        $running | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    $Name = $running[0]
}

if (-not (Test-ContainerExists -ContainerName $Name)) {
    Write-Host "Container '$Name' does not exist." -ForegroundColor Red
    exit 1
}

if ((Get-ContainerStatus -ContainerName $Name) -ne "running") {
    Write-Host "Container '$Name' is not running." -ForegroundColor Red
    exit 1
}

# Check for agent-session helper
& $containerCmd exec $Name /bin/bash -c 'command -v agent-session >/dev/null 2>&1' | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "agent-session helper not found. Opening a regular bash shell (no detach support)." -ForegroundColor Yellow
    & $containerCmd exec -it $Name bash
    exit $LASTEXITCODE
}

Write-Host "Attaching to $Name (detach with Ctrl+B then D)..." -ForegroundColor Cyan
& $containerCmd exec -it $Name agent-session attach
exit $LASTEXITCODE
