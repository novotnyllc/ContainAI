#!/usr/bin/env pwsh
<#!
Strict security enforcement helpers (PowerShell).
Requires: apparmor_parser on Linux, AppArmor enabled.
#>

. (Join-Path $PSScriptRoot "wsl-shim.ps1")

function Invoke-AppArmorStrict {
    param(
        [Parameter(Mandatory = $true)] [string]$ProfileDir
    )

    $installRoot = (Get-Item $ProfileDir).Parent.FullName
    $scriptRelative = "host/utils/security-enforce.sh"
    $scriptArgs = @("--verify", $installRoot)
    $code = Invoke-ContainAIWslScript -ScriptRelativePath $scriptRelative -Arguments $scriptArgs
    if ($code -ne 0) {
        throw "Security profile enforcement failed (see bash output above)."
    }
}
