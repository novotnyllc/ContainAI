#!/usr/bin/env pwsh
[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\..\utils\wsl-shim.ps1")
$exitCode = Invoke-ContainAIWslScript -ScriptRelativePath "host\launchers\entrypoints\run-claude-dev" -Arguments $Arguments
exit $exitCode
