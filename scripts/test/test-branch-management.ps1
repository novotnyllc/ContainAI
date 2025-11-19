<#
.SYNOPSIS
    Comprehensive test suite for branch management features

.DESCRIPTION
    Tests branch conflict detection, archiving, unmerged commits, and cleanup
    All tests are completely isolated and don't affect the host system
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
    if (-not [string]::IsNullOrWhiteSpace($env:TMPDIR)) {
        $env:TEMP = $env:TMPDIR
    } elseif (-not [string]::IsNullOrWhiteSpace($env:TMP)) {
        $env:TEMP = $env:TMP
    } else {
        $env:TEMP = [System.IO.Path]::GetTempPath()
    }
}

# Test session ID for complete isolation
$TEST_SESSION_ID = $PID
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$TEST_REPO_DIR = Join-Path $env:TEMP "test-branch-mgmt-$TEST_SESSION_ID"
$FAILED_TESTS = 0
$PASSED_TESTS = 0
$debugFlag = $env:CODING_AGENTS_BRANCH_TEST_DEBUG
if ([string]::IsNullOrEmpty($debugFlag)) {
    $debugFlag = '0'
}
$SUPPRESS_CLEANUP_EXIT = $debugFlag -ne '0'

# Source common functions to test
. "$SCRIPT_DIR\..\utils\common-functions.ps1"

# ============================================================================
# Docker Detection and Setup
# ============================================================================

function Test-DockerAvailable {
    try {
        $null = docker version 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Start-DockerIfNeeded {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Test helper function - interactive confirmation not needed')]
    param()
    
    if (Test-DockerAvailable) {
        return $true
    }
    
    Write-Host "Docker is not running. Checking if Docker Desktop is installed..." -ForegroundColor Yellow
    
    # Check if Docker Desktop is installed
    $dockerDesktop = Get-Command "Docker Desktop.exe" -ErrorAction SilentlyContinue
    if (-not $dockerDesktop) {
        $dockerDesktop = Get-Item "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue
    }
    
    if (-not $dockerDesktop) {
        Write-Host "❌ Docker is not installed. Please install Docker Desktop from:" -ForegroundColor Red
        Write-Host "   https://www.docker.com/products/docker-desktop" -ForegroundColor Cyan
        return $false
    }
    
    Write-Host "Starting Docker Desktop..." -ForegroundColor Cyan
    Start-Process -FilePath $dockerDesktop.FullName -WindowStyle Hidden
    
    # Wait for Docker to start (max 60 seconds)
    $maxWait = 60
    $waited = 0
    while ($waited -lt $maxWait) {
        Start-Sleep -Seconds 2
        $waited += 2
        if (Test-DockerAvailable) {
            Write-Host "✅ Docker started successfully" -ForegroundColor Green
            return $true
        }
        Write-Host "  Waiting for Docker... ($waited/$maxWait seconds)" -ForegroundColor Gray
    }
    
    Write-Host "❌ Docker failed to start within $maxWait seconds" -ForegroundColor Red
    Write-Host "   Please start Docker Desktop manually and try again" -ForegroundColor Yellow
    return $false
}

# ============================================================================
# Cleanup and Setup Functions
# ============================================================================

function Cleanup {
    Write-Host ""
    Write-Host "🧹 Cleaning up test resources..." -ForegroundColor Cyan
    
    # Remove test containers
    docker ps -aq --filter "label=coding-agents.test-session=$TEST_SESSION_ID" | 
        ForEach-Object { docker rm -f $_ 2>$null | Out-Null }
    
    # Remove test networks
    docker network ls --filter "name=test-branch-mgmt-$TEST_SESSION_ID" --format "{{.Name}}" | 
        ForEach-Object { docker network rm $_ 2>$null | Out-Null }
    
    # Remove test repository
    if (Test-Path $TEST_REPO_DIR) {
        Remove-Item -Path $TEST_REPO_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-TestSummary

    if (-not $SUPPRESS_CLEANUP_EXIT) {
        exit ($FAILED_TESTS -gt 0 ? 1 : 0)
    }
}

function Write-TestSummary {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "Branch Management Test Results:" -ForegroundColor Cyan
    Write-Host "  ✅ Passed: $PASSED_TESTS" -ForegroundColor Green
    Write-Host "  ❌ Failed: $FAILED_TESTS" -ForegroundColor Red
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}

function Initialize-TestRepo {
    Write-Host ""
    Write-Host "Setting up isolated test repository..." -ForegroundColor Cyan
    
    if (Test-Path $TEST_REPO_DIR) {
        Remove-Item -Path $TEST_REPO_DIR -Recurse -Force
    }
    New-Item -Path $TEST_REPO_DIR -ItemType Directory | Out-Null
    
    Push-Location $TEST_REPO_DIR
    try {
        # Initialize git with test configuration
        git init -q
        git config user.name "Test User"
        git config user.email "test@example.com"
        git config commit.gpgsign false
        
        # Create initial commit
        "# Test Repository $TEST_SESSION_ID" | Out-File -FilePath "README.md" -Encoding UTF8
        git add README.md
        git commit -q -m "Initial commit"
        git branch -M main
        
        Write-Host "✅ Test repository created at $TEST_REPO_DIR" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# ============================================================================
# Assertion Helper Functions
# ============================================================================

function Write-Pass {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
    $script:PASSED_TESTS++
}

function Write-Fail {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
    $script:FAILED_TESTS++
}

function Write-TestSection {
    param([string]$Title)
    Write-Host ""
    Write-Host "━━━ $Title ━━━" -ForegroundColor Yellow
}

function Assert-BranchExists {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Exists is semantically correct for this assertion')]
    param(
        [string]$RepoPath,
        [string]$BranchName
    )
    
    if (Test-BranchExists -RepoPath $RepoPath -BranchName $BranchName) {
        Write-Pass "Branch exists: $BranchName"
    } else {
        Write-Fail "Branch does not exist: $BranchName"
    }
}

function Assert-BranchNotExists {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Exists is semantically correct for this assertion')]
    param(
        [string]$RepoPath,
        [string]$BranchName
    )
    
    if (-not (Test-BranchExists -RepoPath $RepoPath -BranchName $BranchName)) {
        Write-Pass "Branch does not exist: $BranchName"
    } else {
        Write-Fail "Branch exists when it shouldn't: $BranchName"
    }
}

# ============================================================================
# Branch Management Function Tests
# ============================================================================

function Test-BranchExistsFunction {
    Write-TestSection "Testing Test-BranchExists function"
    
    Push-Location $TEST_REPO_DIR
    try {
        # Test existing branch
        if (Test-BranchExists -RepoPath $TEST_REPO_DIR -BranchName "main") {
            Write-Pass "Test-BranchExists correctly identifies existing branch"
        } else {
            Write-Fail "Test-BranchExists failed to identify existing branch"
        }
        
        # Test non-existing branch
        if (-not (Test-BranchExists -RepoPath $TEST_REPO_DIR -BranchName "nonexistent")) {
            Write-Pass "Test-BranchExists correctly identifies non-existing branch"
        } else {
            Write-Fail "Test-BranchExists incorrectly identified non-existing branch"
        }
    } finally {
        Pop-Location
    }
}

function Test-CreateGitBranch {
    Write-TestSection "Testing New-GitBranch function"
    
    Push-Location $TEST_REPO_DIR
    try {
        # Create new branch
        if (New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "test-branch") {
            Write-Pass "New-GitBranch successfully created branch"
            Assert-BranchExists -RepoPath $TEST_REPO_DIR -BranchName "test-branch"
        } else {
            Write-Fail "New-GitBranch failed to create branch"
        }
        
        # Create branch from specific commit
        $commitSha = git rev-parse HEAD
        if (New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "test-branch-2" -StartPoint $commitSha) {
            Write-Pass "New-GitBranch created branch from specific commit"
            Assert-BranchExists -RepoPath $TEST_REPO_DIR -BranchName "test-branch-2"
        } else {
            Write-Fail "New-GitBranch failed to create branch from commit"
        }
    } finally {
        Pop-Location
    }
}

function Test-RenameGitBranch {
    Write-TestSection "Testing Rename-GitBranch function"
    
    Push-Location $TEST_REPO_DIR
    try {
        # Create a branch to rename
        New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "branch-to-rename" | Out-Null
        
        # Rename it
        if (Rename-GitBranch -RepoPath $TEST_REPO_DIR -OldName "branch-to-rename" -NewName "renamed-branch") {
            Write-Pass "Rename-GitBranch successfully renamed branch"
            Assert-BranchNotExists -RepoPath $TEST_REPO_DIR -BranchName "branch-to-rename"
            Assert-BranchExists -RepoPath $TEST_REPO_DIR -BranchName "renamed-branch"
        } else {
            Write-Fail "Rename-GitBranch failed to rename branch"
        }
    } finally {
        Pop-Location
    }
}

function Test-RemoveGitBranch {
    Write-TestSection "Testing Remove-GitBranch function"
    
    Push-Location $TEST_REPO_DIR
    try {
        # Create a branch to remove
        New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "branch-to-remove" | Out-Null
        Assert-BranchExists -RepoPath $TEST_REPO_DIR -BranchName "branch-to-remove"
        
        # Remove it
        if (Remove-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "branch-to-remove" -Force $true -Confirm:$false) {
            Write-Pass "Remove-GitBranch successfully removed branch"
            Assert-BranchNotExists -RepoPath $TEST_REPO_DIR -BranchName "branch-to-remove"
        } else {
            Write-Fail "Remove-GitBranch failed to remove branch"
        }
    } finally {
        Pop-Location
    }
}

function Test-GetUnmergedCommits {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Testing function that returns multiple commits')]
    param()
    
    Write-TestSection "Testing Get-UnmergedCommits function"
    
    Push-Location $TEST_REPO_DIR
    try {
        # Create feature branch with unmerged commits
        git checkout -q main
        New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "feature-branch" | Out-Null
        git checkout -q feature-branch
        
        "Feature work" | Out-File -FilePath "feature.txt" -Encoding UTF8
        git add feature.txt
        git commit -q -m "Feature commit 1"
        
        "More feature work" | Out-File -FilePath "feature.txt" -Append -Encoding UTF8
        git add feature.txt
        git commit -q -m "Feature commit 2"
        
        git checkout -q main
        
        # Check for unmerged commits
        $unmerged = Get-UnmergedCommits -RepoPath $TEST_REPO_DIR -BaseBranch "main" -CompareBranch "feature-branch"
        
        if ($unmerged) {
            Write-Pass "Get-UnmergedCommits detected unmerged commits"
            
            # Verify it found 2 commits
            $commitCount = ($unmerged -split "`n").Count
            if ($commitCount -eq 2) {
                Write-Pass "Get-UnmergedCommits found correct number of commits (2)"
            } else {
                Write-Fail "Get-UnmergedCommits found $commitCount commits, expected 2"
            }
        } else {
            Write-Fail "Get-UnmergedCommits failed to detect unmerged commits"
        }
        
        # Test with merged branch
        git merge -q --no-edit feature-branch
        New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "merged-branch" | Out-Null
        
        $merged = Get-UnmergedCommits -RepoPath $TEST_REPO_DIR -BaseBranch "main" -CompareBranch "merged-branch"
        if (-not $merged) {
            Write-Pass "Get-UnmergedCommits correctly reports no unmerged commits"
        } else {
            Write-Fail "Get-UnmergedCommits incorrectly reported unmerged commits on merged branch"
        }
    } finally {
        Pop-Location
    }
}

function Test-AgentBranchIsolation {
    Write-TestSection "Testing agent branch isolation"
    
    Push-Location $TEST_REPO_DIR
    try {
        git checkout -q main
        
        # Create agent-specific branches
        New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "copilot/main" | Out-Null
        New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "codex/main" | Out-Null
        New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "claude/main" | Out-Null
        
        Assert-BranchExists -RepoPath $TEST_REPO_DIR -BranchName "copilot/main"
        Assert-BranchExists -RepoPath $TEST_REPO_DIR -BranchName "codex/main"
        Assert-BranchExists -RepoPath $TEST_REPO_DIR -BranchName "claude/main"
        
        Write-Pass "Multiple agent branches coexist successfully"
    } finally {
        Pop-Location
    }
}

function Test-BranchArchivingWithTimestamp {
    Write-TestSection "Testing branch archiving with timestamp"
    
    Push-Location $TEST_REPO_DIR
    try {
        git checkout -q main
        
        # Create branch with work
        New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "copilot/feature" | Out-Null
        git checkout -q "copilot/feature"
        "Work" | Out-File -FilePath "work.txt" -Encoding UTF8
        git add work.txt
        git commit -q -m "Some work"
        git checkout -q main
        
        # Archive it with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $archiveName = "copilot/feature-archived-$timestamp"
        
        if (Rename-GitBranch -RepoPath $TEST_REPO_DIR -OldName "copilot/feature" -NewName $archiveName) {
            Write-Pass "Branch archived with timestamp"
            Assert-BranchNotExists -RepoPath $TEST_REPO_DIR -BranchName "copilot/feature"
            Assert-BranchExists -RepoPath $TEST_REPO_DIR -BranchName $archiveName
        } else {
            Write-Fail "Failed to archive branch with timestamp"
        }
    } finally {
        Pop-Location
    }
}

function Test-ContainerBranchCleanup {
    Write-TestSection "Testing container branch cleanup integration"
    
    Push-Location $TEST_REPO_DIR
    try {
        git checkout -q main
        
        # Create agent branch
        New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "copilot/cleanup-test" | Out-Null
        
        # Create test container with labels
        $containerName = "copilot-test-cleanup-$TEST_SESSION_ID"
        docker run -d `
            --name $containerName `
            --label "coding-agents.test-session=$TEST_SESSION_ID" `
            --label "coding-agents.type=agent" `
            --label "coding-agents.branch=copilot/cleanup-test" `
            --label "coding-agents.repo-path=$TEST_REPO_DIR" `
            alpine:latest sleep 60 | Out-Null
        
        # Simulate removal with branch cleanup
        Remove-ContainerWithSidecars -ContainerName $containerName -SkipPush -KeepBranch:$false
        
        # Verify branch was cleaned up
        Assert-BranchNotExists -RepoPath $TEST_REPO_DIR -BranchName "copilot/cleanup-test"
    } finally {
        Pop-Location
    }
}

function Test-PreserveBranchWithUnmergedCommits {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Testing preservation of multiple commits')]
    param()
    
    Write-TestSection "Testing preservation of branches with unmerged commits"
    
    Push-Location $TEST_REPO_DIR
    try {
        git checkout -q main
        
        # Create branch with unmerged work
        New-GitBranch -RepoPath $TEST_REPO_DIR -BranchName "copilot/preserve-test" | Out-Null
        git checkout -q "copilot/preserve-test"
        "Important work" | Out-File -FilePath "important.txt" -Encoding UTF8
        git add important.txt
        git commit -q -m "Important commit"
        git checkout -q main
        
        # Create container
        $containerName = "copilot-test-preserve-$TEST_SESSION_ID"
        docker run -d `
            --name $containerName `
            --label "coding-agents.test-session=$TEST_SESSION_ID" `
            --label "coding-agents.type=agent" `
            --label "coding-agents.branch=copilot/preserve-test" `
            --label "coding-agents.repo-path=$TEST_REPO_DIR" `
            alpine:latest sleep 60 | Out-Null
        
        # Remove container (should preserve branch due to unmerged commits)
        try {
            Remove-ContainerWithSidecars -ContainerName $containerName -SkipPush -KeepBranch:$false -ErrorAction SilentlyContinue
        } catch {
            # Expected to warn about unmerged commits - this is normal behavior
            Write-Verbose "Branch preservation warning (expected): $_"
        }
        
        # Verify branch still exists
        Assert-BranchExists -RepoPath $TEST_REPO_DIR -BranchName "copilot/preserve-test"
    } finally {
        Pop-Location
    }
}

# ============================================================================
# Run All Tests
# ============================================================================

function Main {
    Write-Host "🧪 Starting Branch Management Test Suite" -ForegroundColor Cyan
    Write-Host "Session ID: $TEST_SESSION_ID" -ForegroundColor Cyan
    
    # Check Docker availability
    if (-not (Start-DockerIfNeeded)) {
        Write-Host "❌ Cannot run tests without Docker" -ForegroundColor Red
        exit 1
    }
    
    # Setup cleanup handler
    $script:CleanupRegistered = $true
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Cleanup } | Out-Null
    
    try {
        # Setup
        Initialize-TestRepo
        
        # Run all tests
        Test-BranchExistsFunction
        Test-CreateGitBranch
        Test-RenameGitBranch
        Test-RemoveGitBranch
        Test-GetUnmergedCommits
        Test-AgentBranchIsolation
        Test-BranchArchivingWithTimestamp
        Test-ContainerBranchCleanup
        Test-PreserveBranchWithUnmergedCommits
        
        Write-Host ""
        Write-Host "✅ All branch management tests completed" -ForegroundColor Green
    } finally {
        Cleanup
    }
}

# Run the tests
Main
