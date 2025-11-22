#!/usr/bin/env pwsh
<#!
.SYNOPSIS
    Thin PowerShell wrapper that delegates to the Bash installer via WSL.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Channel = "dev",
    [string]$Repo = "ContainAI/ContainAI",
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
