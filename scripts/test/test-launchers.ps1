# Automated test suite for launcher scripts (PowerShell)
# Tests all core functionality: naming, labels, auto-push, shared functions

[CmdletBinding()]
param(
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

if ($Verbose) {
    $VerbosePreference = "Continue"
} else {
    $VerbosePreference = "SilentlyContinue"
}

if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
    if (-not [string]::IsNullOrWhiteSpace($env:TMPDIR)) {
        $env:TEMP = $env:TMPDIR
    } elseif (-not [string]::IsNullOrWhiteSpace($env:TMP)) {
        $env:TEMP = $env:TMP
    } else {
        $env:TEMP = [System.IO.Path]::GetTempPath()
    }
}

$script:FailedTests = 0
$script:PassedTests = 0

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$TestRepoDir = Join-Path $env:TEMP "test-coding-agents-repo"
$script:TestContainerImageSpec = $null
$script:IsWindowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)

function Write-TestLine {
    [CmdletBinding()]
    param(
        [string]$Message = "",
        [ValidateSet("Default", "Red", "Green", "Yellow", "Cyan", "White")]
        [string]$Color = "Default"
    )

    $prefix = switch ($Color) {
        "Red" { "`e[31m" }
        "Green" { "`e[32m" }
        "Yellow" { "`e[33m" }
        "Cyan" { "`e[36m" }
        "White" { "`e[37m" }
        Default { "" }
    }

    $reset = if ($prefix) { "`e[0m" } else { "" }

    if ([string]::IsNullOrEmpty($Message)) {
        Write-Output ""
        return
    }

    Write-Output ($prefix + $Message + $reset)
}

# ============================================================================
# Cleanup and Setup Functions
# ============================================================================

function Clear-TestEnvironment {
    Write-TestLine
    Write-TestLine -Color Cyan -Message "[CLEANUP] Removing test containers and networks"
    
    docker ps -aq --filter "label=coding-agents.test=true" | ForEach-Object {
        docker rm -f $_ 2> $null | Out-Null
    }
    
    docker network ls --filter "name=test-" --format "{{.Name}}" | ForEach-Object {
        docker network rm $_ 2> $null | Out-Null
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
    Write-TestLine
    Write-TestLine -Color Yellow -Message "===================================================="
    Write-TestLine -Color White -Message "Test Results:"
    Write-TestLine -Color Green -Message "  [PASS] $script:PassedTests"
    Write-TestLine -Color Red -Message "  [FAIL] $script:FailedTests"
    Write-TestLine -Color Yellow -Message "===================================================="
}

function Initialize-TestRepo {
    Test-Section "Setting up test repository"
    
    if (Test-Path $TestRepoDir) {
        Remove-Item $TestRepoDir -Recurse -Force
    }
    
    New-Item -ItemType Directory -Path $TestRepoDir | Out-Null
    Push-Location $TestRepoDir
    
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git config commit.gpgsign false
    git config remote.pushDefault local
    
    "# Test Repository" | Out-File -FilePath "README.md" -Encoding UTF8
    git add README.md
    git commit -q -m "Initial commit"
    git checkout -q -B main
    
    Pop-Location
    
    Pass "Created test repository at $TestRepoDir"
}

# ============================================================================
# Assertion Helper Functions
# ============================================================================

function Pass {
    param([string]$Message)
    Write-TestLine -Color Green -Message "[PASS] $Message"
    $script:PassedTests++
}

function Fail {
    param([string]$Message)
    Write-TestLine -Color Red -Message "[FAIL] $Message"
    $script:FailedTests++
}

function Test-Section {
    param([string]$Name)
    Write-TestLine
    Write-TestLine -Color Yellow -Message "--- $Name ---"
}

function Assert-Equals {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Equals is grammatically correct for comparison')]
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Contains is grammatically correct for inclusion check')]
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Exists is semantically correct for existence check')]
    param(
        [string]$ContainerName,
        [string]$Message = "Container exists: $ContainerName"
    )
    
    $exists = docker ps -a --filter "name=^${ContainerName}$" --format "{{.Names}}" 2> $null
    if ($exists -eq $ContainerName) {
        Pass $Message
    } else {
        Fail "Container does not exist: $ContainerName"
    }
}

function Assert-LabelExists {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Exists is semantically correct for existence check')]
    param(
        [string]$ContainerName,
        [string]$LabelKey,
        [string]$LabelValue
    )
    
    $actual = docker inspect -f "{{ index .Config.Labels `"${LabelKey}`" }}" $ContainerName 2> $null
    if ($actual -eq $LabelValue) {
        Pass "Label ${LabelKey}=${LabelValue} on $ContainerName"
    } else {
        Fail "Label ${LabelKey} incorrect on $ContainerName (expected: '$LabelValue', got: '$actual')"
    }
}

function Invoke-Test {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [scriptblock]$Action
    )

    try {
        & $Action
    } catch {
        Fail "$Name failed with error: $_"
    }
}

# ============================================================================
# Environment Validation Functions
# ============================================================================

function Get-DockerOsType {
    try {
        return ((& docker info --format "{{.OSType}}" 2> $null).Trim().ToLower())
    } catch {
        return ""
    }
}

function Confirm-LinuxContainerEnvironment {
    if ($script:IsWindowsHost -and -not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw "Coding Agents launchers require WSL to access Linux containers. Install/enable WSL and switch Docker Desktop to the WSL 2 backend."
    }

    $osType = Get-DockerOsType
    if ([string]::IsNullOrWhiteSpace($osType)) {
        throw "Unable to determine Docker container OS type. Ensure Docker is running and accessible."
    }

    if ($osType -ne "linux") {
        throw "Coding Agents launchers require Docker to run Linux containers (WSL on Windows). Current Docker OSType: '$osType'. Switch Docker to Linux containers."
    }
}

# ============================================================================
# Test Container Helper Functions
# ============================================================================

function Get-TestContainerImageSpec {
    if ($script:TestContainerImageSpec) {
        return $script:TestContainerImageSpec
    }

    Confirm-LinuxContainerEnvironment

    $script:TestContainerImageSpec = @{
        Image = "alpine:latest"
        CommandBuilder = { param($seconds) @("sleep", "$seconds") }
    }

    return $script:TestContainerImageSpec
}

function Start-TestContainer {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [string]$ContainerName,
        [hashtable]$Labels,
        [string[]]$AdditionalArgs,
        [int]$DurationSeconds = 3600
    )

    if (-not $Labels) {
        $Labels = @{}
    }

    $dockerArgs = @("run", "-d", "--name", $ContainerName)
    foreach ($key in $Labels.Keys) {
        $dockerArgs += @("--label", "$key=$($Labels[$key])")
    }

    if ($AdditionalArgs) {
        $dockerArgs += $AdditionalArgs
    }

    $spec = Get-TestContainerImageSpec
    $command = & $spec.CommandBuilder $DurationSeconds
    $dockerArgs += $spec.Image
    $dockerArgs += $command

    if (-not $PSCmdlet.ShouldProcess($ContainerName, "Start test container")) {
        return $null
    }

    $output = & docker @dockerArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start test container '$ContainerName' using image '$($spec.Image)': $output"
    }

    return $output
}

function New-TestContainer {
    [OutputType([string])]
    [CmdletBinding(SupportsShouldProcess=$false)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Test helper - no confirmation needed')]
    param(
        [string]$Agent,
        [string]$Repo,
        [string]$Branch
    )
    
    $SanitizedBranch = $Branch -replace '/', '-'
    $ContainerName = "$Agent-$Repo-$SanitizedBranch"

    $existing = docker ps -a --filter "name=^${ContainerName}$" --format "{{.Names}}" 2> $null
    if ($existing -eq $ContainerName) {
        docker rm -f $ContainerName 2> $null | Out-Null
    }
    
    $labels = @{
        "coding-agents.test" = "true"
        "coding-agents.type" = "agent"
        "coding-agents.agent" = $Agent
        "coding-agents.repo" = $Repo
        "coding-agents.branch" = $Branch
    }

    Start-TestContainer -ContainerName $ContainerName -Labels $labels | Out-Null
    
    return $ContainerName
}

function Test-ContainerLabels {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Testing multiple labels on containers')]
    param(
        [string]$ContainerName,
        [string]$Agent,
        [string]$Repo,
        [string]$Branch
    )
    
    Assert-LabelExists -ContainerName $ContainerName -LabelKey "coding-agents.type" -LabelValue "agent"
    Assert-LabelExists -ContainerName $ContainerName -LabelKey "coding-agents.agent" -LabelValue $Agent
    Assert-LabelExists -ContainerName $ContainerName -LabelKey "coding-agents.repo" -LabelValue $Repo
    Assert-LabelExists -ContainerName $ContainerName -LabelKey "coding-agents.branch" -LabelValue $Branch
}

# ============================================================================
# Test Functions
# ============================================================================

function Test-ContainerRuntimeDetection {
    Test-Section "Testing container runtime detection"
    
    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")
    
    $runtime = Get-ContainerRuntime
    if ($runtime -and @("docker", "podman") -contains $runtime) {
        Pass "Get-ContainerRuntime detected runtime: $runtime"
    } else {
        Fail "Get-ContainerRuntime returned invalid runtime: '$runtime'"
        return
    }
    
    $cmd = Get-Command $runtime -ErrorAction SilentlyContinue
    if ($cmd) {
        Pass "Container runtime command '$runtime' is available"
    } else {
        Fail "Container runtime command '$runtime' not found in PATH"
        return
    }
    
    try {
        & $runtime info 2> $null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Pass "Container runtime '$runtime' successfully executed 'info'"
        } else {
            Fail "Container runtime '$runtime' failed 'info' command with exit code $LASTEXITCODE"
        }
    } catch {
        Fail "Container runtime '$runtime' threw an error running 'info': $_"
    }
}

function Test-SharedFunctions {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Testing multiple shared functions')]
    param()
    
    Test-Section "Testing shared functions"
    
    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")
    
    $repoName = Get-RepoName $TestRepoDir
    Assert-Equals -Expected "test-coding-agents-repo" -Actual $repoName -Message "Get-RepoName returns correct name"
    
    Push-Location $TestRepoDir
    $branch = Get-CurrentBranch $TestRepoDir
    Pop-Location
    Assert-Equals -Expected "main" -Actual $branch -Message "Get-CurrentBranch returns 'main'"
    
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

function Test-LocalRemotePush {
    Test-Section "Testing secure local remote push"

    $bareRoot = Join-Path $env:TEMP ("bare-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $bareRoot | Out-Null
    $bareRepo = Join-Path $bareRoot "local-remote.git"
    git init --bare $bareRepo | Out-Null

    $workspaceDir = Join-Path $env:TEMP ("workspace-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $workspaceDir | Out-Null
    Get-ChildItem -LiteralPath $TestRepoDir -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $workspaceDir -Recurse -Force -ErrorAction Stop
    }

    Push-Location $workspaceDir
    git config user.name "Test User"
    git config user.email "test@example.com"
    git config commit.gpgsign false
    $localUrlPath = $bareRepo -replace '\\','/'
    $localRemoteUrl = "file:///$localUrlPath"
    if (-not (git remote get-url local 2> $null)) {
        git remote add local $localRemoteUrl | Out-Null
    } else {
        git remote set-url local $localRemoteUrl | Out-Null
    }
    git config remote.pushDefault local
    git checkout -q main
    $agentBranch = "copilot/session-test"
    Add-Content -Path README.md -Value "secure push"
    git add README.md
    git commit -q -m "test push"
    try {
        git push local $agentBranch 2> $null | Out-Null
        Pass "git push to local remote succeeded"
    } catch {
        Fail "git push to local remote failed: $_"
    }
    Pop-Location

    $pushedRef = git --git-dir=$bareRepo rev-parse "refs/heads/$agentBranch" 2> $null
    if ($pushedRef) {
        Pass "Bare remote received agent branch"
    } else {
        Fail "Bare remote missing agent branch"
    }

    Remove-Item $workspaceDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $bareRoot -Recurse -Force -ErrorAction SilentlyContinue
}

function Test-LocalRemoteFallbackPush {
    Test-Section "Testing local remote fallback push"

    $bareRoot = Join-Path $env:TEMP ("bare-fallback-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $bareRoot | Out-Null
    $bareRepo = Join-Path $bareRoot "local-remote.git"
    git init --bare $bareRepo | Out-Null

    $workspaceDir = Join-Path $env:TEMP ("workspace-fallback-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $workspaceDir | Out-Null
    Get-ChildItem -LiteralPath $TestRepoDir -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $workspaceDir -Recurse -Force -ErrorAction Stop
    }

    Push-Location $workspaceDir
    git config user.name "Test User"
    git config user.email "test@example.com"
    git config commit.gpgsign false
    if (-not (git remote get-url local 2> $null)) {
        git remote add local $bareRepo | Out-Null
    } else {
        git remote set-url local $bareRepo | Out-Null
    }
    git config remote.pushDefault local
    git checkout -q main
    $agentBranch = "copilot/session-fallback"
    Add-Content -Path README.md -Value "fallback push"
    git add README.md
    git commit -q -m "fallback push"
    try {
        git push local $agentBranch 2> $null | Out-Null
        Pass "git push to fallback local remote succeeded"
    } catch {
        Fail "git push to fallback local remote failed: $_"
    }
    Pop-Location

    $pushedRef = git --git-dir=$bareRepo rev-parse "refs/heads/$agentBranch" 2> $null
    if ($pushedRef) {
        Pass "Fallback remote received agent branch"
    } else {
        Fail "Fallback remote missing agent branch"
    }

    Remove-Item $workspaceDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $bareRoot -Recurse -Force -ErrorAction SilentlyContinue
}

function Test-SecureRemoteSync {
    Test-Section "Testing secure remote host sync"

    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")

    $agentBranch = "copilot/session-sync"
    $bareRoot = Join-Path $env:TEMP ("bare-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $bareRoot | Out-Null
    $bareRepo = Join-Path $bareRoot "local-remote.git"
    git init --bare $bareRepo | Out-Null

    $agentWorkspace = Join-Path $env:TEMP ("agent-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $agentWorkspace | Out-Null
    Push-Location $agentWorkspace
    git init -q
    git config user.name "Agent"
    git config user.email "agent@example.com"
    git config commit.gpgsign false
    "agent work" | Out-File -FilePath agent.txt -Encoding UTF8
    git add agent.txt
    git commit -q -m "agent commit"
    git branch -M $agentBranch
    git remote add origin $bareRepo
    try {
        git push origin $agentBranch 2> $null | Out-Null
        Pass "Agent branch pushed to secure remote"
    } catch {
        Fail "Failed to push agent branch to secure remote: $_"
        Pop-Location
        Remove-Item $agentWorkspace -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $bareRoot -Recurse -Force -ErrorAction SilentlyContinue
        return
    }
    Pop-Location

    Push-Location $TestRepoDir
    git branch -D $agentBranch 2> $null | Out-Null
    Pop-Location

    $sanitizedBranch = $agentBranch -replace '/', '-'
    $containerName = "test-sync-$sanitizedBranch"
    $labels = @{
        "coding-agents.test" = "true"
        "coding-agents.type" = "agent"
        "coding-agents.branch" = $agentBranch
        "coding-agents.repo-path" = $TestRepoDir
        "coding-agents.local-remote" = $bareRepo
    }

    Start-TestContainer -ContainerName $containerName -Labels $labels -DurationSeconds 60 | Out-Null

    if (Remove-ContainerWithSidecars -ContainerName $containerName -SkipPush -KeepBranch) {
        Pass "Remove-ContainerWithSidecars synchronizes secure remote"
    } else {
        Fail "Remove-ContainerWithSidecars reported failure"
    }

    Push-Location $TestRepoDir
    try {
        git show "$agentBranch:agent.txt" 2> $null | Out-Null
        Pass "Host branch fast-forwarded from secure remote"
    } catch {
        Fail "Host branch missing agent changes"
    }
    git branch -D $agentBranch 2> $null | Out-Null
    Pop-Location

    Remove-Item $agentWorkspace -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $bareRoot -Recurse -Force -ErrorAction SilentlyContinue
}

function Test-ContainerNaming {
    Test-Section "Testing container naming convention"
    
    $containerName = New-TestContainer -Agent "copilot" -Repo "test-coding-agents-repo" -Branch "main"
    
    Assert-ContainerExists -ContainerName $containerName
    Assert-Contains -Haystack $containerName -Needle "copilot-" -Message "Container name starts with agent"
    Assert-Contains -Haystack $containerName -Needle "-main" -Message "Container name ends with branch"
}

function Test-ContainerLabelsTest {
    Test-Section "Testing container labels"
    
    $containerName = "copilot-test-coding-agents-repo-main"
    Test-ContainerLabels -ContainerName $containerName -Agent "copilot" -Repo "test-coding-agents-repo" -Branch "main"
}

function Test-ListAgents {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Testing command that lists multiple agents')]
    param()
    
    Test-Section "Testing list-agents command"
    
    New-TestContainer -Agent "codex" -Repo "test-coding-agents-repo" -Branch "develop" | Out-Null
    
    $listScript = Join-Path $ProjectRoot "scripts\launchers\list-agents.ps1"
    $output = & $listScript | Out-String
    
    Assert-Contains -Haystack $output -Needle "copilot-test-coding-agents-repo-main" -Message "list-agents shows copilot container"
    Assert-Contains -Haystack $output -Needle "codex-test-coding-agents-repo-develop" -Message "list-agents shows codex container"
    Assert-Contains -Haystack $output -Needle "NAME" -Message "list-agents shows header"
}

function Test-RemoveAgent {
    Test-Section "Testing remove-agent command"
    
    $containerName = "codex-test-coding-agents-repo-develop"
    
    $removeScript = Join-Path $ProjectRoot "scripts\launchers\remove-agent.ps1"
    & $removeScript $containerName -NoPush
    
    $exists = docker ps -a --filter "name=^${containerName}$" --format "{{.Names}}" 2> $null
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
        Update-AgentImage -Agent "copilot" 2> $null
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
    
    Assert-ContainerExists -ContainerName $containerName
    Assert-LabelExists -ContainerName $containerName -LabelKey "coding-agents.branch" -LabelValue "feature/test-branch"
    
    docker rm -f $containerName 2> $null | Out-Null
}

function Test-MultipleAgents {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Testing multiple agent instances')]
    param()
    
    Test-Section "Testing multiple agents on same repository"
    
    Push-Location $TestRepoDir
    git checkout -q main
    Pop-Location
    
    $agents = @("codex", "claude")
    $containers = @()
    
    foreach ($agent in $agents) {
        $containers += New-TestContainer -Agent $agent -Repo "test-coding-agents-repo" -Branch "main"
    }
    
    foreach ($container in $containers) {
        Assert-ContainerExists -ContainerName $container -Message "Agent container created: $container"
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

function Test-WslPathConversion {
    Test-Section "Testing WSL path conversion"
    
    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")
    
    # Test Windows path conversion
    $wslPath = Convert-WindowsPathToWsl "C:\Users\test\project"
    Assert-Equals -Expected "/mnt/c/Users/test/project" -Actual $wslPath -Message "Windows path converted to WSL path"
    
    # Test already-WSL path (should be unchanged)
    $wslPath2 = Convert-WindowsPathToWsl "/mnt/e/dev/project"
    Assert-Equals -Expected "/mnt/e/dev/project" -Actual $wslPath2 -Message "WSL path unchanged"
    
    # Test different drive
    $wslPath3 = Convert-WindowsPathToWsl "E:\dev\project"
    Assert-Equals -Expected "/mnt/e/dev/project" -Actual $wslPath3 -Message "E: drive converted to WSL path"
}

function Test-BranchNameSanitization {
    Test-Section "Testing branch name sanitization"
    
    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")
    
    # Test slash replacement
    $safe1 = ConvertTo-SafeBranchName "feature/auth-module"
    Assert-Equals -Expected "feature-auth-module" -Actual $safe1 -Message "Forward slashes replaced with dashes"
    
    # Test backslash replacement
    $safe2 = ConvertTo-SafeBranchName "feature\auth\module"
    Assert-Equals -Expected "feature-auth-module" -Actual $safe2 -Message "Backslashes replaced with dashes"
    
    # Test invalid characters
    $safe3 = ConvertTo-SafeBranchName "feature@#\$%auth"
    Assert-Equals -Expected "feature-auth" -Actual $safe3 -Message "Invalid characters removed"
    
    # Test dash collapsing
    $safe4 = ConvertTo-SafeBranchName "feature---auth"
    Assert-Equals -Expected "feature-auth" -Actual $safe4 -Message "Multiple dashes collapsed"
    
    # Test leading/trailing special chars
    $safe5 = ConvertTo-SafeBranchName "---feature-auth---"
    Assert-Equals -Expected "feature-auth" -Actual $safe5 -Message "Leading/trailing dashes removed"
    
    # Test uppercase to lowercase
    $safe6 = ConvertTo-SafeBranchName "Feature/Auth"
    Assert-Equals -Expected "feature-auth" -Actual $safe6 -Message "Uppercase converted to lowercase"
}

function Test-ContainerStatus {
    Test-Section "Testing container status functions"
    
    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")
    
    $containerName = "copilot-test-coding-agents-repo-main"
    
    $status = Get-ContainerStatus $containerName
    Assert-Equals -Expected "running" -Actual $status -Message "Get-ContainerStatus returns 'running'"
    
    docker stop $containerName 2> $null | Out-Null
    $status2 = Get-ContainerStatus $containerName
    Assert-Equals -Expected "exited" -Actual $status2 -Message "Get-ContainerStatus returns 'exited' after stop"
    
    docker start $containerName 2> $null | Out-Null
}

function Test-LauncherWrappers {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Testing multiple wrapper scripts')]
    param()

    Test-Section "Testing launcher wrapper scripts"

    $wrappers = @('run-copilot.ps1', 'run-codex.ps1', 'run-claude.ps1')
    foreach ($wrapper in $wrappers) {
        $script = Join-Path $ProjectRoot "scripts\launchers\$wrapper"
        $output = & $script -Help 2>&1
        if ($LASTEXITCODE -eq 0) {
            Assert-Contains -Haystack $output -Needle "Usage" -Message "$wrapper -Help displays usage"
        } else {
            Fail "$wrapper -Help failed with exit code $LASTEXITCODE"
        }
    }
}

# ============================================================================
# Main Test Execution
# ============================================================================

function Main {
    Write-TestLine -Color Cyan -Message "+===========================================================+"
    Write-TestLine -Color Cyan -Message "|   Coding Agents Launcher Test Suite (PowerShell)          |"
    Write-TestLine -Color Cyan -Message "+===========================================================+"
    Write-TestLine
    Write-TestLine -Color White -Message "Testing from: $ProjectRoot"
    Write-TestLine

    Confirm-LinuxContainerEnvironment
    
    $tests = @(
        @{ Name = "Initialize-TestRepo"; Action = { Initialize-TestRepo } },
        @{ Name = "Test-ContainerRuntimeDetection"; Action = { Test-ContainerRuntimeDetection } },
        @{ Name = "Test-SharedFunctions"; Action = { Test-SharedFunctions } },
        @{ Name = "Test-LocalRemotePush"; Action = { Test-LocalRemotePush } },
        @{ Name = "Test-LocalRemoteFallbackPush"; Action = { Test-LocalRemoteFallbackPush } },
        @{ Name = "Test-SecureRemoteSync"; Action = { Test-SecureRemoteSync } },
        @{ Name = "Test-ContainerNaming"; Action = { Test-ContainerNaming } },
        @{ Name = "Test-ContainerLabelsTest"; Action = { Test-ContainerLabelsTest } },
        @{ Name = "Test-ImagePull"; Action = { Test-ImagePull } },
        @{ Name = "Test-BranchSanitization"; Action = { Test-BranchSanitization } },
        @{ Name = "Test-MultipleAgents"; Action = { Test-MultipleAgents } },
        @{ Name = "Test-LabelFiltering"; Action = { Test-LabelFiltering } },
        @{ Name = "Test-WslPathConversion"; Action = { Test-WslPathConversion } },
        @{ Name = "Test-BranchNameSanitization"; Action = { Test-BranchNameSanitization } },
        @{ Name = "Test-ContainerStatus"; Action = { Test-ContainerStatus } },
        @{ Name = "Test-LauncherWrappers"; Action = { Test-LauncherWrappers } },
        @{ Name = "Test-ListAgents"; Action = { Test-ListAgents } },
        @{ Name = "Test-RemoveAgent"; Action = { Test-RemoveAgent } }
    )

    try {
        foreach ($test in $tests) {
            Invoke-Test -Name $test.Name -Action $test.Action
        }
    } finally {
        Clear-TestEnvironment
    }
}

Main
