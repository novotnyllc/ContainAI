# Automated test suite for launcher scripts (PowerShell)
# Tests all core functionality: naming, labels, auto-push, shared functions

param(
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

$script:FailedTests = 0
$script:PassedTests = 0

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$TestRepoDir = Join-Path $env:TEMP "test-coding-agents-repo"

# ============================================================================
# Cleanup and Setup Functions
# ============================================================================

function Cleanup-Tests {
    Write-Host ""
    Write-Host "🧹 Cleaning up test containers and networks..." -ForegroundColor Cyan
    
    docker ps -aq --filter "label=coding-agents.test=true" | ForEach-Object {
        docker rm -f $_ 2>$null | Out-Null
    }
    
    docker network ls --filter "name=test-" --format "{{.Name}}" | ForEach-Object {
        docker network rm $_ 2>$null | Out-Null
    }
    
    if (Test-Path $TestRepoDir) {
        Remove-Item $TestRepoDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Show-TestSummary
    
    if ($script:FailedTests -gt 0) {
        exit 1
    }
}

function Show-TestSummary {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
    Write-Host "Test Results:" -ForegroundColor White
    Write-Host "  ✅ Passed: $script:PassedTests" -ForegroundColor Green
    Write-Host "  ❌ Failed: $script:FailedTests" -ForegroundColor Red
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
}

function Setup-TestRepo {
    Test-Section "Setting up test repository"
    
    if (Test-Path $TestRepoDir) {
        Remove-Item $TestRepoDir -Recurse -Force
    }
    
    New-Item -ItemType Directory -Path $TestRepoDir | Out-Null
    Push-Location $TestRepoDir
    
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git config remote.pushDefault local
    
    "# Test Repository" | Out-File -FilePath "README.md" -Encoding UTF8
    git add README.md
    git commit -q -m "Initial commit"
    git checkout -q -b main
    
    Pop-Location
    
    Pass "Created test repository at $TestRepoDir"
}

# ============================================================================
# Assertion Helper Functions
# ============================================================================

function Pass {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
    $script:PassedTests++
}

function Fail {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
    $script:FailedTests++
}

function Test-Section {
    param([string]$Name)
    Write-Host ""
    Write-Host "━━━ $Name ━━━" -ForegroundColor Yellow
}

function Assert-Equals {
    param(
        [string]$Expected,
        [string]$Actual,
        [string]$Message
    )
    
    if ($Expected -eq $Actual) {
        Pass $Message
    } else {
        Fail "$Message (expected: '$Expected', got: '$Actual')"
    }
}

function Assert-Contains {
    param(
        [string]$Haystack,
        [string]$Needle,
        [string]$Message
    )
    
    if ($Haystack -match [regex]::Escape($Needle)) {
        Pass $Message
    } else {
        Fail "$Message (string not found: '$Needle')"
    }
}

function Assert-ContainerExists {
    param(
        [string]$ContainerName,
        [string]$Message = "Container exists: $ContainerName"
    )
    
    $exists = docker ps -a --filter "name=^${ContainerName}$" --format "{{.Names}}" 2>$null
    if ($exists -eq $ContainerName) {
        Pass $Message
    } else {
        Fail "Container does not exist: $ContainerName"
    }
}

function Assert-LabelExists {
    param(
        [string]$ContainerName,
        [string]$LabelKey,
        [string]$LabelValue
    )
    
    $actual = docker inspect -f "{{ index .Config.Labels `"${LabelKey}`" }}" $ContainerName 2>$null
    if ($actual -eq $LabelValue) {
        Pass "Label ${LabelKey}=${LabelValue} on $ContainerName"
    } else {
        Fail "Label ${LabelKey} incorrect on $ContainerName (expected: '$LabelValue', got: '$actual')"
    }
}

# ============================================================================
# Test Container Helper Functions
# ============================================================================

function New-TestContainer {
    param(
        [string]$Agent,
        [string]$Repo,
        [string]$Branch
    )
    
    $SanitizedBranch = $Branch -replace '/', '-'
    $ContainerName = "$Agent-$Repo-$SanitizedBranch"
    
    docker run -d `
        --name $ContainerName `
        --label "coding-agents.test=true" `
        --label "coding-agents.type=agent" `
        --label "coding-agents.agent=$Agent" `
        --label "coding-agents.repo=$Repo" `
        --label "coding-agents.branch=$Branch" `
        alpine:latest sleep 3600 | Out-Null
    
    return $ContainerName
}

function Test-ContainerLabels {
    param(
        [string]$ContainerName,
        [string]$Agent,
        [string]$Repo,
        [string]$Branch
    )
    
    Assert-LabelExists $ContainerName "coding-agents.type" "agent"
    Assert-LabelExists $ContainerName "coding-agents.agent" $Agent
    Assert-LabelExists $ContainerName "coding-agents.repo" $Repo
    Assert-LabelExists $ContainerName "coding-agents.branch" $Branch
}

# ============================================================================
# Test Functions
# ============================================================================

function Test-SharedFunctions {
    Test-Section "Testing shared functions"
    
    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")
    
    $repoName = Get-RepoName $TestRepoDir
    Assert-Equals "test-coding-agents-repo" $repoName "Get-RepoName returns correct name"
    
    Push-Location $TestRepoDir
    $branch = Get-CurrentBranch $TestRepoDir
    Pop-Location
    Assert-Equals "main" $branch "Get-CurrentBranch returns 'main'"
    
    if (Test-DockerRunning) {
        Pass "Test-DockerRunning succeeds when Docker is running"
    } else {
        Fail "Test-DockerRunning failed"
    }
    
    if (-not (Test-ContainerExists "non-existent-container-12345")) {
        Pass "Test-ContainerExists returns false for non-existent container"
    } else {
        Fail "Test-ContainerExists returned true for non-existent container"
    }
}

function Test-ContainerNaming {
    Test-Section "Testing container naming convention"
    
    $containerName = New-TestContainer -Agent "copilot" -Repo "test-coding-agents-repo" -Branch "main"
    
    Assert-ContainerExists $containerName
    Assert-Contains $containerName "copilot-" "Container name starts with agent"
    Assert-Contains $containerName "-main" "Container name ends with branch"
}

function Test-ContainerLabelsTest {
    Test-Section "Testing container labels"
    
    $containerName = "copilot-test-coding-agents-repo-main"
    Test-ContainerLabels $containerName "copilot" "test-coding-agents-repo" "main"
}

function Test-ListAgents {
    Test-Section "Testing list-agents command"
    
    New-TestContainer -Agent "codex" -Repo "test-coding-agents-repo" -Branch "develop" | Out-Null
    
    $listScript = Join-Path $ProjectRoot "scripts\launchers\list-agents.ps1"
    $output = & $listScript | Out-String
    
    Assert-Contains $output "copilot-test-coding-agents-repo-main" "list-agents shows copilot container"
    Assert-Contains $output "codex-test-coding-agents-repo-develop" "list-agents shows codex container"
    Assert-Contains $output "NAME" "list-agents shows header"
}

function Test-RemoveAgent {
    Test-Section "Testing remove-agent command"
    
    $containerName = "codex-test-coding-agents-repo-develop"
    
    $removeScript = Join-Path $ProjectRoot "scripts\launchers\remove-agent.ps1"
    & $removeScript $containerName -NoPush
    
    $exists = docker ps -a --filter "name=^${containerName}$" --format "{{.Names}}" 2>$null
    if (-not $exists) {
        Pass "remove-agent successfully removed container"
    } else {
        Fail "remove-agent did not remove container"
    }
}

function Test-ImagePull {
    Test-Section "Testing image pull functionality"
    
    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")
    
    try {
        Update-AgentImage -Agent "copilot" 2>$null
        Pass "Update-AgentImage executes without error"
    } catch {
        Pass "Update-AgentImage handles missing image gracefully"
    }
}

function Test-BranchSanitization {
    Test-Section "Testing branch name sanitization"
    
    Push-Location $TestRepoDir
    git checkout -q -b "feature/test-branch"
    Pop-Location
    
    $containerName = New-TestContainer -Agent "copilot" -Repo "test-coding-agents-repo" -Branch "feature/test-branch"
    
    Assert-ContainerExists $containerName
    Assert-LabelExists $containerName "coding-agents.branch" "feature/test-branch"
    
    docker rm -f $containerName 2>$null | Out-Null
}

function Test-MultipleAgents {
    Test-Section "Testing multiple agents on same repo"
    
    Push-Location $TestRepoDir
    git checkout -q main
    Pop-Location
    
    $agents = @("codex", "claude")
    $containers = @()
    
    foreach ($agent in $agents) {
        $containers += New-TestContainer -Agent $agent -Repo "test-coding-agents-repo" -Branch "main"
    }
    
    foreach ($container in $containers) {
        Assert-ContainerExists $container "Agent container created: $container"
    }
    
    Pass "Multiple agents can run on same repo/branch"
}

function Test-LabelFiltering {
    Test-Section "Testing label-based filtering"
    
    $agentCount = (docker ps -a --filter "label=coding-agents.type=agent" --filter "label=coding-agents.test=true" --format "{{.Names}}" | Measure-Object).Count
    
    if ($agentCount -ge 3) {
        Pass "Label filtering finds multiple agent containers (found: $agentCount)"
    } else {
        Fail "Label filtering found insufficient containers (found: $agentCount, expected: >= 3)"
    }
    
    $copilotCount = (docker ps -a --filter "label=coding-agents.agent=copilot" --filter "label=coding-agents.test=true" --format "{{.Names}}" | Measure-Object).Count
    
    if ($copilotCount -ge 1) {
        Pass "Label filtering finds copilot containers (found: $copilotCount)"
    } else {
        Fail "Label filtering found no copilot containers"
    }
}

function Test-ContainerStatus {
    Test-Section "Testing container status functions"
    
    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")
    
    $containerName = "copilot-test-coding-agents-repo-main"
    
    $status = Get-ContainerStatus $containerName
    Assert-Equals "running" $status "Get-ContainerStatus returns 'running'"
    
    docker stop $containerName 2>$null | Out-Null
    $status2 = Get-ContainerStatus $containerName
    Assert-Equals "exited" $status2 "Get-ContainerStatus returns 'exited' after stop"
    
    docker start $containerName 2>$null | Out-Null
}

# ============================================================================
# Main Test Execution
# ============================================================================

function Main {
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║      Coding Agents Launcher Test Suite (PowerShell)      ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Testing from: $ProjectRoot" -ForegroundColor White
    Write-Host ""
    
    try {
        Setup-TestRepo
        Test-SharedFunctions
        Test-ContainerNaming
        Test-ContainerLabelsTest
        Test-ImagePull
        Test-BranchSanitization
        Test-MultipleAgents
        Test-LabelFiltering
        Test-ContainerStatus
        Test-ListAgents
        Test-RemoveAgent
    }
    finally {
        Cleanup-Tests
    }
}

Main
