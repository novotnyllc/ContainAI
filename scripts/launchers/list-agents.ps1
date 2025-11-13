# List all active agent containers

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\..\utils\common-functions.ps1"

# Check Docker
if (-not (Test-DockerRunning)) { exit 1 }

Write-Host "🤖 Active Agent Containers" -ForegroundColor Cyan
Write-Host ""

# Get all agent containers
$containers = docker ps -a --filter "label=coding-agents.type=agent" --format "{{.Names}}" 2>$null

if (-not $containers) {
    Write-Host "No agent containers found"
    Write-Host ""
    Write-Host "Launch an agent with:"
    Write-Host "  run-copilot      # Quick launch in current directory"
    Write-Host "  launch-agent     # Advanced launch with options"
    exit 0
}

# Print header
Write-Host ("{0,-30} {1,-15} {2,-20} {3,-30}" -f "NAME", "STATUS", "AGENT", "BRANCH") -ForegroundColor White
Write-Host ("-" * 100)

# List each container
foreach ($container in $containers) {
    $status = Get-ContainerStatus $container
    $agent = docker inspect -f '{{ index .Config.Labels "coding-agents.agent" }}' $container 2>$null
    if (-not $agent) { $agent = "unknown" }
    $branch = docker inspect -f '{{ index .Config.Labels "coding-agents.branch" }}' $container 2>$null
    if (-not $branch) { $branch = "unknown" }
    $repo = docker inspect -f '{{ index .Config.Labels "coding-agents.repo" }}' $container 2>$null
    if (-not $repo) { $repo = "unknown" }
    
    # Color code status
    $statusDisplay = switch ($status) {
        "running" { "🟢 running"; $color = "Green" }
        "exited" { "🔴 stopped"; $color = "Red" }
        default { "⚪ $status"; $color = "Gray" }
    }
    
    Write-Host ("{0,-30} {1,-15} {2,-20} {3,-30}" -f $container, $statusDisplay, $agent, $branch) -ForegroundColor $color
}

Write-Host ""
Write-Host "📋 Management Commands:" -ForegroundColor Cyan
Write-Host "  docker exec -it <name> bash     # Connect to container"
Write-Host "  remove-agent <name>             # Remove container (with auto-push)"
Write-Host "  remove-agent <name> --no-push   # Remove without pushing"
