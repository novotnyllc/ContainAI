#!/usr/bin/env pwsh
<#!
.SYNOPSIS
    Thin PowerShell wrapper that delegates to the Bash installer via WSL.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Channel = "prod",
    [string]$Repo = "novotnyllc/ContainAI",
    [string]$InstallRoot = "/opt/containai",
    [string]$RegistryNamespace
)

. "$PSScriptRoot/host/utils/wsl-shim.ps1"

$ErrorActionPreference = 'Stop'
$argsList = @()
if ($PSBoundParameters.ContainsKey('Channel')) { $argsList += @('--channel', $Channel) }
if ($PSBoundParameters.ContainsKey('Version')) { $argsList += @('--version', $Version) }
if ($PSBoundParameters.ContainsKey('Repo')) { $argsList += @('--repo', $Repo) }
if ($PSBoundParameters.ContainsKey('InstallRoot')) { $argsList += @('--install-root', $InstallRoot) }
if ($PSBoundParameters.ContainsKey('RegistryNamespace')) { $argsList += @('--registry-namespace', $RegistryNamespace) }

$exitCode = Invoke-ContainAIWslScript -ScriptRelativePath "install.sh" -Arguments $argsList
if ($exitCode -ne 0) { exit $exitCode }

# Sync PowerShell shims on Windows side after install
function Sync-WindowsShims {
    param([string]$InstallRoot)
    $wslExe = Get-WslExecutablePath
    if ($null -eq $wslExe) { return }
    $launchersWsl = "$InstallRoot/current/host/launchers/entrypoints"
    $utilsWsl = "$InstallRoot/current/host/utils"
    $launchersWin = (& $wslExe wslpath -w $launchersWsl 2>&1).Trim()
    $utilsWin = (& $wslExe wslpath -w $utilsWsl 2>&1).Trim()
    if ([string]::IsNullOrWhiteSpace($launchersWin) -or [string]::IsNullOrWhiteSpace($utilsWin)) {
        Write-Warning "Could not translate WSL install paths to Windows paths; PATH update skipped."
        return
    }
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
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $inUserPath = ($userPath -split ';') -contains $shimLaunchers
    if (-not $inUserPath) {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $shimLaunchers } else { "$shimLaunchers;$userPath" }
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        Write-Output "✓ Added $shimLaunchers to your User PATH."
    }
    if (-not (($env:Path -split ';') -contains $shimLaunchers)) {
        $env:Path = "$shimLaunchers;$env:Path"
        Write-Output "✓ Updated current session PATH."
    }
    Write-Output "Launchers available via: $shimLaunchers"
}

Sync-WindowsShims -InstallRoot $InstallRoot
