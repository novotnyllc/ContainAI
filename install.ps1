#!/usr/bin/env pwsh
<#!
.SYNOPSIS
Bootstrap installer for ContainAI releases (PowerShell).
.DESCRIPTION
Downloads the versioned payload artifact (containai-payload-<version>.tar.gz) from GitHub Releases,
extracts it locally, then runs the bundled install-release.sh with sudo if needed to install
into the secure machine-wide location and load the AppArmor profile (Linux).
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Repo = "ContainAI/ContainAI",
    [string]$InstallRoot = "/opt/containai"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Die($Message) { Write-Error $Message; exit 1 }

if (-not $Version) {
    try {
        $headers = @{}
        if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $($env:GITHUB_TOKEN)" }
        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -ErrorAction Stop
        $Version = $latest.tag_name
    } catch {
        Write-Die "Unable to determine latest release; pass --Version vX.Y.Z"
    }
}

$AssetName = "containai-payload-$Version.tar.gz"
$WorkDir = New-Item -ItemType Directory -Force -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "containai-$Version-$(Get-Random)"))
try {
    $AssetPath = Join-Path $WorkDir $AssetName
    $headers = @{}
    if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $($env:GITHUB_TOKEN)" }
    Write-Output "⬇️  Downloading $AssetName from $Repo..."
    Invoke-WebRequest -Uri "https://github.com/$Repo/releases/download/$Version/$AssetName" -OutFile $AssetPath -Headers $headers -UseBasicParsing -ErrorAction Stop

    $PayloadDir = Join-Path $WorkDir "payload"
    New-Item -ItemType Directory -Force -Path $PayloadDir | Out-Null
    tar -xzf $AssetPath -C $PayloadDir

    $Installer = Join-Path $PayloadDir "host/utils/install-release.sh"
    if (-not (Test-Path $Installer)) { Write-Die "Installer not found inside payload: $Installer" }

    $sudo = @()
    $isLinux = $PSVersionTable.Platform -eq 'Unix' -or ($PSVersionTable.OS -match 'Linux')
    if ($isLinux) {
        $uid = ""
        try { $uid = (& bash -lc "id -u" 2>$null).Trim() } catch {}
        if ($uid -and $uid -ne "0" -and (Get-Command sudo -ErrorAction SilentlyContinue)) {
            Write-Output "This install will write to $InstallRoot and load the AppArmor profile. Sudo is required."
            $reply = Read-Host "Proceed with sudo? [Y/n]"
            if ($reply -match '^[Nn]') { Write-Die "Cancelled." }
            $sudo = @("sudo")
        }
    }

    Write-Output "▶ Running installer..."
    & $sudo bash "$Installer" --version $Version --asset-dir $PayloadDir --install-root $InstallRoot
    Write-Output "✅ ContainAI $Version installed to $InstallRoot"
} finally {
    if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
