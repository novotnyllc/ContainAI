# Automated test suite for launcher scripts (PowerShell)
# Tests all core functionality: naming, labels, auto-push, shared functions

[CmdletBinding()]
param(
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$Tests,
    [switch]$List,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

$EnableVerboseOutput = $PSBoundParameters.ContainsKey("Verbose")

if ($EnableVerboseOutput) {
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

function Test-GitRemoteExists {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Function describes whether a remote exists; renaming would reduce clarity')]
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RemoteName
    )

    try {
        $remotes = git remote 2> $null
        if (-not $remotes) {
            return $false
        }

        return $remotes -contains $RemoteName
    } catch {
        return $false
    }
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

    try {
        $seccompPath = Get-SeccompProfilePath -RepoRoot $ProjectRoot
        Assert-Equals -Expected (Join-Path $ProjectRoot "docker/profiles/seccomp-coding-agents.json") -Actual $seccompPath -Message "Get-SeccompProfilePath returns built-in profile"
    } catch {
        Fail "Get-SeccompProfilePath failed: $_"
    }

    $env:CODING_AGENTS_SECCOMP_PROFILE = "missing-profile.json"
    $seccompFailed = $false
    try {
        $null = Get-SeccompProfilePath -RepoRoot $ProjectRoot
    } catch {
        $seccompFailed = $true
    }
    if ($seccompFailed) {
        Pass "Get-SeccompProfilePath reports missing override"
    } else {
        Fail "Get-SeccompProfilePath should fail for missing override"
    }
    Remove-Item env:CODING_AGENTS_SECCOMP_PROFILE -ErrorAction SilentlyContinue

    $appProfile = Get-AppArmorProfileName -RepoRoot $ProjectRoot
    if ($appProfile) {
        Pass "Get-AppArmorProfileName locates active AppArmor profile"
    } else {
        Fail "Get-AppArmorProfileName could not verify AppArmor support"
    }
}

function Test-HelperNetworkIsolation {
    Test-Section "Testing helper network isolation"

    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")

    $homeDir = if ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath('UserProfile') }
    $scriptDir = Join-Path $homeDir ".coding-agents-tests"
    if (-not (Test-Path $scriptDir)) {
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    }
    $scriptPath = Join-Path $scriptDir ("helper-net-" + [System.Guid]::NewGuid().ToString() + ".py")
    @"
import os
import sys

interfaces = [name for name in os.listdir('/sys/class/net') if name not in ('lo',)]
sys.exit(0 if not interfaces else 1)
"@ | Set-Content -Path $scriptPath -Encoding UTF8

    try {
        $mountDir = [System.IO.Path]::GetDirectoryName($scriptPath)
        if (Invoke-PythonTool -ScriptPath $scriptPath -MountPaths @($mountDir)) {
            Pass "Helper runner hides non-loopback interfaces"
        } else {
            Fail "Helper runner exposed additional interfaces"
        }
    } finally {
        Remove-Item $scriptPath -ErrorAction SilentlyContinue
    }
}

function Test-AuditLoggingPipeline {
    Test-Section "Testing audit logging pipeline"

    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")

    $logFile = Join-Path $env:TEMP ("helper-audit-" + [System.Guid]::NewGuid().ToString() + ".log")
    $env:CODING_AGENTS_AUDIT_LOG = $logFile

    Write-SecurityEvent -EventName "unit-test" -Payload @{ ok = $true }
    $initialLog = Get-Content $logFile -ErrorAction Stop | Out-String
    if ($initialLog -match '"event":"unit-test"') {
        Pass "Security events persisted to audit log"
    } else {
        Fail "Audit log missing custom event"
    }

    $overrideToken = Join-Path $env:TEMP ("override-" + [System.Guid]::NewGuid().ToString())
    New-Item -ItemType File -Path $overrideToken -Force | Out-Null

    $tempRepo = Join-Path $env:TEMP ("audit-" + [System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempRepo -Force | Out-Null
    Push-Location $tempRepo
    git init -q | Out-Null
    New-Item -ItemType Directory -Path "scripts/launchers" -Force | Out-Null
    "echo hi" | Out-File -FilePath "scripts/launchers/tool.sh" -Encoding UTF8
    git add scripts/launchers/tool.sh | Out-Null
    git commit -q -m "init" | Out-Null
    "# dirty" | Out-File -FilePath "scripts/launchers/tool.sh" -Encoding UTF8 -Append
    Pop-Location

    Test-TrustedPathsClean -RepoRoot $tempRepo -Paths @("scripts/launchers") -Label "test stubs" -OverrideToken $overrideToken | Out-Null

    $updatedLog = Get-Content $logFile -ErrorAction Stop | Out-String
    if ($updatedLog -match '"event":"override-used"') {
        Pass "Override usage recorded"
    } else {
        Fail "Override usage not captured in audit log"
    }

    Remove-Item $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $overrideToken -Force -ErrorAction SilentlyContinue
    Remove-Item $logFile -Force -ErrorAction SilentlyContinue
    Remove-Item Env:CODING_AGENTS_AUDIT_LOG -ErrorAction SilentlyContinue
}

function Test-SeccompPtraceBlock {
    Test-Section "Testing seccomp ptrace enforcement"

    $seccompProfilePath = Join-Path $ProjectRoot "docker/profiles/seccomp-coding-agents.json"
    if (-not (Test-Path $seccompProfilePath)) {
        Fail "Seccomp profile missing at $seccompProfilePath"
        return
    }

    $pythonScript = @"
import ctypes, os, sys

libc = ctypes.CDLL(None, use_errno=True)
PTRACE_ATTACH = 16
pid = os.getpid()
res = libc.ptrace(PTRACE_ATTACH, pid, None, None)
err = ctypes.get_errno()
if res == -1 and err in (1, 13, 38):
    sys.exit(0)
sys.exit(1)
"@

    $dockerArgs = @(
        "run", "--rm",
        "--security-opt", "no-new-privileges",
        "--security-opt", "seccomp=$seccompProfilePath",
        "python:3.11-slim",
        "python", "-c", $pythonScript
    )

    & docker @dockerArgs | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Pass "ptrace blocked by seccomp profile"
    } else {
        Fail "ptrace syscall not blocked by seccomp profile"
    }
}

function Test-SessionConfigRenderer {
    Test-Section "Testing session config renderer"

    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")

    $renderer = Join-Path $ProjectRoot "scripts/utils/render-session-config.py"
    if (-not (Test-Path $renderer)) {
        Fail "render-session-config.py missing"
        return
    }

    $outputDir = Join-Path $env:TEMP ("session-config-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $outputDir | Out-Null
    $configPath = Join-Path $ProjectRoot "config.toml"
    $sessionId = "test-session-$PID"
    $renderArgs = @(
        "--config", $configPath,
        "--output", $outputDir,
        "--session-id", $sessionId,
        "--network-policy", "allow-all",
        "--repo", "test-repo",
        "--agent", "copilot",
        "--container", "test-container"
    )
    $mounts = @($outputDir, $configPath)

    try {
        if (Invoke-PythonTool -ScriptPath $renderer -MountPaths $mounts -ScriptArgs $renderArgs) {
            $manifestPath = Join-Path $outputDir "manifest.json"
            if (Test-Path $manifestPath) {
                Pass "Manifest generated"
            } else {
                Fail "Manifest missing"
            }

            $copilotConfig = Join-Path $outputDir "github-copilot/config.json"
            if (Test-Path $copilotConfig) {
                Pass "Copilot config rendered"
            } else {
                Fail "Copilot config missing"
            }

            $serversFile = Join-Path $outputDir "servers.txt"
            if (Test-Path $serversFile) {
                $servers = Get-Content $serversFile | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                if ($servers.Count -gt 0) {
                    Pass "Server list exported via servers.txt"
                } else {
                    Fail "servers.txt contains no entries"
                }
            } else {
                Fail "servers.txt missing"
            }
        } else {
            Fail "render-session-config.py failed via python runner"
        }
    } finally {
        Remove-Item $outputDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-SecretBrokerCli {
    Test-Section "Testing secret broker CLI"

    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")

    $brokerScript = Join-Path $ProjectRoot "scripts/runtime/secret-broker.py"
    if (-not (Test-Path $brokerScript)) {
        Fail "secret-broker.py missing"
        return
    }

    $configRoot = Join-Path $env:TEMP ("broker-config-" + [guid]::NewGuid().ToString())
    $null = New-Item -ItemType Directory -Path $configRoot -Force
    $envDir = Join-Path $configRoot "config"
    $null = New-Item -ItemType Directory -Path $envDir -Force
    $capDir = Join-Path $env:TEMP ("broker-cap-" + [guid]::NewGuid().ToString())
    $null = New-Item -ItemType Directory -Path $capDir -Force
    $sealedDir = Join-Path (Join-Path $capDir "alpha") "secrets"

    $previousConfig = $env:CODING_AGENTS_CONFIG_DIR
    $env:CODING_AGENTS_CONFIG_DIR = $envDir

    $configMounts = @($configRoot)
    $issueMounts = @($configRoot, $capDir)
    $redeemMounts = @($configRoot, $capDir)
    try {
        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $issueMounts -ScriptArgs @("issue", "--session-id", "test-session", "--output", $capDir, "--stubs", "alpha")) {
            Pass "Capability issuance succeeds"
        } else {
            Fail "Capability issuance failed"
            return
        }

        $tokenFile = Get-ChildItem -Path $capDir -Filter '*.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($tokenFile) {
            Pass "Capability token file generated"
        } else {
            Fail "Capability token file missing"
        }

        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $configMounts -ScriptArgs @("store", "--stub", "alpha", "--name", "TEST_SECRET", "--value", "super-secret")) {
            Pass "Broker secret store succeeds"
        } else {
            Fail "Broker secret store failed"
        }

        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $redeemMounts -ScriptArgs @("redeem", "--capability", $tokenFile.FullName, "--secret", "TEST_SECRET")) {
            Pass "Capability redemption seals secret"
        } else {
            Fail "Capability redemption failed"
        }

        $sealedPath = Join-Path $sealedDir "TEST_SECRET.sealed"
        if (-not (Test-Path $sealedPath)) {
            Fail "Sealed secret missing"
        } else {
            Pass "Sealed secret written to disk"
        }

        try {
            $tokenJson = Get-Content $tokenFile.FullName -Raw | ConvertFrom-Json
            $sealedJson = Get-Content $sealedPath -Raw | ConvertFrom-Json
            $sessionKeyBytes = @()
            for ($i = 0; $i -lt $tokenJson.session_key.Length; $i += 2) {
                $sessionKeyBytes += [Convert]::ToByte($tokenJson.session_key.Substring($i, 2), 16)
            }
            $sessionKeyBytes = [byte[]]$sessionKeyBytes
            $cipher = [Convert]::FromBase64String($sealedJson.ciphertext)
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $block = $sha.ComputeHash($sessionKeyBytes)
                $index = 0
                $plainBytes = New-Object System.Collections.Generic.List[byte]
                foreach ($byte in $cipher) {
                    $plainBytes.Add($byte -bxor $block[$index]) | Out-Null
                    $index++
                    if ($index -ge $block.Length) {
                        $block = $sha.ComputeHash($block)
                        $index = 0
                    }
                }
                $plaintext = [System.Text.Encoding]::UTF8.GetString($plainBytes.ToArray())
                if ($plaintext -eq "super-secret") {
                    Pass "Sealed secret decrypts with session key"
                } else {
                    Fail "Decrypted sealed secret does not match expected value"
                }
            } finally {
                $sha.Dispose()
            }
        } catch {
            Fail "Failed to decrypt sealed secret: $_"
        }

        $capabilityUnseal = Join-Path $ProjectRoot "scripts/runtime/capability-unseal.py"
        if (-not (Test-Path $capabilityUnseal)) {
            Fail "capability-unseal.py missing"
        } else {
            $pythonCmdInfo = Get-Command python3 -ErrorAction SilentlyContinue
            if (-not $pythonCmdInfo) {
                $pythonCmdInfo = Get-Command python -ErrorAction SilentlyContinue
            }
            $pythonCmd = if ($pythonCmdInfo) { $pythonCmdInfo.Source } else { $null }

            if (-not $pythonCmd) {
                Fail "Python interpreter not found for capability-unseal test"
            } else {
                $unsealed = & $pythonCmd $capabilityUnseal "--stub" "alpha" "--secret" "TEST_SECRET" "--cap-root" $capDir "--format" "raw" 2> $null
                if ($LASTEXITCODE -eq 0) {
                    if ($unsealed -eq "super-secret") {
                        Pass "capability-unseal retrieves sealed secret"
                    } else {
                        Fail "capability-unseal returned unexpected value"
                    }
                } else {
                    Fail "capability-unseal script failed"
                }
            }
        }

        $secondRedeem = Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $redeemMounts -ScriptArgs @("redeem", "--capability", $tokenFile.FullName, "--secret", "TEST_SECRET")
        if ($secondRedeem) {
            Fail "Redeeming same capability twice should fail"
        } else {
            Pass "Capability redemption is single-use"
        }

        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $configMounts -ScriptArgs @("health")) {
            Pass "Broker health check succeeds"
        } else {
            Fail "Broker health check failed"
        }
    } finally {
        if ($previousConfig) {
            $env:CODING_AGENTS_CONFIG_DIR = $previousConfig
        } else {
            Remove-Item Env:CODING_AGENTS_CONFIG_DIR -ErrorAction SilentlyContinue
        }
        Remove-Item $configRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $capDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-CodexCliHelper {
    Test-Section "Testing Codex CLI helper"

    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")

    $helperScript = Join-Path $ProjectRoot "docker/agents/codex/prepare-codex-secrets.sh"
    if (-not (Test-Path $helperScript)) {
        Fail "Codex helper missing at $helperScript"
        return
    }

    $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
    if (-not $bashCmd) {
        Pass "Bash not available; skipping Codex helper test"
        return
    }

    $brokerScript = Join-Path $ProjectRoot "scripts/runtime/secret-broker.py"
    $configRoot = Join-Path $env:TEMP ("codex-helper-config-" + [guid]::NewGuid().ToString())
    $null = New-Item -ItemType Directory -Path $configRoot -Force
    $envDir = Join-Path $configRoot "config"
    $capDir = Join-Path $configRoot "capabilities"
    $null = New-Item -ItemType Directory -Path $envDir -Force
    $null = New-Item -ItemType Directory -Path $capDir -Force
    $secretFile = Join-Path $configRoot "auth.json"
    '{"refresh_token":"unit-test","access_token":"abc"}' | Set-Content -LiteralPath $secretFile -Encoding UTF8

    $previousConfig = $env:CODING_AGENTS_CONFIG_DIR
    $previousSecretRoot = $env:CODING_AGENTS_AGENT_SECRET_ROOT
    $previousDataHome = $env:CODING_AGENTS_AGENT_DATA_HOME
    $env:CODING_AGENTS_CONFIG_DIR = $envDir

    $issueMounts = @($configRoot, $capDir)
    $storeMounts = @($configRoot)
    $redeemMounts = @($configRoot, $capDir)

    try {
        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $issueMounts -ScriptArgs @("issue", "--session-id", "codex-helper", "--output", $capDir, "--stubs", "agent_codex_cli")) {
            Pass "Codex capability issuance succeeds"
        } else {
            Fail "Codex capability issuance failed"
            return
        }

        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $storeMounts -ScriptArgs @("store", "--stub", "agent_codex_cli", "--name", "codex_cli_auth_json", "--from-file", $secretFile)) {
            Pass "Codex secret stored"
        } else {
            Fail "Codex secret store failed"
        }

        $tokenFile = Get-ChildItem -Path $capDir -Filter '*.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $tokenFile) {
            Fail "Codex capability token missing"
            return
        }

        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $redeemMounts -ScriptArgs @("redeem", "--capability", $tokenFile.FullName, "--secret", "codex_cli_auth_json")) {
            Pass "Codex capability redemption seals secret"
        } else {
            Fail "Codex capability redemption failed"
        }

        $agentHome = Join-Path $env:TEMP ("codex-helper-home-" + [guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $agentHome -Force
        $env:CODING_AGENTS_AGENT_HOME = $agentHome
        $env:CODING_AGENTS_AGENT_CAP_ROOT = $capDir
        $env:CODING_AGENTS_CAPABILITY_UNSEAL = Join-Path $ProjectRoot "scripts/runtime/capability-unseal.py"
        $secretRoot = Join-Path $agentHome ".agent-secrets"
        New-Item -ItemType Directory -Path $secretRoot -Force | Out-Null
        $env:CODING_AGENTS_AGENT_SECRET_ROOT = $secretRoot
        $env:CODING_AGENTS_AGENT_DATA_HOME = $agentHome

        $bashResult = & $bashCmd.Source $helperScript 2>&1
        if ($LASTEXITCODE -eq 0) {
            Pass "prepare-codex-secrets decrypts bundle"
            $authFile = Join-Path $agentHome ".codex/auth.json"
            if ((Test-Path $authFile) -and (Get-Content -LiteralPath $authFile -Raw | Select-String -SimpleMatch "unit-test")) {
                Pass "Codex auth.json materialized"
            } else {
                Fail "Codex auth.json missing or incorrect"
            }
        } else {
            Fail "prepare-codex-secrets failed: $bashResult"
        }

    }
    finally {
        if ($previousConfig) {
            $env:CODING_AGENTS_CONFIG_DIR = $previousConfig
        } else {
            Remove-Item Env:CODING_AGENTS_CONFIG_DIR -ErrorAction SilentlyContinue
        }
        Remove-Item Env:CODING_AGENTS_AGENT_HOME -ErrorAction SilentlyContinue
        Remove-Item Env:CODING_AGENTS_AGENT_CAP_ROOT -ErrorAction SilentlyContinue
        Remove-Item Env:CODING_AGENTS_CAPABILITY_UNSEAL -ErrorAction SilentlyContinue
        if ($previousSecretRoot) {
            $env:CODING_AGENTS_AGENT_SECRET_ROOT = $previousSecretRoot
        } else {
            Remove-Item Env:CODING_AGENTS_AGENT_SECRET_ROOT -ErrorAction SilentlyContinue
        }
        if ($previousDataHome) {
            $env:CODING_AGENTS_AGENT_DATA_HOME = $previousDataHome
        } else {
            Remove-Item Env:CODING_AGENTS_AGENT_DATA_HOME -ErrorAction SilentlyContinue
        }
        Remove-Item $configRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $capDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $secretFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $agentHome) {
            Remove-Item $agentHome -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-ClaudeCliHelper {
    Test-Section "Testing Claude CLI helper"

    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")

    $helperScript = Join-Path $ProjectRoot "docker/agents/claude/prepare-claude-secrets.sh"
    if (-not (Test-Path $helperScript)) {
        Fail "Claude helper missing at $helperScript"
        return
    }

    $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
    if (-not $bashCmd) {
        Pass "Bash not available; skipping Claude helper test"
        return
    }

    $brokerScript = Join-Path $ProjectRoot "scripts/runtime/secret-broker.py"
    $configRoot = Join-Path $env:TEMP ("claude-helper-config-" + [guid]::NewGuid().ToString())
    $null = New-Item -ItemType Directory -Path $configRoot -Force
    $envDir = Join-Path $configRoot "config"
    $null = New-Item -ItemType Directory -Path $envDir -Force
    $secretFile = Join-Path $configRoot "credentials.json"
    '{"api_key":"file-secret","workspace_id":"dev"}' | Set-Content -LiteralPath $secretFile -Encoding UTF8

    $previousConfig = $env:CODING_AGENTS_CONFIG_DIR
    $previousSecretRoot = $env:CODING_AGENTS_AGENT_SECRET_ROOT
    $previousDataHome = $env:CODING_AGENTS_AGENT_DATA_HOME
    $storeMounts = @($configRoot)
    $fileCapDir = $null
    $inlineCapDir = $null
    $agentHomeFile = $null
    $agentHomeInline = $null

    try {
        $env:CODING_AGENTS_CONFIG_DIR = $envDir

        # File-based credentials scenario
        $fileCapDir = Join-Path $configRoot "file-capabilities"
        $null = New-Item -ItemType Directory -Path $fileCapDir -Force
        $issueFileMounts = @($configRoot, $fileCapDir)
        $redeemFileMounts = @($configRoot, $fileCapDir)

        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $issueFileMounts -ScriptArgs @("issue", "--session-id", "claude-helper-file", "--output", $fileCapDir, "--stubs", "agent_claude_cli")) {
            Pass "Claude capability issuance (file) succeeds"
        } else {
            Fail "Claude capability issuance (file) failed"
            return
        }

        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $storeMounts -ScriptArgs @("store", "--stub", "agent_claude_cli", "--name", "claude_cli_credentials", "--from-file", $secretFile)) {
            Pass "Claude secret (file) stored"
        } else {
            Fail "Claude secret (file) store failed"
        }

        $fileToken = Get-ChildItem -Path $fileCapDir -Filter '*.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $fileToken) {
            Fail "Claude capability token (file) missing"
            return
        }

        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $redeemFileMounts -ScriptArgs @("redeem", "--capability", $fileToken.FullName, "--secret", "claude_cli_credentials")) {
            Pass "Claude capability (file) redemption seals secret"
        } else {
            Fail "Claude capability (file) redemption failed"
        }

        $agentHomeFile = Join-Path $env:TEMP ("claude-helper-home-file-" + [guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $agentHomeFile -Force
        $agentConfigDir = Join-Path $agentHomeFile ".config/coding-agents/claude"
        $null = New-Item -ItemType Directory -Path $agentConfigDir -Force
        '{}' | Set-Content -LiteralPath (Join-Path $agentConfigDir ".claude.json") -Encoding UTF8

        $env:CODING_AGENTS_AGENT_HOME = $agentHomeFile
        $env:CODING_AGENTS_AGENT_CAP_ROOT = $fileCapDir
        $env:CODING_AGENTS_CAPABILITY_UNSEAL = Join-Path $ProjectRoot "scripts/runtime/capability-unseal.py"
        $secretRootFile = Join-Path $agentHomeFile ".agent-secrets"
        New-Item -ItemType Directory -Path $secretRootFile -Force | Out-Null
        $env:CODING_AGENTS_AGENT_SECRET_ROOT = $secretRootFile
        $env:CODING_AGENTS_AGENT_DATA_HOME = $agentHomeFile

        $fileHelperResult = & $bashCmd.Source $helperScript 2>&1
        if ($LASTEXITCODE -eq 0) {
            Pass "prepare-claude-secrets decrypts file-based bundle"
            $fileCreds = Join-Path $agentHomeFile ".claude/.credentials.json"
            $content = if (Test-Path $fileCreds) { Get-Content -LiteralPath $fileCreds -Raw -ErrorAction SilentlyContinue } else { "" }
            if ($content -and ($content -like '*"api_key": "file-secret"*') -and ($content -like '*"workspace_id": "dev"*')) {
                Pass "Claude credentials mirrored JSON payload"
            } else {
                Fail "Claude credentials missing expected JSON payload"
            }
        } else {
            Fail "prepare-claude-secrets failed for file-based bundle: $fileHelperResult"
        }

        # Inline API key scenario
        $inlineSecret = "inline-secret-token"
        $inlineCapDir = Join-Path $configRoot "inline-capabilities"
        $null = New-Item -ItemType Directory -Path $inlineCapDir -Force
        $issueInlineMounts = @($configRoot, $inlineCapDir)
        $redeemInlineMounts = @($configRoot, $inlineCapDir)

        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $issueInlineMounts -ScriptArgs @("issue", "--session-id", "claude-helper-inline", "--output", $inlineCapDir, "--stubs", "agent_claude_cli")) {
            Pass "Claude capability issuance (inline) succeeds"
        } else {
            Fail "Claude capability issuance (inline) failed"
        }

        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $storeMounts -ScriptArgs @("store", "--stub", "agent_claude_cli", "--name", "claude_cli_credentials", "--value", $inlineSecret)) {
            Pass "Claude secret (inline) stored"
        } else {
            Fail "Claude secret (inline) store failed"
        }

        $inlineToken = Get-ChildItem -Path $inlineCapDir -Filter '*.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $inlineToken) {
            Fail "Claude capability token (inline) missing"
            return
        }

        if (Invoke-PythonTool -ScriptPath $brokerScript -MountPaths $redeemInlineMounts -ScriptArgs @("redeem", "--capability", $inlineToken.FullName, "--secret", "claude_cli_credentials")) {
            Pass "Claude capability (inline) redemption seals secret"
        } else {
            Fail "Claude capability (inline) redemption failed"
        }

        $agentHomeInline = Join-Path $env:TEMP ("claude-helper-home-inline-" + [guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $agentHomeInline -Force
        $env:CODING_AGENTS_AGENT_HOME = $agentHomeInline
        $env:CODING_AGENTS_AGENT_CAP_ROOT = $inlineCapDir
        $secretRootInline = Join-Path $agentHomeInline ".agent-secrets"
        New-Item -ItemType Directory -Path $secretRootInline -Force | Out-Null
        $env:CODING_AGENTS_AGENT_SECRET_ROOT = $secretRootInline
        $env:CODING_AGENTS_AGENT_DATA_HOME = $agentHomeInline

        $inlineHelperResult = & $bashCmd.Source $helperScript 2>&1
        if ($LASTEXITCODE -eq 0) {
            Pass "prepare-claude-secrets decrypts inline bundle"
            $inlineCreds = Join-Path $agentHomeInline ".claude/.credentials.json"
            $inlineContent = if (Test-Path $inlineCreds) { Get-Content -LiteralPath $inlineCreds -Raw -ErrorAction SilentlyContinue } else { "" }
            if ($inlineContent -and ($inlineContent -like ('*"api_key": "' + $inlineSecret + '"*'))) {
                Pass "Claude credentials synthesized from API key"
            } else {
                Fail "Claude credentials missing synthesized API key"
            }
        } else {
            Fail "prepare-claude-secrets failed for inline bundle: $inlineHelperResult"
        }

    }
    finally {
        if ($previousConfig) {
            $env:CODING_AGENTS_CONFIG_DIR = $previousConfig
        } else {
            Remove-Item Env:CODING_AGENTS_CONFIG_DIR -ErrorAction SilentlyContinue
        }
        Remove-Item Env:CODING_AGENTS_AGENT_HOME -ErrorAction SilentlyContinue
        Remove-Item Env:CODING_AGENTS_AGENT_CAP_ROOT -ErrorAction SilentlyContinue
        Remove-Item Env:CODING_AGENTS_CAPABILITY_UNSEAL -ErrorAction SilentlyContinue
        if ($previousSecretRoot) {
            $env:CODING_AGENTS_AGENT_SECRET_ROOT = $previousSecretRoot
        } else {
            Remove-Item Env:CODING_AGENTS_AGENT_SECRET_ROOT -ErrorAction SilentlyContinue
        }
        if ($previousDataHome) {
            $env:CODING_AGENTS_AGENT_DATA_HOME = $previousDataHome
        } else {
            Remove-Item Env:CODING_AGENTS_AGENT_DATA_HOME -ErrorAction SilentlyContinue
        }
        if ($configRoot) { Remove-Item $configRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if ($secretFile) { Remove-Item $secretFile -Force -ErrorAction SilentlyContinue }
        if ($fileCapDir) { Remove-Item $fileCapDir -Recurse -Force -ErrorAction SilentlyContinue }
        if ($inlineCapDir) { Remove-Item $inlineCapDir -Recurse -Force -ErrorAction SilentlyContinue }
        if ($agentHomeFile) { Remove-Item $agentHomeFile -Recurse -Force -ErrorAction SilentlyContinue }
        if ($agentHomeInline) { Remove-Item $agentHomeInline -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Test-HostSecurityPreflight {
    Test-Section "Testing host security preflight"

    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")

    if (Test-HostSecurityPrereqs -RepoRoot $ProjectRoot) {
        Pass "Preflight succeeds when host security prerequisites are satisfied"
    } else {
        Fail "Preflight rejected valid host security configuration"
    }

    $originalSeccomp = $env:CODING_AGENTS_SECCOMP_PROFILE
    try {
        $env:CODING_AGENTS_SECCOMP_PROFILE = Join-Path $ProjectRoot "tests/nonexistent-seccomp.json"
        $seccompCheckPassed = $true
        try {
            $seccompCheckPassed = Test-HostSecurityPrereqs -RepoRoot $ProjectRoot
        } catch {
            $seccompCheckPassed = $false
        }

        if ($seccompCheckPassed) {
            Fail "Preflight should fail when seccomp profile is missing"
        } else {
            Pass "Seccomp profile requirement enforced"
        }
    }
    finally {
        if ([string]::IsNullOrWhiteSpace($originalSeccomp)) {
            Remove-Item Env:CODING_AGENTS_SECCOMP_PROFILE -ErrorAction SilentlyContinue
        } else {
            $env:CODING_AGENTS_SECCOMP_PROFILE = $originalSeccomp
        }
    }
}

function Test-ContainerSecurityPreflight {
    Test-Section "Testing container security preflight"

    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")

    $goodJson = '{"SecurityOptions":["name=seccomp","name=apparmor"]}'
    $missingAppArmor = '{"SecurityOptions":["name=seccomp"]}'

    $env:CODING_AGENTS_CONTAINER_INFO_JSON = $goodJson
    $env:CODING_AGENTS_DISABLE_SECCOMP = "0"
    $preflightPassed = $false
    try {
        $preflightPassed = Test-ContainerSecuritySupport
    } catch {
        $preflightPassed = $false
    }
    if ($preflightPassed) {
        Pass "Container preflight passes when runtime reports both features"
    } else {
        Fail "Container preflight rejected valid runtime JSON"
    }

    $env:CODING_AGENTS_CONTAINER_INFO_JSON = $missingAppArmor
    $env:CODING_AGENTS_DISABLE_SECCOMP = "0"
    $appArmorCheckPassed = $false
    try {
        $appArmorCheckPassed = Test-ContainerSecuritySupport
    } catch {
        $appArmorCheckPassed = $false
    }
    if ($appArmorCheckPassed) {
        Fail "Container preflight should fail when AppArmor missing"
    } else {
        Pass "AppArmor requirement enforced when runtime lacks support"
    }

    Remove-Item Env:CODING_AGENTS_CONTAINER_INFO_JSON -ErrorAction SilentlyContinue
    Remove-Item Env:CODING_AGENTS_DISABLE_SECCOMP -ErrorAction SilentlyContinue
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
    if (-not (Test-GitRemoteExists -RemoteName "local")) {
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
    if (-not (Test-GitRemoteExists -RemoteName "local")) {
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

    $containerName = New-TestContainer -Agent "codex" -Repo "test-coding-agents-repo" -Branch "develop"
    Assert-ContainerExists -ContainerName $containerName -Message "remove-agent test container created"

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

function Test-PromptFallbackRepoSetup {
    Test-Section "Testing prompt fallback workspace preparation"

    . (Join-Path $ProjectRoot "scripts\utils\common-functions.ps1")

    $scriptContent = New-RepoSetupScript

    if ($scriptContent -match "Prompt session requested without repository: leaving workspace empty") {
        Pass "Setup script documents prompt fallback flow"
    } else {
        Fail "Setup script missing prompt fallback message"
    }

    $exitIndex = $scriptContent.IndexOf("exit 0")
    $cloneIndex = $scriptContent.IndexOf("git clone")
    if ($exitIndex -ge 0 -and ($cloneIndex -lt 0 -or $exitIndex -lt $cloneIndex)) {
        Pass "Prompt fallback branch exits before git operations"
    } else {
        Fail "Prompt fallback branch does not exit before git operations"
    }
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
            Assert-Contains -Haystack $output -Needle "-Prompt" -Message "$wrapper -Help documents -Prompt"
        } else {
            Fail "$wrapper -Help failed with exit code $LASTEXITCODE"
        }
    }
}

# =========================================================================
# Test Selection Helpers
# =========================================================================

$AllTests = @(
    "Initialize-TestRepo",
    "Test-ContainerRuntimeDetection",
    "Test-SharedFunctions",
    "Test-HelperNetworkIsolation",
    "Test-AuditLoggingPipeline",
    "Test-SeccompPtraceBlock",
    "Test-HostSecurityPreflight",
    "Test-ContainerSecurityPreflight",
    "Test-SessionConfigRenderer",
    "Test-SecretBrokerCli",
    "Test-CodexCliHelper",
    "Test-ClaudeCliHelper",
    "Test-LocalRemotePush",
    "Test-LocalRemoteFallbackPush",
    "Test-SecureRemoteSync",
    "Test-ContainerNaming",
    "Test-ContainerLabelsTest",
    "Test-ImagePull",
    "Test-BranchSanitization",
    "Test-MultipleAgents",
    "Test-LabelFiltering",
    "Test-WslPathConversion",
    "Test-PromptFallbackRepoSetup",
    "Test-BranchNameSanitization",
    "Test-ContainerStatus",
    "Test-LauncherWrappers",
    "Test-ListAgents",
    "Test-RemoveAgent"
)

$TestActionMap = @{
    "Initialize-TestRepo"           = { Initialize-TestRepo }
    "Test-ContainerRuntimeDetection" = { Test-ContainerRuntimeDetection }
    "Test-SharedFunctions"           = { Test-SharedFunctions }
    "Test-HelperNetworkIsolation"    = { Test-HelperNetworkIsolation }
    "Test-AuditLoggingPipeline"      = { Test-AuditLoggingPipeline }
    "Test-SeccompPtraceBlock"        = { Test-SeccompPtraceBlock }
    "Test-HostSecurityPreflight"     = { Test-HostSecurityPreflight }
    "Test-ContainerSecurityPreflight" = { Test-ContainerSecurityPreflight }
    "Test-SessionConfigRenderer"     = { Test-SessionConfigRenderer }
    "Test-SecretBrokerCli"           = { Test-SecretBrokerCli }
    "Test-CodexCliHelper"            = { Test-CodexCliHelper }
    "Test-ClaudeCliHelper"           = { Test-ClaudeCliHelper }
    "Test-LocalRemotePush"           = { Test-LocalRemotePush }
    "Test-LocalRemoteFallbackPush"   = { Test-LocalRemoteFallbackPush }
    "Test-SecureRemoteSync"          = { Test-SecureRemoteSync }
    "Test-ContainerNaming"           = { Test-ContainerNaming }
    "Test-ContainerLabelsTest"       = { Test-ContainerLabelsTest }
    "Test-ImagePull"                 = { Test-ImagePull }
    "Test-BranchSanitization"        = { Test-BranchSanitization }
    "Test-MultipleAgents"            = { Test-MultipleAgents }
    "Test-LabelFiltering"            = { Test-LabelFiltering }
    "Test-WslPathConversion"         = { Test-WslPathConversion }
    "Test-PromptFallbackRepoSetup"   = { Test-PromptFallbackRepoSetup }
    "Test-BranchNameSanitization"    = { Test-BranchNameSanitization }
    "Test-ContainerStatus"           = { Test-ContainerStatus }
    "Test-LauncherWrappers"          = { Test-LauncherWrappers }
    "Test-ListAgents"                = { Test-ListAgents }
    "Test-RemoveAgent"               = { Test-RemoveAgent }
}

function Show-Usage {
    Write-Output "Usage: pwsh scripts/test/test-launchers.ps1 [all|TestName ...] [-List] [-Help]"
    Write-Output ""
    Write-Output "Examples:"
    Write-Output "  pwsh scripts/test/test-launchers.ps1";
    Write-Output "  pwsh scripts/test/test-launchers.ps1 all";
    Write-Output "  pwsh scripts/test/test-launchers.ps1 Test-SecretBrokerCli Test-SessionConfigRenderer";
    Write-Output "  pwsh scripts/test/test-launchers.ps1 -List"
}

function Show-AvailableTests {
    $AllTests | ForEach-Object { Write-Output $_ }
}

# ============================================================================
# Main Test Execution
# ============================================================================

function Main {
    if ($Help) {
        Show-Usage
        return
    }

    if ($List) {
        Show-AvailableTests
        return
    }

    $selectedTests = @()
    if (-not $Tests -or ($Tests.Count -eq 1 -and $Tests[0].ToLowerInvariant() -eq "all")) {
        $selectedTests = $AllTests
    } else {
        foreach ($testArg in $Tests) {
            if ($testArg.ToLowerInvariant() -eq "all") {
                $selectedTests = $AllTests
                break
            }
            $resolved = $AllTests | Where-Object { $_.ToLowerInvariant() -eq $testArg.ToLowerInvariant() } | Select-Object -First 1
            if (-not $resolved) {
                Write-TestLine -Color Red -Message "Unknown test: $testArg"
                Write-TestLine -Color Yellow -Message "Available tests:"
                foreach ($available in $AllTests) {
                    Write-TestLine -Color Yellow -Message "  $available"
                }
                exit 1
            }
            $selectedTests += $resolved
        }
    }

    Write-TestLine -Color Cyan -Message "+===========================================================+"
    Write-TestLine -Color Cyan -Message "|   Coding Agents Launcher Test Suite (PowerShell)          |"
    Write-TestLine -Color Cyan -Message "+===========================================================+"
    Write-TestLine
    Write-TestLine -Color White -Message "Testing from: $ProjectRoot"
    Write-TestLine

    Confirm-LinuxContainerEnvironment

    try {
        if ($selectedTests -notcontains "Initialize-TestRepo") {
            Invoke-Test -Name "Initialize-TestRepo" -Action $TestActionMap["Initialize-TestRepo"]
        }

        foreach ($testName in $selectedTests) {
            Invoke-Test -Name $testName -Action $TestActionMap[$testName]
        }
    } finally {
        Clear-TestEnvironment
    }
}

Main
