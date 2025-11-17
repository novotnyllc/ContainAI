# Common functions for agent management scripts (PowerShell)

$script:ConfigRoot = if ($env:CODING_AGENTS_HOST_CONFIG) {
    Split-Path -Parent $env:CODING_AGENTS_HOST_CONFIG
} else {
    $homePath = if ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath('UserProfile') }
    Join-Path $homePath ".config/coding-agents"
}

$script:HostConfigFile = if ($env:CODING_AGENTS_HOST_CONFIG) {
    $env:CODING_AGENTS_HOST_CONFIG
} else {
    Join-Path $script:ConfigRoot "host-config.env"
}

$script:DefaultLauncherUpdatePolicy = "prompt"
$script:ContainerCli = $null

function Get-ContainerCli {
    if ($script:ContainerCli) {
        return $script:ContainerCli
    }

    $runtime = Get-ContainerRuntime
    if (-not $runtime) {
        $runtime = "docker"
    }
    $script:ContainerCli = $runtime
    return $script:ContainerCli
}

function Invoke-ContainerCli {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true, Position = 0)]
        [string[]]$CliArgs
    )

    $cli = Get-ContainerCli
    & $cli @CliArgs
}

function Get-HostConfigValue {
    param([Parameter(Mandatory = $true)][string]$Key)

    if (-not (Test-Path $script:HostConfigFile)) {
        return $null
    }

    $pattern = "^\s*$Key\s*="
    $line = Get-Content $script:HostConfigFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -match $pattern } |
        Select-Object -Last 1

    if (-not $line) {
        return $null
    }

    $value = $line.Substring($line.IndexOf('=') + 1).Trim()
    $value = $value.Trim('"').Trim("'")
    return $value
}

function Get-LauncherUpdatePolicy {
    $value = $env:CODING_AGENTS_LAUNCHER_UPDATE_POLICY
    if (-not $value) {
        $value = Get-HostConfigValue -Key "LAUNCHER_UPDATE_POLICY"
    }

    switch ($value?.ToLower()) {
        'always' { return 'always' }
        'never'  { return 'never' }
        'prompt' { return 'prompt' }
        $null    { return $script:DefaultLauncherUpdatePolicy }
        default  { return $script:DefaultLauncherUpdatePolicy }
    }
}

function Invoke-LauncherUpdateCheck {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $false)][string]$Context
    )

    if ($env:CODING_AGENTS_SKIP_UPDATE_CHECK -eq '1') {
        return
    }

    $policy = Get-LauncherUpdatePolicy
    if ($policy -eq 'never') {
        return
    }

    if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
        return
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "⚠️  Skipping launcher update check (git not available)" -ForegroundColor Yellow
        return
    }

    git -C $RepoRoot rev-parse HEAD 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return
    }

    $upstream = git -C $RepoRoot rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $upstream) {
        return
    }

    git -C $RepoRoot fetch --quiet --tags 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️  Unable to check launcher updates (git fetch failed)" -ForegroundColor Yellow
        return
    }

    $localHead = git -C $RepoRoot rev-parse HEAD 2>$null
    $remoteHead = git -C $RepoRoot rev-parse '@{u}' 2>$null
    $base = git -C $RepoRoot merge-base HEAD '@{u}' 2>$null

    if ($localHead -eq $remoteHead) {
        return
    }

    if ($localHead -ne $base -and $remoteHead -ne $base) {
        Write-Host "⚠️  Launcher repository has diverged from $upstream. Please sync manually." -ForegroundColor Yellow
        return
    }

    $clean = $true
    git -C $RepoRoot diff --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { $clean = $false }
    if ($clean) {
        git -C $RepoRoot diff --quiet --cached 2>$null
        if ($LASTEXITCODE -ne 0) { $clean = $false }
    }

    if ($policy -eq 'always') {
        if (-not $clean) {
            Write-Host "⚠️  Launcher repository has local changes; cannot auto-update." -ForegroundColor Yellow
            return
        }
        git -C $RepoRoot pull --ff-only | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Launcher scripts updated to match $upstream" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Failed to auto-update launcher scripts. Please update manually." -ForegroundColor Yellow
        }
        return
    }

    $canPrompt = $true
    try {
        if ([Console]::IsInputRedirected) {
            $canPrompt = $false
        }
    } catch {
        $canPrompt = $false
    }

    if (-not $canPrompt) {
        Write-Host "⚠️  Launcher scripts are behind $upstream. Update the repository when convenient." -ForegroundColor Yellow
        return
    }

    $suffix = if ($Context) { " ($Context)" } else { "" }
    Write-Host "ℹ️  Launcher scripts are behind $upstream.$suffix" -ForegroundColor Cyan
    if (-not $clean) {
        Write-Host "   Local changes detected; please update manually." -ForegroundColor Yellow
        return
    }

    $response = Read-Host "Update Coding Agents launchers now? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($response)) { $response = "y" }
    if ($response.StartsWith('y', 'InvariantCultureIgnoreCase')) {
        git -C $RepoRoot pull --ff-only | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Launcher scripts updated." -ForegroundColor Green
        } else {
            Write-Host "⚠️  Failed to update launchers. Please update manually." -ForegroundColor Yellow
        }
    } else {
        Write-Host "⏭️  Skipped launcher update." -ForegroundColor Yellow
    }
}

function Get-ContainerRuntime {
    <#
    .SYNOPSIS
        Detects available container runtime (docker or podman)
    
    .DESCRIPTION
        Checks for CONTAINER_RUNTIME environment variable first,
        then auto-detects docker or podman (prefers docker).
    
    .OUTPUTS
        String: "docker" or "podman"
    #>
    
    # Check environment variable first
    if ($env:CONTAINER_RUNTIME) {
        $cmd = Get-Command $env:CONTAINER_RUNTIME -ErrorAction SilentlyContinue
        if ($cmd) {
            return $env:CONTAINER_RUNTIME
        }
    }
    
    # Auto-detect: prefer docker, fall back to podman
    try {
        $null = docker info 2>$null
        if ($LASTEXITCODE -eq 0) {
            return "docker"
        }
    } catch { }
    
    try {
        $null = podman info 2>$null
        if ($LASTEXITCODE -eq 0) {
            return "podman"
        }
    } catch { }
    
    # Check if either command exists (even if not running)
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        return "docker"
    }
    if (Get-Command podman -ErrorAction SilentlyContinue) {
        return "podman"
    }
    
    # Neither found
    return $null
}

function Test-ValidContainerName {
    param([string]$Name)
    # Container names must match: [a-zA-Z0-9][a-zA-Z0-9_.-]*
    if ($Name -match '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$') {
        return $true
    }
    return $false
}

function Test-ValidBranchName {
    param([string]$Branch)
    # Basic git branch name validation - no spaces, no special chars that git doesn't allow
    if ($Branch -match '^[a-zA-Z0-9][a-zA-Z0-9/_.-]*$' -and $Branch -notmatch '\.\.' -and $Branch -notmatch '/$') {
        return $true
    }
    return $false
}

function Test-ValidImageName {
    param([string]$Image)
    # Docker image name validation
    if ($Image -match '^[a-z0-9]+(([._-]|__)[a-z0-9]+)*(:[a-zA-Z0-9_.-]+)?$') {
        return $true
    }
    return $false
}

function Test-BranchExists {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Exists is semantically correct for testing existence')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoPath,
        
        [Parameter(Mandatory=$true)]
        [string]$BranchName
    )
    
    Push-Location $RepoPath
    try {
        git show-ref --verify --quiet "refs/heads/$BranchName" 2>$null
        return ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
}

function Get-UnmergedCommits {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Returns multiple commits - plural is correct')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoPath,
        
        [Parameter(Mandatory=$true)]
        [string]$BaseBranch,
        
        [Parameter(Mandatory=$true)]
        [string]$CompareBranch
    )
    
    Push-Location $RepoPath
    try {
        $commits = git log "$BaseBranch..$CompareBranch" --oneline 2>$null
        return $commits
    } finally {
        Pop-Location
    }
}

function Remove-GitBranch {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoPath,
        
        [Parameter(Mandatory=$true)]
        [string]$BranchName,
        
        [Parameter(Mandatory=$false)]
        [bool]$Force = $false
    )
    
    if ($PSCmdlet.ShouldProcess($BranchName, "Remove git branch")) {
        Push-Location $RepoPath
        try {
            $flag = if ($Force) { "-D" } else { "-d" }
            git branch $flag $BranchName 2>$null | Out-Null
            return ($LASTEXITCODE -eq 0)
        } finally {
            Pop-Location
        }
    }
    return $false
}

function Rename-GitBranch {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoPath,
        
        [Parameter(Mandatory=$true)]
        [string]$OldName,
        
        [Parameter(Mandatory=$true)]
        [string]$NewName
    )
    
    Push-Location $RepoPath
    try {
        git branch -m $OldName $NewName 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
}

function New-GitBranch {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoPath,
        
        [Parameter(Mandatory=$true)]
        [string]$BranchName,
        
        [Parameter(Mandatory=$false)]
        [string]$StartPoint = "HEAD"
    )
    
    if ($PSCmdlet.ShouldProcess($BranchName, "Create git branch")) {
        Push-Location $RepoPath
        try {
            git branch $BranchName $StartPoint 2>$null | Out-Null
            return ($LASTEXITCODE -eq 0)
        } finally {
            Pop-Location
        }
    }
    return $false
}

function Get-RepoName {
    param([string]$RepoPath)
    Split-Path -Leaf $RepoPath
}

function Get-CurrentBranch {
    param([string]$RepoPath)
    Push-Location $RepoPath
    $branch = git branch --show-current 2>$null
    Pop-Location
    if ($branch) { return $branch } else { return "main" }
}

function ConvertTo-SafeBranchName {
    <#
    .SYNOPSIS
        Sanitizes a branch name for use in Docker container names
    
    .DESCRIPTION
        Converts a git branch name to a safe format for Docker container naming:
        - Replaces slashes and backslashes with dashes
        - Replaces invalid characters with dashes
        - Collapses multiple dashes
        - Removes leading/trailing special characters
        - Converts to lowercase
    
    .PARAMETER BranchName
        The git branch name to sanitize
    
    .EXAMPLE
        ConvertTo-SafeBranchName "feature/auth-module"
        Returns: "feature-auth-module"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$BranchName
    )
    
    # Replace slashes with dashes
    $sanitized = $BranchName -replace '[/\\]', '-'
    
    # Replace any other invalid characters with dashes
    $sanitized = $sanitized -replace '[^a-zA-Z0-9._-]', '-'
    
    # Collapse multiple dashes
    $sanitized = $sanitized -replace '-+', '-'
    
    # Remove leading special characters
    $sanitized = $sanitized -replace '^[._-]+', ''
    
    # Remove trailing special characters
    $sanitized = $sanitized -replace '[._-]+$', ''
    
    # Convert to lowercase
    $sanitized = $sanitized.ToLower()
    
    # Ensure non-empty result
    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        $sanitized = "branch"
    }
    
    return $sanitized
}

function Convert-WindowsPathToWsl {
    <#
    .SYNOPSIS
        Converts Windows paths to WSL paths
    
    .DESCRIPTION
        Converts Windows-style paths (e.g., C:\path\to\file) to WSL-style paths (/mnt/c/path/to/file)
    
    .PARAMETER Path
        The Windows path to convert
    
    .EXAMPLE
        Convert-WindowsPathToWsl "C:\dev\project"
        Returns: "/mnt/c/dev/project"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    # Check if path matches Windows drive letter pattern (C:, D:, etc.)
    if ($Path -match '^([A-Z]):(.*)'  ) {
        $drive = $Matches[1].ToLower()
        $rest = $Matches[2] -replace '\\', '/'
        return "/mnt/$drive$rest"
    }
    
    # Return unchanged if not a Windows path
    return $Path
}

function Test-DockerRunning {
    <#
    .SYNOPSIS
        Checks if container runtime (Docker/Podman) is running
    
    .DESCRIPTION
        Checks Docker or Podman availability and provides helpful error messages.
        On Windows with Docker, attempts to auto-start Docker Desktop if installed.
    
    .EXAMPLE
        if (-not (Test-DockerRunning)) {
            exit 1
        }
    #>
    
    $runtime = Get-ContainerRuntime
    
    if ($runtime) {
        # Check if runtime is running
        try {
            $null = & $runtime info 2>$null
            if ($LASTEXITCODE -eq 0) {
                $script:ContainerCli = $runtime
                return $true
            }
        } catch { }
    }
    
    Write-Host "⚠️  Container runtime not running. Checking installation..." -ForegroundColor Yellow
    
    # Try docker first
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    $podmanCmd = Get-Command podman -ErrorAction SilentlyContinue
    
    if (-not $dockerCmd -and -not $podmanCmd) {
        Write-Host "❌ No container runtime found. Please install one:" -ForegroundColor Red
        Write-Host "   Docker: https://www.docker.com/products/docker-desktop" -ForegroundColor Cyan
        Write-Host "   Podman: https://podman.io/getting-started/installation" -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Red
        Write-Host "   For Windows: Download Docker Desktop or Podman Desktop" -ForegroundColor Cyan
        Write-Host "   For Mac: Download Docker Desktop or brew install podman" -ForegroundColor Cyan
        Write-Host "   For Linux: Use your package manager" -ForegroundColor Cyan
        return $false
    }
    
    # If podman is available and docker is not (or not running)
    if ($podmanCmd -and (-not $dockerCmd -or $runtime -eq "podman")) {
        Write-Host "ℹ️  Using Podman as container runtime" -ForegroundColor Cyan
        
        try {
            $null = podman info 2>$null
            if ($LASTEXITCODE -eq 0) {
                $script:ContainerCli = "podman"
                return $true
            }
        } catch { }
        
        Write-Host "❌ Podman is installed but not working properly" -ForegroundColor Red
        Write-Host "   Try: podman machine init && podman machine start" -ForegroundColor Cyan
        return $false
    }
    
    # Docker is installed but not running
    Write-Host "Docker is installed but not running." -ForegroundColor Yellow
    
    # On Windows, try to start Docker Desktop
    if ($IsWindows -or $env:OS -match 'Windows') {
        Write-Host "Attempting to start Docker Desktop..." -ForegroundColor Cyan
        
        # Find Docker Desktop executable
        $dockerDesktopPaths = @(
            "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
            "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
            "$env:LOCALAPPDATA\Docker\Docker Desktop.exe"
        )
        
        $dockerDesktop = $null
        foreach ($path in $dockerDesktopPaths) {
            if (Test-Path $path) {
                $dockerDesktop = $path
                break
            }
        }
        
        if ($dockerDesktop) {
            Write-Host "Starting Docker Desktop from: $dockerDesktop" -ForegroundColor Gray
            Start-Process -FilePath $dockerDesktop -WindowStyle Hidden
            
            # Wait for Docker to start (max 60 seconds)
            Write-Host "Waiting for Docker to start (max 60 seconds)..." -ForegroundColor Cyan
            $maxWait = 60
            $waited = 0
            
            while ($waited -lt $maxWait) {
                Start-Sleep -Seconds 2
                $waited += 2
                
                try {
                    $null = docker info 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✅ Docker started successfully!" -ForegroundColor Green
                        $script:ContainerCli = "docker"
                        return $true
                    }
                } catch {
                    # Continue waiting
                }
                
                Write-Host "  Still waiting... ($waited/$maxWait seconds)" -ForegroundColor Gray
            }
            
            Write-Host "❌ Docker failed to start within $maxWait seconds." -ForegroundColor Red
            Write-Host "   Please start Docker Desktop manually and try again." -ForegroundColor Yellow
            return $false
        } else {
            Write-Host "❌ Could not find Docker Desktop executable." -ForegroundColor Red
            Write-Host "   Please start Docker Desktop manually." -ForegroundColor Yellow
            return $false
        }
    } else {
        # On Linux/Mac, provide guidance
        Write-Host "❌ Please start Docker manually:" -ForegroundColor Red
        Write-Host "" -ForegroundColor Red
        Write-Host "   On Linux: sudo systemctl start docker" -ForegroundColor Cyan
        Write-Host "   Or: sudo service docker start" -ForegroundColor Cyan
        Write-Host "   On Mac: Open Docker Desktop application" -ForegroundColor Cyan
        return $false
    }
}

function Update-AgentImage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Idempotent operation - safe to run without confirmation')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Agent,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory=$false)]
        [int]$RetryDelaySeconds = 2
    )
    
    $registryImage = "ghcr.io/novotnyllc/coding-agents-${Agent}:latest"
    $localImage = "coding-agents-${Agent}:local"
    
    Write-Host "📦 Checking for image updates..." -ForegroundColor Cyan
    
    # Try to pull with retries
    $attempt = 0
    $pulled = $false
    
    while ($attempt -lt $MaxRetries -and -not $pulled) {
        $attempt++
        try {
            if ($attempt -gt 1) {
                Write-Host "  Retry attempt $attempt of $MaxRetries..." -ForegroundColor Yellow
            }
            Invoke-ContainerCli pull --quiet $registryImage 2>$null | Out-Null
            Invoke-ContainerCli tag $registryImage $localImage 2>$null | Out-Null
            $pulled = $true
        } catch {
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }
    
    if (-not $pulled) {
        Write-Host "  ⚠️  Warning: Could not pull latest image, using cached version" -ForegroundColor Yellow
    }
}

function Test-ContainerExists {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Exists is semantically correct for testing existence')]
    param([string]$ContainerName)
    
    $existing = Invoke-ContainerCli ps -a --filter "name=^${ContainerName}$" --format "{{.Names}}" 2>$null
    return ($existing -eq $ContainerName)
}

function Get-ContainerStatus {
    param([string]$ContainerName)
    $status = Invoke-ContainerCli inspect -f '{{.State.Status}}' $ContainerName 2>$null
    if ($status) { return $status } else { return "not-found" }
}

function Push-ToLocal {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipPush
    )
    
    if ($SkipPush) {
        Write-Host "⏭️  Skipping git push (--no-push specified)" -ForegroundColor Yellow
        return
    }
    
    Write-Host "💾 Pushing changes to local remote..." -ForegroundColor Cyan
    
    $pushScript = @'
cd /workspace
if [ -n "$(git status --porcelain)" ]; then
    echo "📝 Uncommitted changes detected"
    read -p "Commit changes before push? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Commit message: " msg
        git add -A
        git commit -m "$msg"
    fi
fi

if git push 2>&1; then
    echo "✅ Changes pushed to local remote"
else
    echo "⚠️  Failed to push (may be up to date)"
fi
'@
    
    $cli = Get-ContainerCli
    try {
        $pushScript | & $cli exec -i $ContainerName bash 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Push failed"
        }
    } catch {
        Write-Host "⚠️  Could not push changes" -ForegroundColor Yellow
    }
}

function Get-AgentContainers {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Returns multiple containers - plural is correct')]
    param()
    
    Invoke-ContainerCli ps -a --filter "label=coding-agents.type=agent" `
        --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.CreatedAt}}"
}

function Get-ProxyContainer {
    param([string]$AgentContainer)
    Invoke-ContainerCli inspect -f '{{ index .Config.Labels "coding-agents.proxy-container" }}' $AgentContainer 2>$null
}

function Get-ProxyNetwork {
    param([string]$AgentContainer)
    Invoke-ContainerCli inspect -f '{{ index .Config.Labels "coding-agents.proxy-network" }}' $AgentContainer 2>$null
}

function Remove-ContainerWithSidecars {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Removes multiple sidecars - plural is semantically correct')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipPush,
        
        [Parameter(Mandatory=$false)]
        [switch]$KeepBranch
    )
    
    if (-not $PSCmdlet.ShouldProcess($ContainerName, "Remove container and associated resources")) {
        return
    }
    
    if (-not (Test-ContainerExists -ContainerName $ContainerName)) {
        Write-Host "❌ Container '$ContainerName' does not exist" -ForegroundColor Red
        return $false
    }
    
    # Get container labels to find repo and branch info
    $agentBranch = Invoke-ContainerCli inspect -f '{{ index .Config.Labels "coding-agents.branch" }}' $ContainerName 2>$null
    $repoPath = Invoke-ContainerCli inspect -f '{{ index .Config.Labels "coding-agents.repo-path" }}' $ContainerName 2>$null
    $localRemotePath = Invoke-ContainerCli inspect -f '{{ index .Config.Labels "coding-agents.local-remote" }}' $ContainerName 2>$null
    
    # Push changes first
    if ((Get-ContainerStatus $ContainerName) -eq "running") {
        Push-ToLocal -ContainerName $ContainerName -SkipPush:$SkipPush
    }
    
    # Get associated resources
    $proxyContainer = Get-ProxyContainer $ContainerName
    $proxyNetwork = Get-ProxyNetwork $ContainerName
    
    # Remove main container
    Write-Host "🗑️  Removing container: $ContainerName" -ForegroundColor Cyan
    Invoke-ContainerCli rm -f $ContainerName 2>$null | Out-Null
    
    # Remove proxy if exists
    if ($proxyContainer -and (Test-ContainerExists $proxyContainer)) {
        Write-Host "🗑️  Removing proxy: $proxyContainer" -ForegroundColor Cyan
        Invoke-ContainerCli rm -f $proxyContainer 2>$null | Out-Null
    }
    
    # Remove network if exists and no containers attached
    if ($proxyNetwork) {
        $attached = Invoke-ContainerCli network inspect -f '{{range .Containers}}{{.Name}} {{end}}' $proxyNetwork 2>$null
        if (-not $attached) {
            Write-Host "🗑️  Removing network: $proxyNetwork" -ForegroundColor Cyan
            Invoke-ContainerCli network rm $proxyNetwork 2>$null | Out-Null
        }
    }

    if ($agentBranch -and $repoPath -and (Test-Path $repoPath) -and $localRemotePath) {
        Write-Host ""
        Write-Host "🔄 Syncing agent branch back to host repository..." -ForegroundColor Cyan
        Sync-LocalRemoteToHost -RepoPath $repoPath -LocalRemotePath $localRemotePath -AgentBranch $agentBranch
    }
    
    # Clean up agent branch in host repo if applicable
    if (-not $KeepBranch -and $agentBranch -and $repoPath -and (Test-Path $repoPath)) {
        Write-Host ""
        Write-Host "🌿 Cleaning up agent branch: $agentBranch" -ForegroundColor Cyan
        
        if (Test-BranchExists -RepoPath $repoPath -BranchName $agentBranch) {
            # Check if branch has unpushed work
            Push-Location $repoPath
            try {
                $currentBranch = git branch --show-current 2>$null
                $unmergedCommits = Get-UnmergedCommits -RepoPath $repoPath -BaseBranch $currentBranch -CompareBranch $agentBranch
                
                if ($unmergedCommits) {
                    Write-Host "   ⚠️  Branch has unmerged commits - keeping branch" -ForegroundColor Yellow
                    Write-Host "   Manually merge or delete: git branch -D $agentBranch" -ForegroundColor Gray
                } else {
                    if (Remove-GitBranch -RepoPath $repoPath -BranchName $agentBranch -Force) {
                        Write-Host "   ✅ Agent branch removed" -ForegroundColor Green
                    } else {
                        Write-Host "   ⚠️  Could not remove agent branch" -ForegroundColor Yellow
                    }
                }
            } finally {
                Pop-Location
            }
        }
    }
    
    Write-Host ""
    Write-Host "✅ Cleanup complete" -ForegroundColor Green
    return $true
}

function Initialize-SquidProxy {
    param(
        [Parameter(Mandatory=$true)]
        [string]$NetworkName,
        
        [Parameter(Mandatory=$true)]
        [string]$ProxyContainer,
        
        [Parameter(Mandatory=$true)]
        [string]$ProxyImage,
        
        [Parameter(Mandatory=$true)]
        [string]$AgentContainer,
        
        [Parameter(Mandatory=$false)]
        [string]$SquidAllowedDomains = "*.github.com,*.githubcopilot.com,*.nuget.org"
    )
    
    # Validate inputs
    if (-not (Test-ValidContainerName $ProxyContainer)) {
        Write-Host "❌ Error: Invalid proxy container name: $ProxyContainer" -ForegroundColor Red
        throw "Invalid proxy container name"
    }
    
    if ([string]::IsNullOrWhiteSpace($SquidAllowedDomains)) {
        Write-Host "⚠️  Warning: No allowed domains specified for proxy" -ForegroundColor Yellow
        $SquidAllowedDomains = "*.github.com"
    }
    
    # Create network if needed
    $networkExists = Invoke-ContainerCli network inspect $NetworkName 2>$null
    if (-not $networkExists) {
        Invoke-ContainerCli network create $NetworkName | Out-Null
    }
    
    # Check if proxy exists
    if (Test-ContainerExists $ProxyContainer) {
        $state = Get-ContainerStatus $ProxyContainer
        if ($state -ne "running") {
            Invoke-ContainerCli start $ProxyContainer | Out-Null
        }
    } else {
        # Create new proxy
        Invoke-ContainerCli run -d `
            --name $ProxyContainer `
            --hostname $ProxyContainer `
            --network $NetworkName `
            --restart unless-stopped `
            -e "SQUID_ALLOWED_DOMAINS=$SquidAllowedDomains" `
            --label "coding-agents.proxy-of=$AgentContainer" `
            --label "coding-agents.proxy-image=$ProxyImage" `
            $ProxyImage | Out-Null
    }
}

function New-RepoSetupScript {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Returns a string script - does not execute anything')]
    param()
    
    return @'
#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${WORKSPACE_DIR:-/workspace}"
mkdir -p "$TARGET_DIR"

# Clean target directory
if [ -d "$TARGET_DIR" ] && [ "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
    find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

if [ "$SOURCE_TYPE" = "url" ]; then
    echo "🌐 Cloning repository from $GIT_URL..."
    git clone "$GIT_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
    if [ -n "$ORIGIN_URL" ]; then
        git remote set-url origin "$ORIGIN_URL"
    fi
else
    echo "📁 Copying repository from host..."
    cp -a /tmp/source-repo/. "$TARGET_DIR/"
    cd "$TARGET_DIR"
    
    # Configure local remote
    if [ -n "$LOCAL_REMOTE_URL" ]; then
        if git remote get-url local >/dev/null 2>&1; then
            git remote set-url local "$LOCAL_REMOTE_URL"
        else
            git remote add local "$LOCAL_REMOTE_URL"
        fi
        git config remote.pushDefault local
        git config remote.local.pushurl "$LOCAL_REMOTE_URL" >/dev/null 2>&1 || true
    elif [ -n "$LOCAL_REPO_PATH" ]; then
        if ! git remote get-url local >/dev/null 2>&1; then
            git remote add local "$LOCAL_REPO_PATH"
        fi
        git config remote.pushDefault local
    fi
fi

# Create and checkout branch
if [ -n "$AGENT_BRANCH" ]; then
    BRANCH_NAME="$AGENT_BRANCH"
    if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
        git checkout -b "$BRANCH_NAME"
    else
        git checkout "$BRANCH_NAME"
    fi
fi

echo "✅ Repository setup complete"
'@
}

function Sync-LocalRemoteToHost {
    [CmdletBinding()]
    param(
        [string]$RepoPath,
        [string]$LocalRemotePath,
        [string]$AgentBranch
    )

    if ([string]::IsNullOrWhiteSpace($RepoPath) -or [string]::IsNullOrWhiteSpace($LocalRemotePath) -or [string]::IsNullOrWhiteSpace($AgentBranch)) {
        return
    }

    if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
        return
    }

    if (-not (Test-Path $LocalRemotePath)) {
        Write-Warning "Secure remote missing at $LocalRemotePath"
        return
    }

    $branchExists = git --git-dir=$LocalRemotePath rev-parse --verify --quiet "refs/heads/$AgentBranch" 2>$null
    if (-not $?) {
        return
    }

    Push-Location $RepoPath
    try {
        $tempRef = "refs/coding-agents-sync/$AgentBranch" -replace ' ', '-'
        if (-not (git fetch $LocalRemotePath "${AgentBranch}:$tempRef" 2>$null)) {
            Write-Warning "Failed to fetch agent branch from secure remote"
            return
        }

        $fetchedSha = git rev-parse $tempRef 2>$null
        if (-not $?) { return }

        $currentBranch = git branch --show-current 2>$null
        $hostHasBranch = git show-ref --verify --quiet "refs/heads/$AgentBranch" 2>$null
        $hostHasBranch = $?

        if ($hostHasBranch) {
            if ($currentBranch -eq $AgentBranch) {
                $worktreeState = git status --porcelain 2>$null
                if ($worktreeState) {
                    Write-Warning "Working tree dirty on $AgentBranch; skipped auto-sync"
                } else {
                    if (git merge --ff-only $tempRef 2>$null) {
                        Write-Host "✅ Host branch '$AgentBranch' fast-forwarded from secure remote"
                    } else {
                        Write-Warning "Unable to fast-forward '$AgentBranch' (merge required)"
                    }
                }
            } else {
                if (git update-ref "refs/heads/$AgentBranch" $fetchedSha 2>$null) {
                    Write-Host "✅ Host branch '$AgentBranch' updated from secure remote"
                } else {
                    Write-Warning "Failed to update branch '$AgentBranch'"
                }
            }
        } else {
            if (git branch $AgentBranch $tempRef 2>$null) {
                Write-Host "✅ Created branch '$AgentBranch' from secure remote"
            } else {
                Write-Warning "Failed to create branch '$AgentBranch'"
            }
        }
    }
    finally {
        git update-ref -d $tempRef 2>$null | Out-Null
        Pop-Location
    }
}
