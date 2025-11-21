#!/usr/bin/env pwsh
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet("env","json")]
    [string]$Format = "env",
    [string]$RepoRoot,
    [string]$ProdRoot
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Join-Path $PSScriptRoot "..\.." | Resolve-Path | Select-Object -ExpandProperty Path
}

if (-not $ProdRoot) {
    $ProdRoot = $env:CONTAINAI_PROD_ROOT
    if (-not $ProdRoot) { $ProdRoot = $env:CONTAINAI_INSTALL_ROOT }
    if (-not $ProdRoot) { $ProdRoot = "/opt/containai/current" }
}

$mode = $env:CONTAINAI_PROFILE
if (-not $mode) { $mode = $env:CONTAINAI_MODE }
if (-not $mode -and $env:CONTAINAI_FORCE_MODE) { $mode = $env:CONTAINAI_FORCE_MODE }

if (-not $mode) {
    if (Test-Path (Join-Path $ProdRoot "host/launchers")) {
        $mode = "prod"
    } else {
        $mode = "dev"
    }
}

if ($mode -notin @("dev","prod")) {
    throw "Invalid profile mode: $mode"
}

if ($mode -eq "prod") {
    $root = (Resolve-Path $ProdRoot).Path
    $configRoot = $env:CONTAINAI_CONFIG_ROOT
    if (-not $configRoot) { $configRoot = "/etc/containai" }
    $dataRoot = $env:CONTAINAI_DATA_ROOT
    if (-not $dataRoot) { $dataRoot = "/var/lib/containai" }
    $cacheRoot = $env:CONTAINAI_CACHE_ROOT
    if (-not $cacheRoot) { $cacheRoot = "/var/cache/containai" }
} else {
    $root = (Resolve-Path $RepoRoot).Path
    $configRoot = $env:CONTAINAI_CONFIG_ROOT
    if (-not $configRoot) { $configRoot = "$HOME/.config/containai-dev" }
    $dataRoot = $env:CONTAINAI_DATA_ROOT
    if (-not $dataRoot) { $dataRoot = "$HOME/.local/share/containai-dev" }
    $cacheRoot = $env:CONTAINAI_CACHE_ROOT
    if (-not $cacheRoot) { $cacheRoot = "$HOME/.cache/containai-dev" }
}

$shaFile = $env:CONTAINAI_SHA256_FILE
if (-not $shaFile) { $shaFile = Join-Path $root "SHA256SUMS" }

switch ($Format) {
    "json" {
        $obj = [ordered]@{
            profile   = $mode
            root      = $root
            configRoot = $configRoot
            dataRoot   = $dataRoot
            cacheRoot  = $cacheRoot
            sha256File = $shaFile
        }
        $obj | ConvertTo-Json -Compress
    }
    "env" {
        @(
            "CONTAINAI_PROFILE=$mode"
            "CONTAINAI_ROOT=$root"
            "CONTAINAI_CONFIG_ROOT=$configRoot"
            "CONTAINAI_DATA_ROOT=$dataRoot"
            "CONTAINAI_CACHE_ROOT=$cacheRoot"
            "CONTAINAI_SHA256_FILE=$shaFile"
        ) -join "`n"
    }
}
