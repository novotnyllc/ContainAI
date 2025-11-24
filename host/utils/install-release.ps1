#!/usr/bin/env pwsh
<#!
.SYNOPSIS
Thin PowerShell shim that delegates ContainAI installs to the canonical Bash installer via WSL.

.DESCRIPTION
Keeps installer logic in one place (host/utils/install-release.sh). Performs minimal validation and WSL path conversion, then executes the Bash script with the provided arguments.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$Repo = $env:GITHUB_REPOSITORY,
    [string]$InstallRoot = "/opt/containai",
    [string]$AssetDir,
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InstallerSelfSha256 = "__INSTALLER_SELF_SHA256__"

function Assert-SelfIntegrity {
    if ($InstallerSelfSha256 -eq "__INSTALLER_SELF_SHA256__") { throw "Installer self-hash not injected; repackage artifacts." }
    $content = Get-Content -Raw -LiteralPath $MyInvocation.MyCommand.Path
    $redacted = [regex]::Replace($content, 'InstallerSelfSha256="[^"]*"', 'InstallerSelfSha256="__REDACTED__"')
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($redacted)
    $computed = ($hasher.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
    if ($computed -ne $InstallerSelfSha256.ToLower()) {
        throw "Installer integrity check failed; expected $InstallerSelfSha256 got $computed"
    }
}

Assert-SelfIntegrity

. "$PSScriptRoot/wsl-shim.ps1"

if (-not $Repo) { throw "--Repo or GITHUB_REPOSITORY env is required" }

$wslInstallRoot = Convert-ToWslPath -Path $InstallRoot

$argsList = @("--version", $Version, "--install-root", $wslInstallRoot, "--repo", $Repo)
if ($AssetDir) { $argsList += @("--asset-dir", (Convert-ToWslPath -Path $AssetDir)) }
if ($VerifyOnly) { $argsList += "--verify-only" }

$exitCode = Invoke-ContainAIWslScript -ScriptRelativePath "host/utils/install-release.sh" -Arguments $argsList
if ($exitCode -ne 0) { exit $exitCode }

if (-not $VerifyOnly) {
    $wslExe = Get-WslExecutablePath
    if ($null -ne $wslExe) {
        $launchersWsl = "$wslInstallRoot/current/host/launchers/entrypoints"
        $utilsWsl = "$wslInstallRoot/current/host/utils"

        $launchersWin = (& $wslExe wslpath -w $launchersWsl 2>&1).Trim()
        $utilsWin = (& $wslExe wslpath -w $utilsWsl 2>&1).Trim()

        if ([string]::IsNullOrWhiteSpace($launchersWin) -or [string]::IsNullOrWhiteSpace($utilsWin)) {
            Write-Warning "Could not translate WSL install paths to Windows paths; PATH update skipped."
        } else {
            $shimRoot = Join-Path $env:LOCALAPPDATA "ContainAI"
            $shimLaunchers = Join-Path $shimRoot "host\launchers\entrypoints"
            $shimUtils = Join-Path $shimRoot "host\utils"

            New-Item -ItemType Directory -Force -Path $shimLaunchers | Out-Null
            New-Item -ItemType Directory -Force -Path $shimUtils | Out-Null

            try {
                Copy-Item -Recurse -Force -Filter *.ps1 -Path (Join-Path $launchersWin '*') -Destination $shimLaunchers
                Copy-Item -Recurse -Force -Filter *.ps1 -Path (Join-Path $utilsWin '*') -Destination $shimUtils
                Write-Output "✓ Synced PowerShell shims to $shimRoot"
            } catch {
                Write-Warning ("Failed to sync PowerShell shims to {0}: {1}" -f $shimRoot, $_)
            }

            # Add Windows shim launchers to PATH.
            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            $inUserPath = ($userPath -split ';') -contains $shimLaunchers
            if (-not $inUserPath) {
                $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $shimLaunchers } else { "$shimLaunchers;$userPath" }
                [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
                Write-Output "✓ Added $shimLaunchers to your User PATH."
            } else {
                Write-Output "✓ Launchers already present in User PATH."
            }

            if (-not (($env:Path -split ';') -contains $shimLaunchers)) {
                $env:Path = "$shimLaunchers;$env:Path"
                Write-Output "✓ Updated current session PATH."
            }

            Write-Output "Launchers available via: $shimLaunchers"
        }
    }
}
