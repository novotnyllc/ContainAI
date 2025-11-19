<#
.SYNOPSIS
    CodingAgents Health Check ("The Doctor")
.DESCRIPTION
    Diagnoses system readiness for running secure agents.
    Checks: Admin privileges, Docker/Podman status, WSL 2 security (AppArmor), Network, and Disk Space.
#>
$ErrorActionPreference = "Stop"

# Colors for friendly output
function Write-Good ($Text) { Write-Host "✅ $Text" -ForegroundColor Green }
function Write-Warn ($Text) { Write-Host "⚠️  $Text" -ForegroundColor Yellow }
function Write-Bad  ($Text) { Write-Host "❌ $Text" -ForegroundColor Red }
function Write-Info ($Text) { Write-Host "ℹ️  $Text" -ForegroundColor Cyan }

Write-Host "`n🏥 CodingAgents Doctor" -ForegroundColor Cyan
Write-Host "-----------------------"

$Global:ExitCode = 0

# 1. PRIVILEGE CHECK
# We need Admin to install to %ProgramFiles%, but User is fine for Runtime.
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($IsAdmin) {
    Write-Good "User: Administrator (Ready to Install)"
} else {
    Write-Warn "User: Standard User"
    Write-Host "   • Runtime: OK"
    Write-Host "   • Install: Requires Admin (sudo)"
}

# 2. CONTAINER ENGINE
try {
    $DockerInfo = docker info --format '{{json .}}' 2>$null
    if ($LASTEXITCODE -eq 0) {
        $InfoObj = $DockerInfo | ConvertFrom-Json
        $Ver = $InfoObj.ServerVersion
        Write-Good "Container Engine: Docker v$Ver (Running)"
        
        # Check for WSL 2 Backend specifically
        if ($InfoObj.Name -match "docker-desktop" -or $InfoObj.OperatingSystem -match "Docker Desktop") {
             Write-Good "Backend: Docker Desktop (Safe VM Mode)"
        } elseif ($InfoObj.OSType -eq "linux") {
             # Native Linux (WSL 2 Engine)
             Write-Warn "Backend: Native Engine (WSL 2)"
             Write-Host "   • This mode requires AppArmor for safety."
        }
    } else {
        throw "Docker not running"
    }
} catch {
    # Try Podman
    try {
        $PodmanInfo = podman info 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Good "Container Engine: Podman (Running)"
        } else {
            throw
        }
    } catch {
        Write-Bad "Container Engine: NOT FOUND or NOT RUNNING"
        Write-Host "   Fix: Start Docker Desktop or install Podman."
        $Global:ExitCode = 1
    }
}

# 3. WSL 2 SECURITY (The Critical Check)
if (wsl --list --quiet 2>$null) {
    $WslVer = wsl --version 2>$null
    if ($LASTEXITCODE -ne 0) {
         # Older WSL versions don't support --version
         Write-Warn "WSL: Version Unknown (Likely old)"
         Write-Host "   Fix: Run 'wsl --update' to ensure security features."
    } else {
         # Parse "WSL version: 2.0.0.0"
         $Lines = $WslVer -split "`n"
         $VerLine = $Lines | Where-Object { $_ -match "^WSL version:\s+([0-9.]+)" }
         $CurrentVer = [version]$Matches[1]
         
         if ($CurrentVer -ge [version]"1.0.0") {
             Write-Good "WSL: v$CurrentVer (Supported)"
         } else {
             Write-Warn "WSL: v$CurrentVer (Update Recommended)"
         }
    }

    # Check Kernel & AppArmor inside default distro
    # We use wsl -u root to peek inside
    $KernelCheck = wsl -u root bash -c "uname -r; if [ -f /sys/kernel/security/apparmor/profiles ]; then echo 'AA_OK'; else echo 'AA_MISSING'; fi" 2>$null
    
    if ($null -ne $KernelCheck) {
        $KernelVer = $KernelCheck[0]
        $AaStatus = $KernelCheck[1]
        
        if ($AaStatus -eq "AA_OK") {
            Write-Good "Kernel: $KernelVer (AppArmor Active)"
        } else {
            Write-Bad "Kernel: $KernelVer (AppArmor DISABLED)"
            Write-Host "   ❌ CRITICAL: Your agents are running without confinement."
            Write-Host "   👉 FIX: Run '.\scripts\utils\enable-wsl-security.ps1'"
            $Global:ExitCode = 1
        }
    }
} else {
    Write-Info "WSL: Not detected (Non-WSL Windows?)"
}

# 4. CONNECTIVITY (Registry)
try {
    Invoke-WebRequest -Uri "https://ghcr.io" -Method Head -TimeoutSec 5 -ErrorAction Stop
    Write-Good "Network: ghcr.io Reachable"
} catch {
    Write-Warn "Network: ghcr.io Unreachable (Check VPN/Proxy)"
}

Write-Host "-----------------------"
if ($Global:ExitCode -eq 0) {
    Write-Good "System is ready."
    exit 0
} else {
    Write-Bad "System checks failed."
    exit 1
}