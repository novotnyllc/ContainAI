#!/usr/bin/env pwsh
<#!
.SYNOPSIS
    Installs CodingAgents launchers on Windows hosts.
.DESCRIPTION
    Ensures WSL is available, runs prerequisite & health checks inside WSL,
    and adds host\launchers to the user's PATH so commands like run-copilot
    are available from any PowerShell prompt.
#>
[CmdletBinding()]
param(
    [switch]$SkipChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent $ScriptRoot
$LaunchersPath = Join-Path $RepoRoot 'host\launchers'

if (-not (Test-Path -LiteralPath $LaunchersPath)) {
    throw "Launchers directory not found: $LaunchersPath"
}

. (Join-Path $RepoRoot 'host\utils\wsl-shim.ps1')

function Invoke-WslScript {
    param(
        [Parameter(Mandatory)] [string]$RelativePath,
        [Parameter(Mandatory)] [string]$Description
    )

    Write-Host "Running $Description..." -ForegroundColor Cyan
    $code = Invoke-CodingAgentsWslScript -ScriptRelativePath $RelativePath
    if ($code -ne 0) {
        throw "❌ $Description failed. Resolve the errors above and rerun scripts\\install.ps1."
    }
    Write-Host "✅ $Description passed." -ForegroundColor Green
}

function Normalize-PathValue {
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

    $normalizedCandidate = Normalize-PathValue $Candidate
    if ([string]::IsNullOrEmpty($normalizedCandidate)) { return $false }
    foreach ($entry in ($PathList -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if (Normalize-PathValue $entry -ieq $normalizedCandidate) {
            return $true
        }
    }
    return $false
}

function Ensure-LaunchersOnPath {
    param([string]$PathToAdd)

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Test-PathInList -Candidate $PathToAdd -PathList $userPath)) {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
            $PathToAdd
        } else {
            "$PathToAdd;$userPath"
        }
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        Write-Host "✓ Added $PathToAdd to your User PATH." -ForegroundColor Green
    } else {
        Write-Host "✓ Launchers already present in User PATH." -ForegroundColor DarkGray
    }

    if (-not (Test-PathInList -Candidate $PathToAdd -PathList $env:Path)) {
        $env:Path = "$PathToAdd;$env:Path"
        Write-Host "✓ Updated current session PATH." -ForegroundColor DarkGray
    }
}

Write-Host "Installing CodingAgents launchers..." -ForegroundColor Cyan
if ($SkipChecks) {
    Write-Host "Skipping prerequisite and health checks (--SkipChecks)." -ForegroundColor Yellow
} else {
    Invoke-WslScript -RelativePath 'host/utils/verify-prerequisites.sh' -Description 'Prerequisite verification'
    Invoke-WslScript -RelativePath 'host/utils/check-health.sh' -Description 'System health check'
}

Ensure-LaunchersOnPath -PathToAdd $LaunchersPath

Write-Host "`nLaunchers installed." -ForegroundColor Green
Write-Host "You can now run 'run-copilot', 'run-codex', 'run-claude', etc. from any PowerShell prompt." -ForegroundColor Green
Write-Host "Open a new terminal (or run 'refreshenv' if using Scoop/Chocolatey) so the updated PATH takes effect everywhere." -ForegroundColor Yellow
