# Verify that all prerequisites for CodingAgents are installed and configured
# Usage: .\scripts\verify-prerequisites.ps1

$ErrorActionPreference = "Continue"  # Don't stop on errors, we want to check everything

# Counters
$script:Passed = 0
$script:Failed = 0
$script:Warnings = 0

# Print functions
function Print-Checking {
    param([string]$Message)
    Write-Host "⏳ Checking: " -NoNewline -ForegroundColor Blue
    Write-Host $Message
}

function Print-Success {
    param([string]$Message)
    Write-Host "✓ " -NoNewline -ForegroundColor Green
    Write-Host $Message
    $script:Passed++
}

function Print-Error {
    param([string]$Message, [string]$Hint = "")
    Write-Host "✗ " -NoNewline -ForegroundColor Red
    Write-Host $Message
    if ($Hint) {
        Write-Host "         $Hint" -ForegroundColor Gray
    }
    $script:Failed++
}

function Print-Warning {
    param([string]$Message, [string]$Hint = "")
    Write-Host "⚠ " -NoNewline -ForegroundColor Yellow
    Write-Host $Message
    if ($Hint) {
        Write-Host "         $Hint" -ForegroundColor Gray
    }
    $script:Warnings++
}

function Print-Info {
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
Print-Checking "Container runtime (Docker or Podman)"
$script:ContainerCmd = ""
try {
    $dockerVersion = (docker --version 2>$null | Select-String -Pattern '\d+\.\d+\.\d+').Matches[0].Value
    if ($dockerVersion) {
        Print-Success "Docker installed (version $dockerVersion)"
        $script:ContainerCmd = "docker"
        
        # Check if Docker version is recent enough (20.10.0+)
        $versionParts = $dockerVersion.Split('.')
        $major = [int]$versionParts[0]
        $minor = [int]$versionParts[1]
        
        if ($major -lt 20 -or ($major -eq 20 -and $minor -lt 10)) {
            Print-Warning "Docker version $dockerVersion is old. Recommend 20.10.0+"
        }
    } else {
        throw "Version not detected"
    }
} catch {
    # Try Podman
    try {
        $podmanVersion = (podman --version 2>$null | Select-String -Pattern '\d+\.\d+\.\d+').Matches[0].Value
        if ($podmanVersion) {
            Print-Success "Podman installed (version $podmanVersion)"
            $script:ContainerCmd = "podman"
            
            # Check if Podman version is recent enough (3.0.0+)
            $versionParts = $podmanVersion.Split('.')
            $major = [int]$versionParts[0]
            
            if ($major -lt 3) {
                Print-Warning "Podman version $podmanVersion is old. Recommend 3.0.0+"
            }
        } else {
            throw "Version not detected"
        }
    } catch {
        Print-Error "Neither Docker nor Podman is installed" "Install Docker from: https://docs.docker.com/get-docker/ or Podman from: https://podman.io/getting-started/installation"
    }
}

# Check if container runtime is running
if ($script:ContainerCmd) {
    Print-Checking "$($script:ContainerCmd) daemon status"
    try {
        if ($script:ContainerCmd -eq "docker") {
            $null = docker info 2>&1
        } else {
            $null = podman info 2>&1
        }
        if ($LASTEXITCODE -eq 0) {
            Print-Success "$($script:ContainerCmd) daemon is running"
        } else {
            if ($script:ContainerCmd -eq "docker") {
                Print-Error "Docker daemon is not running" "Start Docker Desktop"
            } else {
                Print-Error "Podman service is not running" "Start Podman service"
            }
        }
    } catch {
        if ($script:ContainerCmd -eq "docker") {
            Print-Error "Docker daemon is not running" "Start Docker Desktop"
        } else {
            Print-Error "Podman service is not running" "Start Podman service"
        }
    }
}

# Check WSL (Windows only)
if ($IsWindows -or $env:OS -match "Windows") {
    Print-Checking "WSL2 availability"
    try {
        $wslVersion = wsl --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $version = ($wslVersion | Select-String -Pattern 'WSL version:\s*(\S+)').Matches[0].Groups[1].Value
            if ($version) {
                Print-Success "WSL installed (version $version)"
            } else {
                Print-Success "WSL installed"
            }
        } else {
            Print-Warning "WSL not detected" "Docker Desktop requires WSL2 on Windows"
        }
    } catch {
        Print-Warning "WSL not detected" "Docker Desktop requires WSL2 on Windows"
    }
}

# Check Git installation
Print-Checking "Git installation"
try {
    $gitVersion = (git --version 2>$null | Select-String -Pattern '\d+\.\d+\.\d+').Matches[0].Value
    if ($gitVersion) {
        Print-Success "Git installed (version $gitVersion)"
    } else {
        throw "Version not detected"
    }
} catch {
    Print-Error "Git is not installed" "Install from: https://git-scm.com/downloads"
}

# Check Git configuration
Print-Checking "Git user.name configuration"
try {
    $gitName = git config --global user.name 2>$null
    if ($gitName -and $gitName.Trim()) {
        Print-Success "Git user.name configured: $gitName"
    } else {
        Print-Error "Git user.name not configured" 'Run: git config --global user.name "Your Name"'
    }
} catch {
    Print-Error "Git user.name not configured" 'Run: git config --global user.name "Your Name"'
}

Print-Checking "Git user.email configuration"
try {
    $gitEmail = git config --global user.email 2>$null
    if ($gitEmail -and $gitEmail.Trim()) {
        Print-Success "Git user.email configured: $gitEmail"
    } else {
        Print-Error "Git user.email not configured" 'Run: git config --global user.email "your@email.com"'
    }
} catch {
    Print-Error "Git user.email not configured" 'Run: git config --global user.email "your@email.com"'
}

# Check GitHub CLI installation
Print-Checking "GitHub CLI installation"
try {
    $ghVersion = (gh --version 2>$null | Select-Object -First 1 | Select-String -Pattern '\d+\.\d+\.\d+').Matches[0].Value
    if ($ghVersion) {
        Print-Success "GitHub CLI installed (version $ghVersion)"
    } else {
        throw "Version not detected"
    }
} catch {
    Print-Error "GitHub CLI is not installed" "Install from: https://cli.github.com/"
}

# Check GitHub CLI authentication
Print-Checking "GitHub CLI authentication"
try {
    $ghStatus = gh auth status 2>&1
    if ($LASTEXITCODE -eq 0) {
        # Try to get username
        try {
            $ghUser = (gh api user --jq .login 2>$null)
            if ($ghUser) {
                Print-Success "GitHub CLI authenticated (user: $ghUser)"
            } else {
                Print-Success "GitHub CLI authenticated"
            }
        } catch {
            Print-Success "GitHub CLI authenticated"
        }
    } else {
        Print-Error "GitHub CLI is not authenticated" "Run: gh auth login"
    }
} catch {
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Print-Error "GitHub CLI is not authenticated" "Run: gh auth login"
    } else {
        Print-Error "Cannot check authentication (gh not installed)"
    }
}

# Check disk space
Print-Checking "Available disk space"
try {
    $drive = (Get-Location).Drive
    if ($drive) {
        $freeSpaceGB = [math]::Round($drive.Free / 1GB, 1)
        
        if ($freeSpaceGB -ge 5.0) {
            Print-Success "Disk space available: $freeSpaceGB GB"
        } elseif ($freeSpaceGB -ge 3.0) {
            Print-Warning "Disk space available: $freeSpaceGB GB (recommend 5GB+)"
        } else {
            Print-Error "Disk space available: $freeSpaceGB GB (need at least 5GB)" "Free up disk space or choose different location"
        }
    } else {
        Print-Warning "Cannot determine drive information"
    }
} catch {
    Print-Warning "Cannot check disk space"
}

# Check for optional tools
Write-Host ""
Write-Host "Optional Tools:" -ForegroundColor Cyan
Write-Host "---------------" -ForegroundColor Cyan

# VS Code
Print-Checking "VS Code installation"
if (Get-Command code -ErrorAction SilentlyContinue) {
    try {
        $codeVersion = (code --version 2>$null | Select-Object -First 1)
        if ($codeVersion) {
            Print-Success "VS Code installed (for Dev Containers integration)"
        } else {
            Print-Success "VS Code installed"
        }
    } catch {
        Print-Success "VS Code installed"
    }
} else {
    Print-Info "VS Code not found (optional, but recommended)" "Install from: https://code.visualstudio.com/"
}

# jq (useful for MCP config)
Print-Checking "jq installation"
if (Get-Command jq -ErrorAction SilentlyContinue) {
    try {
        $jqVersion = (jq --version 2>$null | Select-String -Pattern '\d+\.\d+').Matches[0].Value
        if ($jqVersion) {
            Print-Success "jq installed (version $jqVersion)"
        } else {
            Print-Success "jq installed"
        }
    } catch {
        Print-Success "jq installed"
    }
} else {
    Print-Info "jq not found (optional, useful for JSON processing)"
}

# yq (useful for MCP config)
Print-Checking "yq installation"
if (Get-Command yq -ErrorAction SilentlyContinue) {
    try {
        $yqVersion = (yq --version 2>$null | Select-String -Pattern '\d+\.\d+\.\d+').Matches[0].Value
        if ($yqVersion) {
            Print-Success "yq installed (version $yqVersion)"
        } else {
            Print-Success "yq installed"
        }
    } catch {
        Print-Success "yq installed"
    }
} else {
    Print-Info "yq not found (optional, useful for YAML processing)"
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
