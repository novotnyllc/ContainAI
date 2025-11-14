# Verify that all prerequisites for CodingAgents are installed and configured
# Usage: .\scripts\verify-prerequisites.ps1

# Suppress Write-Host warnings - this is a user-facing verification script
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='User-facing output script')]
param()

$ErrorActionPreference = "Continue"  # Don't stop on errors, we want to check everything

# Counters
$script:Passed = 0
$script:Failed = 0
$script:Warnings = 0

# Output functions
function Write-Checking {
    param([string]$Message)
    Write-Host "⏳ Checking: " -NoNewline -ForegroundColor Blue
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ " -NoNewline -ForegroundColor Green
    Write-Host $Message
    $script:Passed++
}

function Write-ErrorMsg {
    param([string]$Message, [string]$Hint = "")
    Write-Host "✗ " -NoNewline -ForegroundColor Red
    Write-Host $Message
    if ($Hint) {
        Write-Host "         $Hint" -ForegroundColor Gray
    }
    $script:Failed++
}

function Write-WarningMsg {
    param([string]$Message, [string]$Hint = "")
    Write-Host "⚠ " -NoNewline -ForegroundColor Yellow
    Write-Host $Message
    if ($Hint) {
        Write-Host "         $Hint" -ForegroundColor Gray
    }
    $script:Warnings++
}

function Write-InfoMsg {
    param([string]$Message, [string]$Hint = "")
    Write-Host "ℹ  " -NoNewline -ForegroundColor Yellow
    Write-Host $Message
    if ($Hint) {
        Write-Host "         $Hint" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  CodingAgents Prerequisites Check" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker or Podman installation
Write-Checking "Container runtime (Docker or Podman)"
$script:ContainerCmd = ""
try {
    $dockerVersion = (docker --version 2>$null | Select-String -Pattern '\d+\.\d+\.\d+').Matches[0].Value
    if ($dockerVersion) {
        Write-Success "Docker installed (version $dockerVersion)"
        $script:ContainerCmd = "docker"

        # Check if Docker version is recent enough (20.10.0+)
        $versionParts = $dockerVersion.Split('.')
        $major = [int]$versionParts[0]
        $minor = [int]$versionParts[1]

        if ($major -lt 20 -or ($major -eq 20 -and $minor -lt 10)) {
            Write-WarningMsg "Docker version $dockerVersion is old. Recommend 20.10.0+"
        }
    } else {
        throw "Version not detected"
    }
} catch {
    # Try Podman
    try {
        $podmanVersion = (podman --version 2>$null | Select-String -Pattern '\d+\.\d+\.\d+').Matches[0].Value
        if ($podmanVersion) {
            Write-Success "Podman installed (version $podmanVersion)"
            $script:ContainerCmd = "podman"

            # Check if Podman version is recent enough (3.0.0+)
            $versionParts = $podmanVersion.Split('.')
            $major = [int]$versionParts[0]

            if ($major -lt 3) {
                Write-WarningMsg "Podman version $podmanVersion is old. Recommend 3.0.0+"
            }
        } else {
            throw "Version not detected"
        }
    } catch {
        Write-ErrorMsg "Neither Docker nor Podman is installed" "Install Docker from: https://docs.docker.com/get-docker/ or Podman from: https://podman.io/getting-started/installation"
    }
}

# Check if container runtime is running
if ($script:ContainerCmd) {
    Write-Checking "$($script:ContainerCmd) daemon status"
    try {
        if ($script:ContainerCmd -eq "docker") {
            $null = docker info 2>&1
        } else {
            $null = podman info 2>&1
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$($script:ContainerCmd) daemon is running"
        } else {
            if ($script:ContainerCmd -eq "docker") {
                Write-ErrorMsg "Docker daemon is not running" "Start Docker Desktop"
            } else {
                Write-ErrorMsg "Podman service is not running" "Start Podman service"
            }
        }
    } catch {
        if ($script:ContainerCmd -eq "docker") {
            Write-ErrorMsg "Docker daemon is not running" "Start Docker Desktop"
        } else {
            Write-ErrorMsg "Podman service is not running" "Start Podman service"
        }
    }
}

# Check WSL (Windows only)
if ($IsWindows -or $env:OS -match "Windows") {
    Write-Checking "WSL2 availability"
    try {
        $wslVersion = wsl --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $version = ($wslVersion | Select-String -Pattern 'WSL version:\s*(\S+)').Matches[0].Groups[1].Value
            if ($version) {
                Write-Success "WSL installed (version $version)"
            } else {
                Write-Success "WSL installed"
            }
        } else {
            Write-WarningMsg "WSL not detected" "Docker Desktop requires WSL2 on Windows"
        }
    } catch {
        Write-WarningMsg "WSL not detected" "Docker Desktop requires WSL2 on Windows"
    }
}

# Check Git installation
Write-Checking "Git installation"
try {
    $gitVersion = (git --version 2>$null | Select-String -Pattern '\d+\.\d+\.\d+').Matches[0].Value
    if ($gitVersion) {
        Write-Success "Git installed (version $gitVersion)"
    } else {
        throw "Version not detected"
    }
} catch {
    Write-ErrorMsg "Git is not installed" "Install from: https://git-scm.com/downloads"
}

# Check Git configuration
Write-Checking "Git user.name configuration"
try {
    $gitName = git config --global user.name 2>$null
    if ($gitName -and $gitName.Trim()) {
        Write-Success "Git user.name configured: $gitName"
    } else {
        Write-ErrorMsg "Git user.name not configured" 'Run: git config --global user.name "Your Name"'
    }
} catch {
    Write-ErrorMsg "Git user.name not configured" 'Run: git config --global user.name "Your Name"'
}

Write-Checking "Git user.email configuration"
try {
    $gitEmail = git config --global user.email 2>$null
    if ($gitEmail -and $gitEmail.Trim()) {
        Write-Success "Git user.email configured: $gitEmail"
    } else {
        Write-ErrorMsg "Git user.email not configured" 'Run: git config --global user.email "your@email.com"'
    }
} catch {
    Write-ErrorMsg "Git user.email not configured" 'Run: git config --global user.email "your@email.com"'
}

# Check socat installation (in WSL for Windows, native for Linux/Mac)
Write-Checking "socat installation"
try {
    if ($IsWindows -or $env:OS -match "Windows") {
        # On Windows, check if socat is available in WSL
        $socatCheck = wsl bash -c "command -v socat" 2>$null
        if ($LASTEXITCODE -eq 0 -and $socatCheck) {
            $socatVersion = wsl bash -c "socat -V 2>&1 | head -1 | grep -oP 'socat version \K[\d.]+'" 2>$null
            if ($socatVersion) {
                Write-Success "socat installed in WSL (version $socatVersion)"
            } else {
                Write-Success "socat installed in WSL"
            }
        } else {
            Write-ErrorMsg "socat is not installed in WSL (required for credential/GPG proxy)" "Install in WSL: wsl sudo apt-get install socat"
        }
    } else {
        # On Linux/Mac, check directly
        $socatVersion = (socat -V 2>&1 | Select-Object -First 1 | Select-String -Pattern 'socat version ([\d.]+)').Matches[0].Groups[1].Value
        if ($socatVersion) {
            Write-Success "socat installed (version $socatVersion)"
        } else {
            throw "Version not detected"
        }
    }
} catch {
    if ($IsMacOS) {
        Write-ErrorMsg "socat is not installed (required for credential/GPG proxy)" "Install: brew install socat"
    } else {
        Write-ErrorMsg "socat is not installed (required for credential/GPG proxy)" "Install using your package manager"
    }
}

# Check GitHub CLI installation
Write-Checking "GitHub CLI installation"
try {
    $ghVersion = (gh --version 2>$null | Select-Object -First 1 | Select-String -Pattern '\d+\.\d+\.\d+').Matches[0].Value
    if ($ghVersion) {
        Write-Success "GitHub CLI installed (version $ghVersion)"
    } else {
        throw "Version not detected"
    }
} catch {
    Write-ErrorMsg "GitHub CLI is not installed" "Install from: https://cli.github.com/"
}

# Check GitHub CLI authentication
Write-Checking "GitHub CLI authentication"
try {
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        # Try to get username
        try {
            $ghUser = (gh api user --jq .login 2>$null)
            if ($ghUser) {
                Write-Success "GitHub CLI authenticated (user: $ghUser)"
            } else {
                Write-Success "GitHub CLI authenticated"
            }
        } catch {
            Write-Success "GitHub CLI authenticated"
        }
    } else {
        Write-ErrorMsg "GitHub CLI is not authenticated" "Run: gh auth login"
    }
} catch {
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Write-ErrorMsg "GitHub CLI is not authenticated" "Run: gh auth login"
    } else {
        Write-ErrorMsg "Cannot check authentication (gh not installed)"
    }
}

# Check disk space
Write-Checking "Available disk space"
try {
    $drive = (Get-Location).Drive
    if ($drive) {
        $freeSpaceGB = [math]::Round($drive.Free / 1GB, 1)

        if ($freeSpaceGB -ge 5.0) {
            Write-Success "Disk space available: $freeSpaceGB GB"
        } elseif ($freeSpaceGB -ge 3.0) {
            Write-WarningMsg "Disk space available: $freeSpaceGB GB (recommend 5GB+)"
        } else {
            Write-ErrorMsg "Disk space available: $freeSpaceGB GB (need at least 5GB)" "Free up disk space or choose different location"
        }
    } else {
        Write-WarningMsg "Cannot determine drive information"
    }
} catch {
    Write-WarningMsg "Cannot check disk space"
}

# Check for optional tools
Write-Host ""
Write-Host "Optional Tools:" -ForegroundColor Cyan
Write-Host "---------------" -ForegroundColor Cyan

# VS Code
Write-Checking "VS Code installation"
if (Get-Command code -ErrorAction SilentlyContinue) {
    try {
        $codeVersion = (code --version 2>$null | Select-Object -First 1)
        if ($codeVersion) {
            Write-Success "VS Code installed (for Dev Containers integration)"
        } else {
            Write-Success "VS Code installed"
        }
    } catch {
        Write-Success "VS Code installed"
    }
} else {
    Write-InfoMsg "VS Code not found (optional, but recommended)" "Install from: https://code.visualstudio.com/"
}

# jq (useful for MCP config)
Write-Checking "jq installation"
if (Get-Command jq -ErrorAction SilentlyContinue) {
    try {
        $jqVersion = (jq --version 2>$null | Select-String -Pattern '\d+\.\d+').Matches[0].Value
        if ($jqVersion) {
            Write-Success "jq installed (version $jqVersion)"
        } else {
            Write-Success "jq installed"
        }
    } catch {
        Write-Success "jq installed"
    }
} else {
    Write-InfoMsg "jq not found (optional, useful for JSON processing)"
}

# yq (useful for MCP config)
Write-Checking "yq installation"
if (Get-Command yq -ErrorAction SilentlyContinue) {
    try {
        $yqVersion = (yq --version 2>$null | Select-String -Pattern '\d+\.\d+\.\d+').Matches[0].Value
        if ($yqVersion) {
            Write-Success "yq installed (version $yqVersion)"
        } else {
            Write-Success "yq installed"
        }
    } catch {
        Write-Success "yq installed"
    }
} else {
    Write-InfoMsg "yq not found (optional, useful for YAML processing)"
}

# Summary
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Passed:   " -NoNewline -ForegroundColor Green
Write-Host $script:Passed
Write-Host "Warnings: " -NoNewline -ForegroundColor Yellow
Write-Host $script:Warnings
Write-Host "Failed:   " -NoNewline -ForegroundColor Red
Write-Host $script:Failed
Write-Host ""

if ($script:Failed -eq 0) {
    if ($script:Warnings -eq 0) {
        Write-Host "✓ All prerequisites met! " -NoNewline -ForegroundColor Green
        Write-Host "You're ready to use CodingAgents."
        Write-Host ""
        Write-Host "Next steps:"
        Write-Host "  1. Get images:      docker pull ghcr.io/novotnyllc/coding-agents-copilot:latest"
        Write-Host "  2. Install scripts: .\scripts\install.ps1"
        Write-Host "  3. First launch:    run-copilot"
        exit 0
    } else {
        Write-Host "⚠ Prerequisites met with warnings." -ForegroundColor Yellow
        Write-Host "You can proceed, but consider addressing warnings above."
        exit 0
    }
} else {
    Write-Host "✗ Some prerequisites are missing." -ForegroundColor Red
    Write-Host "Please address the errors above before using CodingAgents."
    Write-Host ""
    Write-Host "See docs\getting-started.md for detailed setup instructions."
    exit 1
}
