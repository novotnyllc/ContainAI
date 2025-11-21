#!/usr/bin/env pwsh
[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\..\host\utils\wsl-shim.ps1")
$exitCode = Invoke-ContainAIWslScript -ScriptRelativePath "scripts\test\test-config.sh" -Arguments $Arguments
exit $exitCode
