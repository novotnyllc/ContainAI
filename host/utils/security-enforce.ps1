#!/usr/bin/env pwsh
<#!
Strict security enforcement helpers (PowerShell).
Requires: apparmor_parser on Linux, AppArmor enabled.
#>

function Require-AppArmorStrict {
    param(
        [Parameter(Mandatory = $true)] [string]$ProfileDir
    )

    $seccomp = Join-Path $ProfileDir "seccomp-containai-agent.json"
    $apparmor = Join-Path $ProfileDir "apparmor-containai-agent.profile"

    if (-not (Test-Path $seccomp)) { throw "Seccomp profile missing at $seccomp" }
    if (-not (Test-Path $apparmor)) { throw "AppArmor profile missing at $apparmor" }

    $seccompHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $seccomp).Hash
    $apparmorHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apparmor).Hash
    @"
seccomp-containai-agent.json $seccompHash
apparmor-containai-agent.profile $apparmorHash
"@ | Set-Content -LiteralPath (Join-Path $ProfileDir "containai-profiles.sha256")

    $enabledPath = "/sys/module/apparmor/parameters/enabled"
    if (-not (Get-Command apparmor_parser -ErrorAction SilentlyContinue)) {
        throw "AppArmor tools missing; install apparmor-utils and retry."
    }
    if (-not (Test-Path $enabledPath) -or -not ((Get-Content $enabledPath) -match 'Y|y')) {
        throw "AppArmor is disabled; enable AppArmor to continue."
    }
    & apparmor_parser -r $apparmor 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to load AppArmor profile 'containai'."
    }
}
