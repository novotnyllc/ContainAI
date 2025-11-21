#!/usr/bin/env pwsh
<#!
.SYNOPSIS
Installs a ContainAI release artifact (tar.gz) from GitHub Releases or a local asset directory.

.DESCRIPTION
Expects a versioned payload asset named containai-payload-<version>.tar.gz that contains:
  - host/, agent-configs/, config.toml, tools/, SBOM files
  - SHA256SUMS and payload.sha256 (hash of SHA256SUMS)

Steps:
  - Download or locate the payload tar.gz (or an already-extracted payload dir)
  - Verify payload.sha256 against SHA256SUMS
  - Copy payload into <install-root>/releases/<version>, write profile manifest
  - Run integrity-check with the embedded SHA256SUMS
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$Repo = $env:GITHUB_REPOSITORY,
    [string]$InstallRoot = "/opt/containai",
    [string]$AssetDir,
    [switch]$AllowNonRoot,
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Die($Message) { Write-Error $Message; exit 1 }

if (-not $Repo) { Write-Die "--Repo or GITHUB_REPOSITORY env is required" }

$PayloadAssetName = "containai-payload-$Version.tar.gz"
$ReleaseDir = Join-Path $InstallRoot "releases/$Version"
$ExtractDir = New-Item -ItemType Directory -Force -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "containai-$Version-$(Get-Random)"))
$AssetPath = $null

if (-not $AllowNonRoot) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { Write-Die "System installs require Administrator/root; use -AllowNonRoot only for tests." }
    if ($InstallRoot.StartsWith($env:USERPROFILE)) { Write-Die "Install root cannot be under the current user profile." }
}

function Find-PayloadDir {
    param([string]$BasePath)
    $sha = Get-ChildItem -Path $BasePath -Filter "SHA256SUMS" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sha) { Write-Die "SHA256SUMS not found in payload assets" }
    $payloadDir = $sha.Directory.FullName
    $payloadSha = Join-Path $payloadDir "payload.sha256"
    if (-not (Test-Path $payloadSha)) { Write-Die "payload.sha256 missing alongside SHA256SUMS" }
    return @{ Dir = $payloadDir; Sha = $payloadSha; ShaSums = $sha.FullName }
}

function Verify-PayloadHash {
    param([string]$ShaFile, [string]$ShaSumsPath)
    $expected = (Get-Content -Path $ShaFile -TotalCount 1).Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries)[0]
    if (-not $expected) { Write-Die "Expected hash for SHA256SUMS not found in payload.sha256" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $ShaSumsPath).Hash
    if ($actual.ToLower() -ne $expected.ToLower()) {
        Write-Die "Payload hash mismatch (expected $expected got $actual)"
    }
    Write-Output "SHA256 verified for payload contents"
}

function Extract-PayloadTar {
    param([string]$TarGzPath, [string]$Destination)
    if (Test-Path $Destination) { Remove-Item -Recurse -Force $Destination }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    tar -xzf $TarGzPath -C $Destination
}

if ($VerifyOnly) {
    Write-Output "🔍 Verifying existing install at $InstallRoot/current"
    $current = Join-Path $InstallRoot "current"
    if (-not (Test-Path $current)) { Write-Die "No current symlink under $InstallRoot" }
    $target = (Get-Item $current).Target
    if (-not (Test-Path $target)) { Write-Die "Current symlink target missing: $target" }
    & "$PSScriptRoot/integrity-check.ps1" -Mode prod -Root $target -Sums (Join-Path $target "SHA256SUMS")
    Write-Output "✅ Existing install verified."
    exit 0
}

try {
    if ($AssetDir) {
        $candidateTar = Join-Path $AssetDir $PayloadAssetName
        if (Test-Path $candidateTar) { $AssetPath = $candidateTar }
    }
    if (-not $AssetPath) {
        $tempZip = Join-Path $ExtractDir $PayloadAssetName
        $headers = @{}
        if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $($env:GITHUB_TOKEN)" }
        $url = "https://github.com/$Repo/releases/download/$Version/$PayloadAssetName"
        Write-Output "⬇️  Fetching $PayloadAssetName"
        Invoke-WebRequest -Uri $url -OutFile $tempZip -Headers $headers -UseBasicParsing -ErrorAction Stop
        $AssetPath = $tempZip
    }

    if ($AssetPath) {
        Extract-PayloadTar -TarGzPath $AssetPath -Destination (Join-Path $ExtractDir "payload")
        $payloadInfo = Find-PayloadDir -BasePath (Join-Path $ExtractDir "payload")
    } else {
        # If we have no zip but AssetDir points to extracted payload
        if (-not $AssetDir) { Write-Die "No payload asset found" }
        $payloadInfo = Find-PayloadDir -BasePath $AssetDir
    }

    $payloadDir = $payloadInfo.Dir
    $payloadSha = $payloadInfo.Sha
    $shaSumsPath = $payloadInfo.ShaSums

    Verify-PayloadHash -ShaFile $payloadSha -ShaSumsPath $shaSumsPath

    Write-Output "📦 Installing ContainAI $Version to $ReleaseDir"
    if (Test-Path $ReleaseDir) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $ReleaseDir }
    New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null
    Copy-Item -Recurse -Force -Path (Join-Path $payloadDir '*') -Destination $ReleaseDir

    $profileDir = Join-Path $ReleaseDir "host/profiles"
    if (Test-Path $profileDir) {
        . (Join-Path $PSScriptRoot "security-enforce.ps1")
        Require-AppArmorStrict -ProfileDir $profileDir
    }

    & "$PSScriptRoot/integrity-check.ps1" -Mode prod -Root $ReleaseDir -Sums (Join-Path $ReleaseDir "SHA256SUMS")

    $currentLink = Join-Path $InstallRoot "current"
    $previousLink = Join-Path $InstallRoot "previous"
    if (Test-Path $currentLink) {
        $target = (Get-Item $currentLink).Target
        New-Item -Force -ItemType SymbolicLink -Path $previousLink -Target $target | Out-Null
    }
    New-Item -Force -ItemType SymbolicLink -Path $currentLink -Target $ReleaseDir | Out-Null

    @" 
version=$Version
installed_at=$(Get-Date -Format s -AsUTC)Z
payload_asset=$PayloadAssetName
repo=$Repo
"@ | Set-Content -LiteralPath (Join-Path $ReleaseDir "install.meta")

    Write-Output "✅ Install complete. Current -> $ReleaseDir"
} finally {
    if (Test-Path $ExtractDir) { Remove-Item -Recurse -Force $ExtractDir -ErrorAction SilentlyContinue }
}
