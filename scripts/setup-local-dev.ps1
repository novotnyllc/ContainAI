#!/usr/bin/env pwsh
<#!
.SYNOPSIS
    Installs ContainAI launchers on Windows hosts.
.DESCRIPTION
    Ensures WSL is available, runs prerequisite & health checks inside WSL,
    and adds host\launchers\entrypoints to the user's PATH so channel-specific
    commands (run-copilot-dev / run-copilot / run-copilot-nightly) are available
    from any PowerShell prompt.
#>
[CmdletBinding()]
param(
    [switch]$SkipChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent $ScriptRoot
$LaunchersPath = Join-Path $RepoRoot 'host\launchers\entrypoints'

if (-not (Test-Path -LiteralPath $LaunchersPath)) {
    throw "Launchers directory not found: $LaunchersPath"
}

. (Join-Path $RepoRoot 'host\utils\wsl-shim.ps1')

function Invoke-WslScript {
    param(
        [Parameter(Mandatory)] [string]$RelativePath,
        [Parameter(Mandatory)] [string]$Description
    )

    Write-Output "Running $Description..."
    $code = Invoke-ContainAIWslScript -ScriptRelativePath $RelativePath
    if ($code -ne 0) {
        throw "❌ $Description failed. Resolve the errors above and rerun scripts\\install.ps1."
    }
    Write-Output "✅ $Description passed."
}

function Get-NormalizedPathValue {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try {
        return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\')
    } catch {
        return $Path.TrimEnd('\')
    }
}

function Test-PathInList {
    param(
        [string]$Candidate,
        [string]$PathList
    )

    $normalizedCandidate = Get-NormalizedPathValue $Candidate
    if ([string]::IsNullOrEmpty($normalizedCandidate)) { return $false }
    foreach ($entry in ($PathList -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if (Get-NormalizedPathValue $entry -ieq $normalizedCandidate) {
            return $true
        }
    }
    return $false
}

function Set-LaunchersOnPath {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$PathToAdd)

    if (-not $PSCmdlet.ShouldProcess($PathToAdd, "Add to user PATH")) { return }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Test-PathInList -Candidate $PathToAdd -PathList $userPath)) {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
            $PathToAdd
        } else {
            "$PathToAdd;$userPath"
        }
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        Write-Output "✓ Added $PathToAdd to your User PATH."
    } else {
        Write-Output "✓ Launchers already present in User PATH."
    }

    if (-not (Test-PathInList -Candidate $PathToAdd -PathList $env:Path)) {
        $env:Path = "$PathToAdd;$env:Path"
        Write-Output "✓ Updated current session PATH."
    }
}

Write-Output "Installing ContainAI launchers..."
if ($SkipChecks) {
    Write-Output "Skipping prerequisite and health checks (--SkipChecks)."
} else {
    Invoke-WslScript -RelativePath 'host/utils/verify-prerequisites.sh' -Description 'Prerequisite verification'
    Invoke-WslScript -RelativePath 'host/utils/check-health.sh' -Description 'System health check'
}

Set-LaunchersOnPath -PathToAdd $LaunchersPath

Write-Output "`nLaunchers installed."
Write-Output "You can now run the channel-specific launchers from host\\launchers\\entrypoints (e.g., run-copilot-dev in repo clones, run-copilot for prod bundles, run-copilot-nightly for nightly smoke)."
Write-Output "Open a new terminal (or run 'refreshenv' if using Scoop/Chocolatey) so the updated PATH takes effect everywhere."
