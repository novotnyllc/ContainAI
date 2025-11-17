# List all active agent containers

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\..\utils\common-functions.ps1"

# Check container runtime
if (-not (Test-DockerRunning)) { exit 1 }
$containerCli = Get-ContainerCli

Write-Output "🤖 Active Agent Containers"
Write-Output ""

# Get all agent containers
$containers = Invoke-ContainerCli ps -a --filter "label=coding-agents.type=agent" --format "{{.Names}}" 2>$null

if (-not $containers) {
    Write-Output "No agent containers found"
    Write-Output ""
    Write-Output "Launch an agent with:"
    Write-Output "  run-copilot      # Quick launch in current directory"
    Write-Output "  launch-agent     # Advanced launch with options"
    exit 0
}

# Print header
Write-Output ("{0,-30} {1,-15} {2,-20} {3,-30}" -f "NAME", "STATUS", "AGENT", "BRANCH")
Write-Output ("-" * 100)

# List each container
foreach ($container in $containers) {
    $status = Get-ContainerStatus $container
    $agent = Invoke-ContainerCli inspect -f '{{ index .Config.Labels "coding-agents.agent" }}' $container 2>$null
    if (-not $agent) { $agent = "unknown" }
    $branch = Invoke-ContainerCli inspect -f '{{ index .Config.Labels "coding-agents.branch" }}' $container 2>$null
    if (-not $branch) { $branch = "unknown" }
    $repo = Invoke-ContainerCli inspect -f '{{ index .Config.Labels "coding-agents.repo" }}' $container 2>$null
    if (-not $repo) { $repo = "unknown" }
    
    # Color code status
    $statusDisplay = switch ($status) {
        "running" { "🟢 running" }
        "exited" { "🔴 stopped" }
        default { "⚪ $status" }
    }
    
    Write-Output ("{0,-30} {1,-15} {2,-20} {3,-30}" -f $container, $statusDisplay, $agent, $branch)
}

Write-Output ""
Write-Output "📋 Management Commands:"
Write-Output "  $containerCli exec -it <name> bash     # Connect to container"
Write-Output "  remove-agent <name>             # Remove container (with auto-push)"
Write-Output "  remove-agent <name> --no-push   # Remove without pushing"
