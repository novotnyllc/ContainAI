#!/usr/bin/env pwsh
[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "wsl-shim.ps1")
$exitCode = Invoke-CodingAgentsWslScript -ScriptRelativePath "host\utils\verify-prerequisites.sh" -Arguments $Arguments
exit $exitCode
