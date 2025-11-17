# Quick launcher for GitHub Copilot from the current directory
# Usage: .\run-copilot.ps1 [RepoPath] [OPTIONS]
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
    @(
        "Usage: .\run-copilot.ps1 [RepoPath] [OPTIONS]",
        "",
        "Launch GitHub Copilot CLI in an ephemeral container.",
        "",
        "Options mirror run-agent; see docs/cli-reference.md for details.",
        "Example: .\run-copilot.ps1 -Branch feature/api"
    ) | ForEach-Object { Write-Output $_ }
    exit 0
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunAgent = Join-Path $ScriptDir "run-agent.ps1"

$argsList = @('-Agent', 'copilot', '-Source', $RepoPath)
if ($PSBoundParameters.ContainsKey('Branch')) { $argsList += @('-Branch', $Branch) }
if ($PSBoundParameters.ContainsKey('Name')) { $argsList += @('-Name', $Name) }
if ($PSBoundParameters.ContainsKey('DotNetPreview')) { $argsList += @('-DotNetPreview', $DotNetPreview) }
if ($PSBoundParameters.ContainsKey('NetworkProxy')) { $argsList += @('-NetworkProxy', $NetworkProxy) }
if ($PSBoundParameters.ContainsKey('Cpu')) { $argsList += @('-Cpu', $Cpu) }
if ($PSBoundParameters.ContainsKey('Memory')) { $argsList += @('-Memory', $Memory) }
if ($PSBoundParameters.ContainsKey('Gpu')) { $argsList += @('-Gpu', $Gpu) }
if ($NoPush) { $argsList += '-NoPush' }
if ($UseCurrentBranch) { $argsList += '-UseCurrentBranch' }
if ($Force) { $argsList += '-Force' }

& $RunAgent @argsList
exit $LASTEXITCODE
