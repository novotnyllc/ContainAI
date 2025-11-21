#!/usr/bin/env pwsh
[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\utils\wsl-shim.ps1")
$exitCode = Invoke-ContainAIWslScript -ScriptRelativePath "host\launchers\run-agent" -Arguments $Arguments
exit $exitCode
