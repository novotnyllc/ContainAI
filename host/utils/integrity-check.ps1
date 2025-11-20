#!/usr/bin/env pwsh
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet("dev","prod")]
    [string]$Mode = $env:CODING_AGENTS_PROFILE,
    [string]$Root = $env:CODING_AGENTS_ROOT,
    [string]$SumsPath = $env:CODING_AGENTS_SHA256_FILE,
    [ValidateSet("text","json")]
    [string]$Format = "text",
    [switch]$FailDevMissing
)

$ErrorActionPreference = "Stop"

$null = $Format

if (-not $Mode) { $Mode = "dev" }
if (-not $Root) { $Root = (Join-Path $PSScriptRoot "..\..") }
if (-not $SumsPath) { $SumsPath = Join-Path $Root "SHA256SUMS" }

function Write-Result([string]$Status, [string]$Message, [string]$OutputFormat = $Format) {
    if ($OutputFormat -eq "json") {
        $obj = [ordered]@{
            mode     = $Mode
            status   = $Status
            message  = $Message
            sumsPath = $SumsPath
            root     = $Root
        }
        $obj | ConvertTo-Json -Compress
    } else {
        Write-Output $Message
    }
}

if (-not (Get-Command -Name "Get-FileHash" -ErrorAction SilentlyContinue)) {
    Write-Result "error" "Get-FileHash unavailable"
    if ($Mode -eq "prod") { exit 1 } else { exit 0 }
}

if (-not (Test-Path -LiteralPath $SumsPath)) {
    $msg = "No SHA256SUMS found at $SumsPath"
    if ($Mode -eq "prod" -or $FailDevMissing.IsPresent) {
        Write-Result "fail" $msg
        exit 1
    }
    Write-Result "warn" "Dev mode: $msg (skipping)"
    exit 0
}

$lines = Get-Content -LiteralPath $SumsPath | Where-Object { $_.Trim() -ne "" }
$failures = @()
foreach ($line in $lines) {
    if ($line -notmatch '^[0-9a-fA-F]{64}\s+(.+)$') {
        $failures += "Malformed SHA entry: $line"
        continue
    }
    $expected = $line.Substring(0,64)
    $file = $line.Substring(65).Trim()
    $target = $file
    if (-not [System.IO.Path]::IsPathRooted($file)) {
        $target = Join-Path $Root $file
    }
    if (-not (Test-Path -LiteralPath $target)) {
        $failures += "Missing file $file"
        continue
    }
    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected.ToLowerInvariant()) {
        $failures += "Mismatch for $file"
    }
}

if ($failures.Count -gt 0) {
    $msg = "Integrity check failed: " + ($failures -join "; ")
    Write-Result "fail" $msg
    if ($Mode -eq "prod") { exit 1 } else { exit 0 }
}

Write-Result "ok" "Integrity check passed for $SumsPath"
exit 0
