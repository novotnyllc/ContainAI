#!/usr/bin/env pwsh
[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\..\host\utils\wsl-shim.ps1")

# Skip if no WSL distribution is available (e.g., Windows CI without WSL configured)
if (-not $script:RunningOnLinux -and -not $script:WslDistributionAvailable) {
    Write-Host "⏭️  Skipping test-config.ps1: No WSL distribution is installed" -ForegroundColor Yellow
    exit 0
}

$exitCode = Invoke-ContainAIWslScript -ScriptRelativePath "scripts\test\test-config.sh" -Arguments $Arguments
exit $exitCode
