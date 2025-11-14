# Quick launcher for OpenAI Codex from current directory
# Usage: .\run-codex.ps1 [RepoPath] [-NoPush]

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$RepoPath = ".",
    
    [Parameter(Mandatory=$false)]
    [Alias("b")]
    [string]$Branch,
    
    [Parameter(Mandatory=$false)]
    [string]$Name,
    
    [Parameter(Mandatory=$false)]
    [string]$DotNetPreview,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("allow-all", "restricted", "squid", "none")]
    [string]$NetworkProxy = "allow-all",
    
    [Parameter(Mandatory=$false)]
    [string]$Cpu = "4",
    
    [Parameter(Mandatory=$false)]
    [string]$Memory = "8g",
    
    [Parameter(Mandatory=$false)]
    [string]$Gpu,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoPush,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseCurrentBranch,
    
    [Parameter(Mandatory=$false)]
    [Alias("y")]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
    Write-Host "Usage: .\run-codex.ps1 [RepoPath] [OPTIONS]"
    Write-Host ""
    Write-Host "Launch OpenAI Codex in an ephemeral container."
    Write-Host ""
    Write-Host "Arguments:"
    Write-Host "  RepoPath              Path to repository (default: current directory)"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Branch BRANCH        Branch name (creates <agent>/<branch>)"
    Write-Host "  -Name NAME            Custom container name"
    Write-Host "  -DotNetPreview CH     Install .NET preview SDK (e.g., 11.0)"
    Write-Host "  -NetworkProxy MODE    Network: allow-all, restricted, squid (default: allow-all)"
    Write-Host "  -Cpu NUM              CPU limit (default: 4)"
    Write-Host "  -Memory SIZE          Memory limit (default: 8g)"
    Write-Host "  -Gpu SPEC             GPU specification (e.g., 'all' or 'device=0')"
    Write-Host "  -NoPush               Skip auto-push to git remote on exit"
    Write-Host "  -UseCurrentBranch     Use current branch (no isolation)"
    Write-Host "  -Force                Replace existing branch without prompt"
    Write-Host "  -Help                 Show this help"
    exit 0
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\..\utils\common-functions.ps1"

if (-not (Test-DockerRunning)) { exit 1 }

try {
    $RepoPath = Resolve-Path $RepoPath -ErrorAction Stop
} catch {
    Write-Host "❌ Error: Repository path does not exist: $RepoPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path (Join-Path $RepoPath ".git"))) {
    Write-Host "❌ Error: $RepoPath is not a git repository" -ForegroundColor Red
    exit 1
}

$RepoName = Get-RepoName $RepoPath
$Branch = Get-CurrentBranch $RepoPath
$ContainerName = "codex-$RepoName-$Branch"
$WslPath = $RepoPath -replace '^([A-Z]):', { '/mnt/' + $_.Groups[1].Value.ToLower() } -replace '\\', '/'

$WslHome = wsl bash -c 'echo $HOME' 2>$null
if (-not $WslHome) {
    Write-Host "❌ Error: Could not detect WSL home directory" -ForegroundColor Red
    exit 1
}

$TimeZone = (Get-TimeZone).Id

Update-AgentImage -Agent "codex"

Write-Host "🚀 Launching OpenAI Codex..." -ForegroundColor Cyan
Write-Host "📁 Repository: $RepoName" -ForegroundColor Cyan
Write-Host "🌿 Branch: $Branch" -ForegroundColor Cyan
Write-Host "🏷️  Container: $ContainerName" -ForegroundColor Cyan
Write-Host ""

$dockerArgs = @(
    "run", "-d", "--rm",
    "--name", $ContainerName,
    "-e", "TZ=$TimeZone",
    "-e", "AGENT_SESSION_MODE=supervised",
    "-e", "AGENT_SESSION_NAME=agent",
    "-v", "${WslPath}:/workspace",
    "-v", "${WslHome}/.gitconfig:/home/agentuser/.gitconfig:ro",
    "-v", "${WslHome}/.config/gh:/home/agentuser/.config/gh:ro",
    "--label", "coding-agents.type=agent",
    "--label", "coding-agents.agent=codex",
    "--label", "coding-agents.repo=$RepoName",
    "--label", "coding-agents.branch=$Branch"
)

if ($NoPush) {
    $dockerArgs += "-e"
    $dockerArgs += "AUTO_PUSH_ON_SHUTDOWN=false"
}

if (wsl test -d "${WslHome}/.config/codex") {
    $dockerArgs += "-v"
    $dockerArgs += "${WslHome}/.config/codex:/home/agentuser/.config/codex:ro"
}

if (wsl test -f "${WslHome}/.config/coding-agents/mcp-secrets.env") {
    $dockerArgs += "-v"
    $dockerArgs += "${WslHome}/.config/coding-agents/mcp-secrets.env:/home/agentuser/.mcp-secrets.env:ro"
}

$dockerArgs += @(
    "-w", "/workspace",
    "--security-opt", "no-new-privileges:true",
    "--cpus=$Cpu",
    "--memory=$Memory"
)

if ($Gpu) {
    $dockerArgs += "--gpus=$Gpu"
}

$dockerArgs += "coding-agents-codex:local"

$containerId = & docker $dockerArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to start Codex container" -ForegroundColor Red
    exit 1
}

Write-Host "🔗 Connecting to Codex session (detach with Ctrl+B then D)..." -ForegroundColor Cyan
& docker exec -it $ContainerName agent-session attach
$attachExit = $LASTEXITCODE
if ($attachExit -ne 0) {
    if ((Get-ContainerStatus $ContainerName) -eq "running") {
        Write-Host "⚠ Unable to attach. Run .\\connect-agent.ps1 -Name $ContainerName once the container is ready." -ForegroundColor Yellow
    } else {
        Write-Host "❌ Codex session exited before it was ready." -ForegroundColor Red
    }
    exit $attachExit
}

$status = Get-ContainerStatus $ContainerName
if ($status -eq "running") {
    Write-Host ""
    Write-Host "ℹ Session detached but container is still running." -ForegroundColor Cyan
    Write-Host "   Reconnect: .\\connect-agent.ps1 -Name $ContainerName" -ForegroundColor Gray
    Write-Host "   Stop later: docker stop $ContainerName" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "✅ Codex session complete. Container stopped." -ForegroundColor Green
}
