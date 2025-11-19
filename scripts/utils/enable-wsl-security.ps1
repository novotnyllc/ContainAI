<#
.SYNOPSIS
Audits and configures WSL 2 so AppArmor is always available to Coding Agents.
.DESCRIPTION
Validates both the Windows-side .wslconfig kernel parameters and the Linux-side
systemd/securityfs requirements. Supports a check-only mode so Linux prereq
checks can surface actionable remediation guidance inside WSL shells.
#>
[CmdletBinding()]
param (
    [switch]$Force,
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
$WslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$LsmStack = "apparmor,landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,tomoyo"
$KernelParams = "apparmor=1 security=apparmor lsm=$LsmStack"

function Get-WslExecutablePath {
    $candidate = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($candidate) {
        return $candidate.Source
    }

    $fallback = Join-Path $env:WINDIR "System32\\wsl.exe"
    if (Test-Path $fallback) {
        return $fallback
    }

    throw "Unable to locate wsl.exe. Install WSL 2 and ensure it is on PATH."
}

function Test-KernelCommandLineConfigured {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { return $false }
    if ($Content -notmatch "kernelCommandLine\s*=") { return $false }

    $hasAppArmorFlag = $Content -match "apparmor\s*=\s*1"
    $hasSecurityFlag = $Content -match "security\s*=\s*apparmor"
    $hasLsmStack = $Content -match "lsm\s*=\s*[^`r`n]*apparmor"

    return ($hasAppArmorFlag -and $hasSecurityFlag -and $hasLsmStack)
}

function Get-WslLinuxDeficiencies {
    param([string]$WslExe)

    $probe = "if ! grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null; then echo MISSING_SYSTEMD; fi; if ! grep -q 'securityfs' /etc/fstab 2>/dev/null; then echo MISSING_FSTAB; fi"
    $output = & $WslExe -u root bash -c $probe 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect the default WSL distribution. $output"
    }

    return [PSCustomObject]@{
        NeedsSystemd   = ($output -match 'MISSING_SYSTEMD')
        NeedsSecurityFs = ($output -match 'MISSING_FSTAB')
    }
}

function Get-WslSecurityStatus {
    param(
        [string]$WslConfig,
        [string]$KernelLine,
        [string]$WslExe
    )

    $diagnostics = New-Object System.Collections.Generic.List[string]
    $windowsNeedsUpdate = $false

    if (-not (Test-Path $WslConfig)) {
        $windowsNeedsUpdate = $true
        $diagnostics.Add("Create .wslconfig with kernelCommandLine = $KernelLine") | Out-Null
    } else {
        $content = Get-Content $WslConfig -Raw
        if (-not (Test-KernelCommandLineConfigured -Content $content)) {
            $windowsNeedsUpdate = $true
            $diagnostics.Add("Update .wslconfig kernelCommandLine so AppArmor is prioritized (lsm/security flags)") | Out-Null
        }
    }

    $linuxStatus = Get-WslLinuxDeficiencies -WslExe $WslExe
    if ($linuxStatus.NeedsSystemd) {
        $diagnostics.Add("Enable systemd=true inside /etc/wsl.conf for the default distro") | Out-Null
    }
    if ($linuxStatus.NeedsSecurityFs) {
        $diagnostics.Add("Ensure /etc/fstab mounts securityfs (AppArmor interface)") | Out-Null
    }

    return [PSCustomObject]@{
        WindowsNeedsUpdate = $windowsNeedsUpdate
        NeedsSystemd = $linuxStatus.NeedsSystemd
        NeedsSecurityFs = $linuxStatus.NeedsSecurityFs
        Diagnostics = $diagnostics
    }
}

function Set-WindowsKernelConfig {
    param(
        [string]$WslConfig,
        [string]$KernelLine
    )

    $directory = Split-Path -Parent $WslConfig
    if (-not (Test-Path $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }

    $content = if (Test-Path $WslConfig) { Get-Content $WslConfig -Raw } else { "" }

    if ($content -match "kernelCommandLine\s*=") {
        $updated = [System.Text.RegularExpressions.Regex]::Replace($content, "kernelCommandLine\s*=.*", "kernelCommandLine = $KernelLine", 1)
        Set-Content -Path $WslConfig -Value $updated -Encoding UTF8
        Write-Host "   -> Updated existing kernelCommandLine" -ForegroundColor Green
        return
    }

    if ($content -match "\[wsl2\]") {
        $updated = $content -replace "\[wsl2\]", "[wsl2]`nkernelCommandLine = $KernelLine"
        Set-Content -Path $WslConfig -Value $updated -Encoding UTF8
        Write-Host "   -> Added kernelCommandLine inside existing [wsl2] section" -ForegroundColor Green
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($content)) {
        $content = $content.TrimEnd() + "`n`n[wsl2]`nkernelCommandLine = $KernelLine`n"
    } else {
        $content = "[wsl2]`nkernelCommandLine = $KernelLine`n"
    }

    Set-Content -Path $WslConfig -Value $content -Encoding UTF8
    Write-Host "   -> Created [wsl2] stanza with kernelCommandLine" -ForegroundColor Green
}

function Set-WslLinuxConfig {
    param([string]$WslExe)

    $script = "if ! grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null; then printf '\n[boot]\nsystemd=true\n' >> /etc/wsl.conf; fi; if ! grep -q 'securityfs' /etc/fstab 2>/dev/null; then echo 'none /sys/kernel/security securityfs defaults 0 0' >> /etc/fstab; fi"
    & $WslExe -u root bash -c $script 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update Linux-side WSL configuration"
    }
    Write-Host "   -> Configured Linux boot settings" -ForegroundColor Green
}

function Restart-Wsl {
    param([string]$WslExe)

    Write-Host "🔄 Restarting WSL..." -ForegroundColor Yellow
    & $WslExe --shutdown | Out-Null
    Start-Sleep -Seconds 5
    try {
        & $WslExe bash -c "exit 0" | Out-Null
    } catch {
        Write-Warning "⚠️  Unable to pre-start WSL default user session automatically: $_"
    }
}

$wslExePath = Get-WslExecutablePath
Write-Host "🔍 Checking WSL 2 security configuration..." -ForegroundColor Cyan
$status = Get-WslSecurityStatus -WslConfig $WslConfigPath -KernelLine $KernelParams -WslExe $wslExePath

if ($status.Diagnostics.Count -eq 0) {
    Write-Host "✅ System is already correctly configured." -ForegroundColor Green
    exit 0
}

Write-Host "`n⚠️  The following security fixes are required:" -ForegroundColor Yellow
foreach ($message in $status.Diagnostics) {
    Write-Host "   • $message"
}

if ($CheckOnly) {
    exit 2
}

if (-not $Force) {
    Write-Host "`nThis will modify configuration files and RESTART WSL (closing all running shells)." -ForegroundColor Red
    $confirmation = Read-Host "Do you want to proceed? [y/N]"
    if ($confirmation -notmatch '^[Yy]$') {
        Write-Host "❌ Aborted."
        exit 1
    }
}

Write-Host "`n🚀 Applying fixes..." -ForegroundColor Cyan

if ($status.WindowsNeedsUpdate) {
    Set-WindowsKernelConfig -WslConfig $WslConfigPath -KernelLine $KernelParams
} else {
    Write-Host "   -> Windows kernelCommandLine already satisfies requirements" -ForegroundColor DarkGray
}

if ($status.NeedsSystemd -or $status.NeedsSecurityFs) {
    Set-WslLinuxConfig -WslExe $wslExePath
} else {
    Write-Host "   -> Linux boot settings already satisfy requirements" -ForegroundColor DarkGray
}

Restart-Wsl -WslExe $wslExePath
Write-Host '✅ Configuration complete. AppArmor is now active.' -ForegroundColor Green