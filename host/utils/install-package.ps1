#!/usr/bin/env pwsh
<#!
.SYNOPSIS
Downloads a ContainAI release from GitHub and installs it (blue/green).
#>

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

if (-not $AllowNonRoot) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { Write-Die "System installs require Administrator/root; use -AllowNonRoot only for tests." }
    if ($InstallRoot.StartsWith($env:USERPROFILE)) { Write-Die "Install root cannot be under the current user profile." }
}

$ReleaseDir = Join-Path $InstallRoot "releases/$Version"
New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null

if ($AssetDir) {
    $DownloadDir = $AssetDir
} else {
    $DownloadDir = New-Item -ItemType Directory -Force -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "containai-$Version-$(Get-Random)"))
}

$Bundle = Join-Path $DownloadDir "containai-$Version.tar.gz"
$Payload = Join-Path $DownloadDir "payload.tar.gz"
$PayloadSha = Join-Path $DownloadDir "payload.sha256"
$Attestation = Join-Path $DownloadDir "attestation.intoto.jsonl"
$CosignRoot = Join-Path $DownloadDir "cosign-root.pem"

function Get-ReleaseAsset([string]$Name, [string]$Dest) {
    $token = $env:GITHUB_TOKEN
    $url = "https://github.com/$Repo/releases/download/$Version/$Name"
    $headers = @{}
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    Write-Output "Downloading $Name"
    Invoke-WebRequest -Uri $url -OutFile $Dest -Headers $headers -UseBasicParsing -ErrorAction Stop
}

function Get-ReleaseBundle {
    if ($AssetDir) {
        if (-not (Test-Path $Bundle)) { Write-Die "Bundle not found in $AssetDir" }
        return
    }
    Get-ReleaseAsset "containai-$Version.tar.gz" $Bundle
    if (-not (Test-Path $Bundle)) { Write-Die "Bundle missing in release" }
}

function Expand-Bundle {
    tar -xzf $Bundle -C $DownloadDir
    if (-not (Test-Path $Payload)) { Write-Die "payload.tar.gz missing in bundle" }
    if (-not (Test-Path $PayloadSha)) { Write-Die "payload.sha256 missing in bundle" }
    if (-not (Test-Path $Attestation)) { Write-Die "attestation.intoto.jsonl missing in bundle" }
}
function Test-PayloadHash {
    $expected = Select-String -Path $PayloadSha -Pattern "payload.tar.gz" | ForEach-Object { $_.Line.Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries)[0] }
    if (-not $expected) { Write-Die "Hash not found in payload.sha256" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Payload).Hash.ToLower()
    if ($actual -ne $expected.ToLower()) { Write-Die "Payload hash mismatch (expected $expected got $actual)" }
    Write-Output "SHA256 verified"
}

function Test-Attestation {
    if (-not (Test-Path $Attestation)) { Write-Die "Attestation missing; cannot verify provenance." }
    $rawAtt = Get-Content $Attestation -Raw
    $bundle = $rawAtt | ConvertFrom-Json
    if ($bundle.attestation -eq "placeholder") { Write-Output "Skipping attestation verification (placeholder dev build)"; return }
    Write-Output "Verifying attestation via system crypto"
    $envObj = if ($bundle.envelope) { $bundle.envelope } else { $bundle }
    $payloadB64 = $envObj.payload
    $sigB64 = $envObj.signatures[0].sig
    $certEscaped = $envObj.signatures[0].cert
    if (-not $payloadB64 -or -not $sigB64 -or -not $certEscaped) { Write-Die "Attestation missing payload/sig/cert" }
    $payloadBytes = [Convert]::FromBase64String($payloadB64)
    $payloadJson = [System.Text.Encoding]::UTF8.GetString($payloadBytes)
    $payloadParsed = $payloadJson | ConvertFrom-Json
    $expected = $payloadParsed.subject[0].digest.sha256
    if (-not $expected) { Write-Die "No digest in attested payload" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Payload).Hash.ToLower()
    if ($expected.ToLower() -ne $actual) { Write-Die "Attested digest mismatch (expected $expected got $actual)" }
    $certPem = $certEscaped -replace "\\n","`n"
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([System.Text.Encoding]::UTF8.GetBytes($certPem))
    $root = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new((Get-Content $CosignRoot -Raw))
    $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
    $chain.ChainPolicy.TrustMode = [System.Security.Cryptography.X509Certificates.X509ChainTrustMode]::CustomRootTrust
    $chain.ChainPolicy.CustomTrustStore.Add($root) | Out-Null
    $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
    if (-not $chain.Build($cert)) { Write-Die "Certificate chain validation failed" }
    $san = ($cert.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.17" } | Select-Object -First 1)
    if (-not $san -or $san.Format(1) -notmatch "token.actions.githubusercontent.com") { Write-Die "OIDC issuer not trusted in certificate" }
    $sigBytes = [Convert]::FromBase64String($sigB64)
    $ecdsa = $cert.GetECDsaPublicKey()
    $ok = $ecdsa.VerifyData($payloadBytes, $sigBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    if (-not $ok) { Write-Die "Signature verification failed" }
}

if ($VerifyOnly) {
    $current = Join-Path $InstallRoot "current"
    if (-not (Test-Path $current)) { Write-Die "No current symlink under $InstallRoot" }
    $target = (Get-Item $current).Target
    & "$PSScriptRoot/integrity-check.ps1" -Mode prod -Root $target -Sums (Join-Path $target "SHA256SUMS")
    Write-Output "Existing install verified."
    exit 0
}

Get-ReleaseBundle
Expand-Bundle
Test-PayloadHash
Test-Attestation

Write-Output "Installing ContainAI $Version to $ReleaseDir"
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $ReleaseDir
New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null
& tar -xzf $Payload -C $ReleaseDir --strip-components=1
Copy-Item -LiteralPath $Payload -Destination (Join-Path $ReleaseDir (Split-Path -Leaf $Payload))
if (Test-Path $CosignRoot) { Copy-Item -LiteralPath $CosignRoot -Destination (Join-Path $ReleaseDir "cosign-root.pem") }
if (Test-Path $Attestation) { Copy-Item -LiteralPath $Attestation -Destination (Join-Path $ReleaseDir "attestation.intoto.jsonl") }

& "$PSScriptRoot/integrity-check.ps1" -Mode prod -Root $ReleaseDir -Sums (Join-Path $ReleaseDir "SHA256SUMS")

$currentLink = Join-Path $InstallRoot "current"
$previousLink = Join-Path $InstallRoot "previous"
if (Test-Path $currentLink) {
    $target = (Get-Item $currentLink).Target
    New-Item -Force -ItemType SymbolicLink -Path $previousLink -Target $target | Out-Null
}
New-Item -Force -ItemType SymbolicLink -Path $currentLink -Target $ReleaseDir | Out-Null

$payloadName = Split-Path -Leaf $Payload
$bundleName = Split-Path -Leaf $Bundle
@"
version=$Version
installed_at=$(Get-Date -Format s -AsUTC)Z
payload=$payloadName
bundle=$bundleName
repo=$Repo
"@ | Set-Content -LiteralPath (Join-Path $ReleaseDir "install.meta")

Write-Output "Install complete. Current -> $ReleaseDir"
