#!/usr/bin/env pwsh
[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\utils\wsl-shim.ps1")
$exitCode = Invoke-CodingAgentsWslScript -ScriptRelativePath "scripts\runtime\sync-local-remote.sh" -Arguments $Arguments
exit $exitCode
