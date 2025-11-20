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
    $ProdRoot = $env:CODING_AGENTS_PROD_ROOT
    if (-not $ProdRoot) { $ProdRoot = $env:CODING_AGENTS_INSTALL_ROOT }
    if (-not $ProdRoot) { $ProdRoot = "/opt/coding-agents/current" }
}

$mode = $env:CODING_AGENTS_PROFILE
if (-not $mode) { $mode = $env:CODING_AGENTS_MODE }
if (-not $mode -and $env:CODING_AGENTS_FORCE_MODE) { $mode = $env:CODING_AGENTS_FORCE_MODE }

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
    $configRoot = $env:CODING_AGENTS_CONFIG_ROOT
    if (-not $configRoot) { $configRoot = "/etc/coding-agents" }
    $dataRoot = $env:CODING_AGENTS_DATA_ROOT
    if (-not $dataRoot) { $dataRoot = "/var/lib/coding-agents" }
    $cacheRoot = $env:CODING_AGENTS_CACHE_ROOT
    if (-not $cacheRoot) { $cacheRoot = "/var/cache/coding-agents" }
} else {
    $root = (Resolve-Path $RepoRoot).Path
    $configRoot = $env:CODING_AGENTS_CONFIG_ROOT
    if (-not $configRoot) { $configRoot = "$HOME/.config/coding-agents-dev" }
    $dataRoot = $env:CODING_AGENTS_DATA_ROOT
    if (-not $dataRoot) { $dataRoot = "$HOME/.local/share/coding-agents-dev" }
    $cacheRoot = $env:CODING_AGENTS_CACHE_ROOT
    if (-not $cacheRoot) { $cacheRoot = "$HOME/.cache/coding-agents-dev" }
}

$shaFile = $env:CODING_AGENTS_SHA256_FILE
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
            "CODING_AGENTS_PROFILE=$mode"
            "CODING_AGENTS_ROOT=$root"
            "CODING_AGENTS_CONFIG_ROOT=$configRoot"
            "CODING_AGENTS_DATA_ROOT=$dataRoot"
            "CODING_AGENTS_CACHE_ROOT=$cacheRoot"
            "CODING_AGENTS_SHA256_FILE=$shaFile"
        ) -join "`n"
    }
}
