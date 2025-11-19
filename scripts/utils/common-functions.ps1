# Common functions for agent management scripts (PowerShell)

$script:RepoRootDefault = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

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

$script:OverrideDir = if ($env:CODING_AGENTS_OVERRIDE_DIR) {
    $env:CODING_AGENTS_OVERRIDE_DIR
} else {
    Join-Path $script:ConfigRoot "overrides"
}

$script:DirtyOverrideToken = if ($env:CODING_AGENTS_DIRTY_OVERRIDE_TOKEN) {
    $env:CODING_AGENTS_DIRTY_OVERRIDE_TOKEN
} else {
    Join-Path $script:OverrideDir "allow-dirty"
}

$script:CacheRoot = if ($env:CODING_AGENTS_CACHE_DIR) {
    $env:CODING_AGENTS_CACHE_DIR
} else {
    Join-Path $script:ConfigRoot "cache"
}

$script:PrereqCacheFile = if ($env:CODING_AGENTS_PREREQ_CACHE_FILE) {
    $env:CODING_AGENTS_PREREQ_CACHE_FILE
} else {
    Join-Path $script:CacheRoot "prereq-check"
}

$script:BrokerScript = if ($env:CODING_AGENTS_BROKER_SCRIPT) {
    $env:CODING_AGENTS_BROKER_SCRIPT
} else {
    Join-Path $script:RepoRootDefault "scripts/runtime/secret-broker.py"
}

$script:AuditLogPath = if ($env:CODING_AGENTS_AUDIT_LOG) {
    $env:CODING_AGENTS_AUDIT_LOG
} else {
    Join-Path $script:ConfigRoot "security-events.log"
}

$script:HelperNetworkPolicy = if ($env:CODING_AGENTS_HELPER_NETWORK_POLICY) {
    $env:CODING_AGENTS_HELPER_NETWORK_POLICY
} else {
    "loopback"
}

$helperPidLimitValue = 64
if ($env:CODING_AGENTS_HELPER_PIDS_LIMIT) {
    [int]::TryParse($env:CODING_AGENTS_HELPER_PIDS_LIMIT, [ref]$helperPidLimitValue) | Out-Null
}
$script:HelperPidLimit = $helperPidLimitValue

$script:HelperMemory = if ($env:CODING_AGENTS_HELPER_MEMORY) {
    $env:CODING_AGENTS_HELPER_MEMORY
} else {
    "512m"
}

$script:GitExecutable = $null

$script:DefaultLauncherUpdatePolicy = "prompt"
$script:ContainerCli = $null

function Write-AgentMessage {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='Human-facing launcher output requires colorized console text')]
    param(
        [string]$Message = "",
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
    )

    Write-Host $Message -ForegroundColor $Color
}

function Get-StringSha256 {
    param([string]$InputString = "")

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $hash = $sha.ComputeHash($stream)
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
}

function Get-ToolVersionString {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @('--version'),
        [switch]$FirstLineOnly
    )

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return "missing"
    }

    try {
        $output = & $cmd @Arguments 2>&1
        if ($LASTEXITCODE -ne 0 -or -not $output) {
            return "missing"
        }
        $text = if ($FirstLineOnly) { ($output | Select-Object -First 1) } else { $output }
        return (($text -join ' ').Trim())
    } catch {
        return "missing"
    }
}

function Get-PrereqFingerprint {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $entries = [System.Collections.Generic.List[string]]::new()
    $psScript = Join-Path $RepoRoot 'scripts/verify-prerequisites.ps1'
    $bashScript = Join-Path $RepoRoot 'scripts/verify-prerequisites.sh'
    $scriptPath = if (Test-Path $psScript) { $psScript } elseif (Test-Path $bashScript) { $bashScript } else { $null }
    if ($scriptPath) {
        $hash = Get-FileSha256 -Path $scriptPath
        $entries.Add("script=$hash")
    } else {
        $entries.Add("script=missing")
    }

    $entries.Add("docker=$(Get-ToolVersionString -Command 'docker' -FirstLineOnly)")
    $entries.Add("podman=$(Get-ToolVersionString -Command 'podman' -FirstLineOnly)")
    $entries.Add("socat=$(Get-ToolVersionString -Command 'socat' -Arguments @('-V') -FirstLineOnly)")
    $entries.Add("git=$(Get-ToolVersionString -Command 'git' -FirstLineOnly)")
    $entries.Add("gh=$(Get-ToolVersionString -Command 'gh' -FirstLineOnly)")

    $osDescription = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    $entries.Add("uname=$osDescription-$osArch")

    $joined = [string]::Join([Environment]::NewLine, $entries)
    return Get-StringSha256 -InputString $joined
}

function Test-PrerequisitesVerified {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    if ($env:CODING_AGENTS_DISABLE_AUTO_PREREQ_CHECK -eq "1") {
        return $true
    }

    $psScript = Join-Path $RepoRoot 'scripts/verify-prerequisites.ps1'
    $bashScript = Join-Path $RepoRoot 'scripts/verify-prerequisites.sh'
    $scriptPath = if (Test-Path $psScript) { $psScript } elseif (Test-Path $bashScript) { $bashScript } else { $null }
    if (-not $scriptPath) {
        return $true
    }

    $fingerprint = Get-PrereqFingerprint -RepoRoot $RepoRoot
    if (-not $fingerprint) {
        return $true
    }

    $cachePath = if ($env:CODING_AGENTS_PREREQ_CACHE_FILE) { $env:CODING_AGENTS_PREREQ_CACHE_FILE } else { $script:PrereqCacheFile }
    $cached = if (Test-Path $cachePath) { (Get-Content -Path $cachePath -TotalCount 1 -ErrorAction SilentlyContinue) } else { $null }
    if ($cached -and $cached -eq $fingerprint) {
        return $true
    }

    Write-AgentMessage -Message "🔍 Running prerequisite verification (first launch or dependency change detected)..." -Color Cyan
    if ($scriptPath.ToLower().EndsWith('.ps1')) {
        & $scriptPath
    } else {
        & bash $scriptPath
    }
    if ($LASTEXITCODE -ne 0) {
        Write-AgentMessage -Message "❌ Automatic prerequisite check failed. Resolve the issues above or rerun $scriptPath manually." -Color Red
        return $false
    }

    $cacheDir = Split-Path -Parent $cachePath
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $content = "{0}`n{1}" -f $fingerprint, (Get-Date).ToUniversalTime().ToString('o')
    Set-Content -Path $cachePath -Value $content -Encoding UTF8
    Write-AgentMessage -Message "✅ Prerequisites verified. Results cached for future launches." -Color Green
    return $true
}

function Get-GitExecutable {
    if ($script:GitExecutable) {
        return $script:GitExecutable
    }

    try {
        $git = Get-Command git -ErrorAction Stop
        $script:GitExecutable = $git.Source
        return $script:GitExecutable
    } catch {
        return $null
    }
}

function Get-GitHeadHash {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $git = Get-GitExecutable
    if (-not $git) {
        return $null
    }
    if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
        return $null
    }
    try {
        $result = & $git -C $RepoRoot rev-parse HEAD 2> $null
        if ($LASTEXITCODE -eq 0) {
            return $result.Trim()
        }
    } catch {
        Write-Verbose "Get-GitHeadHash failed: $_"
    }
    return $null
}

function Get-TrustedPathTreeHashes {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Returns multiple hashes, plural form is intentional')]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string[]]$Paths
    )

    $git = Get-GitExecutable
    if (-not $git) {
        return @()
    }

    $hashes = @()
    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        try {
            & $git -C $RepoRoot rev-parse --verify --quiet "HEAD:$path" 2> $null | Out-Null
            if ($LASTEXITCODE -ne 0) { continue }
            $hash = & $git -C $RepoRoot rev-parse "HEAD:$path" 2> $null
            if ($LASTEXITCODE -eq 0 -and $hash) {
                $hashes += [pscustomobject]@{ Path = $path; Hash = $hash.Trim() }
            }
        } catch {
            Write-Verbose "Get-TrustedPathTreeHashes failed for '$path': $_"
        }
    }
    return $hashes
}

function Write-SecurityEvent {
    param(
        [Parameter(Mandatory = $true)][string]$EventName,
        [Parameter(Mandatory = $true)][hashtable]$Payload
    )

    if ($env:CODING_AGENTS_DISABLE_AUDIT_LOG -eq "1") {
        return
    }

    $record = [pscustomobject]@{
        ts = (Get-Date).ToUniversalTime().ToString("o")
        event = $EventName
        payload = $Payload
    }
    $json = $record | ConvertTo-Json -Depth 6 -Compress
    $logPath = if ($env:CODING_AGENTS_AUDIT_LOG) { $env:CODING_AGENTS_AUDIT_LOG } else { $script:AuditLogPath }
    $fullLogPath = [System.IO.Path]::GetFullPath($logPath)
    $logDir = [System.IO.Path]::GetDirectoryName($fullLogPath)
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    Add-Content -Path $fullLogPath -Value $json -Encoding utf8
    $systemdCat = Get-Command systemd-cat -ErrorAction SilentlyContinue
    if ($systemdCat) {
        try {
            $json | systemd-cat -t "coding-agents-launcher" | Out-Null
        } catch {
            Write-Verbose "systemd-cat logging failed: $_"
        }
    }
}

function Write-OverrideUsageEvent {
    param(
        [string]$RepoRoot,
        [string]$Label,
        [string[]]$DirtyPaths
    )

    if (-not $DirtyPaths -or $DirtyPaths.Count -eq 0) {
        return
    }

    $payload = @{
        repo = $RepoRoot
        label = $Label
        dirtyPaths = $DirtyPaths
    }
    Write-SecurityEvent -EventName "override-used" -Payload $payload
}

function Write-SessionConfigEvent {
    param(
        [string]$SessionId,
        [string]$ManifestSha,
        [string]$RepoRoot,
        [System.Collections.IEnumerable]$TrustedHashes
    )

    $payload = @{
        session = $SessionId
        manifestSha = if ($ManifestSha) { $ManifestSha } else { "unknown" }
        gitHead = Get-GitHeadHash -RepoRoot $RepoRoot
        trustedTrees = $TrustedHashes
    }
    Write-SecurityEvent -EventName "session-config" -Payload $payload
}

function Write-CapabilityIssuanceEvent {
    param(
        [string]$SessionId,
        [string]$OutputDir,
        [string[]]$Stubs,
        [string]$RepoRoot
    )

    if (-not (Test-Path $OutputDir)) {
        return
    }

    $capabilities = Get-ChildItem -Path $OutputDir -Recurse -Filter *.json -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            stub = $_.Directory.Name
            capabilityId = $_.BaseName
        }
    }

    $payload = @{
        session = $SessionId
        gitHead = Get-GitHeadHash -RepoRoot $RepoRoot
        manifestSha = if ($env:CODING_AGENTS_SESSION_CONFIG_SHA256) { $env:CODING_AGENTS_SESSION_CONFIG_SHA256 } else { "unknown" }
        stubs = $Stubs
        capabilities = $capabilities
    }
    Write-SecurityEvent -EventName "capabilities-issued" -Payload $payload
}

function Test-TrustedPathsClean {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [string]$Label = "trusted files",
        [switch]$ThrowOnFailure,
        [string]$OverrideToken
    )

    $git = Get-GitExecutable
    if (-not $git) {
        $message = "Git is required to verify $Label"
        if ($ThrowOnFailure) { throw $message }
        Write-Warning $message
        return $false
    }

    if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
        $message = "Unable to verify $Label; .git directory not found"
        if ($ThrowOnFailure) { throw $message }
        Write-Warning $message
        return $false
    }

    $dirty = @()
    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        try {
            $status = & $git -C $RepoRoot status --short -- $path 2> $null
            if ($status) {
                $dirty += $path
            }
        } catch {
            Write-Verbose "Failed to inspect trusted path '$path': $_"
        }
    }

    if ($dirty.Count -eq 0) {
        return $true
    }

    $overrideToken = if (-not [string]::IsNullOrWhiteSpace($OverrideToken)) {
        $OverrideToken
    } elseif ($env:CODING_AGENTS_DIRTY_OVERRIDE_TOKEN) {
        $env:CODING_AGENTS_DIRTY_OVERRIDE_TOKEN
    } else {
        $script:DirtyOverrideToken
    }

    if (Test-Path $overrideToken) {
        Write-Warning "Override token '$overrideToken' detected; proceeding with dirty ${Label}: $($dirty -join ', ')"
        Write-OverrideUsageEvent -RepoRoot $RepoRoot -Label $Label -DirtyPaths $dirty
        return $true
    }

    $message = "Trusted $Label have uncommitted changes: $($dirty -join ', ')"
    if ($ThrowOnFailure) {
        throw $message
    }
    Write-Error $message
    return $false
}

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

function Get-SecretBrokerScript {
    if ($script:BrokerScript -and (Test-Path $script:BrokerScript)) {
        return $script:BrokerScript
    }
    return $null
}

function Test-SecretBrokerReady {
    $broker = Get-SecretBrokerScript
    if (-not $broker) {
        Write-Warning "Secret broker script not found"
        return $false
    }
    if (Invoke-PythonTool -ScriptPath $broker -ScriptArgs @('health')) {
        return $true
    }
    Write-Error "Secret broker health check failed"
    return $false
}

function Invoke-SessionCapabilityIssue {
    param(
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$OutputDir,
        [string[]]$Stubs
    )

    if (-not $Stubs -or $Stubs.Count -eq 0) {
        return $true
    }

    $broker = Get-SecretBrokerScript
    if (-not $broker) {
        Write-Error "Secret broker script not found"
        return $false
    }

    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $scriptArgs = @('issue', '--session-id', $SessionId, '--output', $OutputDir, '--stubs') + $Stubs
    $result = Invoke-PythonTool -ScriptPath $broker -MountPaths @($OutputDir) -ScriptArgs $scriptArgs
    if ($result) {
        Write-CapabilityIssuanceEvent -SessionId $SessionId -OutputDir $OutputDir -Stubs $Stubs -RepoRoot $script:RepoRootDefault
    }
    return $result
}

function Get-SeccompProfilePath {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $candidate = if ($env:CODING_AGENTS_SECCOMP_PROFILE) {
        $env:CODING_AGENTS_SECCOMP_PROFILE
    } else {
        Join-Path $RepoRoot "docker/profiles/seccomp-coding-agents.json"
    }

    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $RepoRoot $candidate
    }

    if (-not (Test-Path $candidate)) {
        throw "Seccomp profile not found at $candidate"
    }

    return (Resolve-Path $candidate).ProviderPath
}

function Test-AppArmorSupported {
    if (-not $IsLinux) { return $false }
    $flagPath = "/sys/module/apparmor/parameters/enabled"
    if (-not (Test-Path $flagPath)) { return $false }
    $status = (Get-Content $flagPath -ErrorAction SilentlyContinue)
    if (-not $status) { return $false }
    return ($status -match '^(Y|y)')
}

function Test-AppArmorProfileLoaded {
    param([Parameter(Mandatory = $true)][string]$Name)

    $profilesFile = "/sys/kernel/security/apparmor/profiles"
    if (-not (Test-Path $profilesFile)) { return $false }
    $pattern = "^{0}\s" -f [System.Text.RegularExpressions.Regex]::Escape($Name)
    return Select-String -Path $profilesFile -Pattern $pattern -Quiet -ErrorAction SilentlyContinue
}

function Get-AppArmorProfileName {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    if ($env:CODING_AGENTS_DISABLE_APPARMOR -eq '1') {
        return $null
    }

    if (-not (Test-AppArmorSupported)) {
        return $null
    }

    $profileName = if ($env:CODING_AGENTS_APPARMOR_PROFILE_NAME) {
        $env:CODING_AGENTS_APPARMOR_PROFILE_NAME
    } else {
        "coding-agents"
    }

    if (Test-AppArmorProfileLoaded -Name $profileName) {
        return $profileName
    }

    $profilePath = if ($env:CODING_AGENTS_APPARMOR_PROFILE_FILE) {
        $env:CODING_AGENTS_APPARMOR_PROFILE_FILE
    } else {
        Join-Path $RepoRoot "docker/profiles/apparmor-coding-agents.profile"
    }

    if (-not (Test-Path $profilePath)) {
        Write-Warning "⚠️  AppArmor profile file not found at $profilePath"
        return $null
    }

    Write-Warning "⚠️  AppArmor profile '$profileName' is not loaded. Run: sudo apparmor_parser -r '$profilePath'"
    return $null
}

function Test-HostSecurityPrereqs {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Validates multiple prerequisites in a single call')]
    param(
        [string]$RepoRoot
    )

    $resolvedRoot = if ($RepoRoot) {
        $RepoRoot
    } elseif ($env:CODING_AGENTS_REPO_ROOT) {
        $env:CODING_AGENTS_REPO_ROOT
    } else {
        $script:RepoRootDefault
    }

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    if ($env:CODING_AGENTS_DISABLE_SECCOMP -eq '1') {
        $warnings.Add('Seccomp enforcement disabled via CODING_AGENTS_DISABLE_SECCOMP=1') | Out-Null
    } else {
        try {
            Get-SeccompProfilePath -RepoRoot $resolvedRoot | Out-Null
        } catch {
            $hint = if ($env:CODING_AGENTS_SECCOMP_PROFILE) { $env:CODING_AGENTS_SECCOMP_PROFILE } else { Join-Path $resolvedRoot 'docker/profiles/seccomp-coding-agents.json' }
            if (-not [System.IO.Path]::IsPathRooted($hint)) {
                $hint = Join-Path $resolvedRoot $hint
            }
            $errors.Add("Seccomp profile not found at $hint. Install host security profiles or set CODING_AGENTS_DISABLE_SECCOMP=1 (not recommended).") | Out-Null
        }
    }

    if ($env:CODING_AGENTS_DISABLE_APPARMOR -eq '1') {
        $warnings.Add('AppArmor enforcement disabled via CODING_AGENTS_DISABLE_APPARMOR=1') | Out-Null
    } else {
        if (-not $IsLinux) {
            $errors.Add('AppArmor enforcement requires a Linux host. Run from Linux or export CODING_AGENTS_DISABLE_APPARMOR=1 to acknowledge the risk.') | Out-Null
        } elseif (-not (Test-AppArmorSupported)) {
            $errors.Add('AppArmor kernel support not detected. Enable AppArmor or export CODING_AGENTS_DISABLE_APPARMOR=1 to override.') | Out-Null
        } else {
            $profileName = if ($env:CODING_AGENTS_APPARMOR_PROFILE_NAME) { $env:CODING_AGENTS_APPARMOR_PROFILE_NAME } else { 'coding-agents' }
            if (-not (Test-AppArmorProfileLoaded -Name $profileName)) {
                $profilePath = if ($env:CODING_AGENTS_APPARMOR_PROFILE_FILE) { $env:CODING_AGENTS_APPARMOR_PROFILE_FILE } else { Join-Path $resolvedRoot 'docker/profiles/apparmor-coding-agents.profile' }
                if (-not [System.IO.Path]::IsPathRooted($profilePath)) {
                    $profilePath = Join-Path $resolvedRoot $profilePath
                }
                if (-not (Test-Path $profilePath)) {
                    $errors.Add("AppArmor profile file '$profilePath' not found. Set CODING_AGENTS_APPARMOR_PROFILE_FILE to a valid profile path.") | Out-Null
                } else {
                    $errors.Add("AppArmor profile '$profileName' is not loaded. Run: sudo apparmor_parser -r '$profilePath' or export CODING_AGENTS_DISABLE_APPARMOR=1 to override.") | Out-Null
                }
            }
        }
    }

    if ($env:CODING_AGENTS_DISABLE_PTRACE_SCOPE -eq '1') {
        $warnings.Add('Ptrace scope hardening disabled via CODING_AGENTS_DISABLE_PTRACE_SCOPE=1') | Out-Null
    } elseif ($IsLinux -and -not (Test-Path '/proc/sys/kernel/yama/ptrace_scope')) {
        $errors.Add('kernel.yama.ptrace_scope is unavailable. Enable the Yama LSM or export CODING_AGENTS_DISABLE_PTRACE_SCOPE=1 to bypass (not recommended).') | Out-Null
    }

    if ($env:CODING_AGENTS_DISABLE_SENSITIVE_TMPFS -eq '1') {
        $warnings.Add('Sensitive tmpfs mounting disabled via CODING_AGENTS_DISABLE_SENSITIVE_TMPFS=1') | Out-Null
    }

    if ($errors.Count -gt 0) {
        $joined = $errors -join "`n  - "
        Write-Error "Host security verification failed:`n  - $joined"
        return $false
    }

    if ($warnings.Count -gt 0) {
        $joinedWarnings = $warnings -join "`n  - "
        Write-Warning "Host security warnings:`n  - $joinedWarnings"
    }

    return $true
}

function Test-ContainerSecuritySupport {
    if ($env:CODING_AGENTS_DISABLE_CONTAINER_SECURITY_CHECK -eq '1') {
        Write-Warning "Container security checks disabled via CODING_AGENTS_DISABLE_CONTAINER_SECURITY_CHECK=1"
        return $true
    }

    $requireSeccomp = ($env:CODING_AGENTS_DISABLE_SECCOMP -ne '1')
    $requireAppArmor = ($env:CODING_AGENTS_DISABLE_APPARMOR -ne '1')
    if (-not $requireSeccomp -and -not $requireAppArmor) {
        return $true
    }

    $infoJson = $env:CODING_AGENTS_CONTAINER_INFO_JSON
    if (-not $infoJson) {
        $cli = Get-ContainerCli
        if (-not $cli) {
            Write-Error "Unable to determine container runtime for security checks"
            return $false
        }
        try {
            $infoJson = & $cli info --format '{{json .}}' 2> $null
            if (-not $infoJson) {
                $infoJson = & $cli info --format json 2> $null
            }
        } catch {
            $infoJson = $null
        }
    }

    if (-not $infoJson) {
        Write-Error "Unable to inspect container runtime security options"
        return $false
    }

    try {
        $info = $infoJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Error "Failed to parse container runtime security information"
        return $false
    }

    $hasSeccomp = $false
    $hasAppArmor = $false

    $securityOptions = @()
    if ($info.SecurityOptions) { $securityOptions += $info.SecurityOptions }
    if ($info.securityOptions) { $securityOptions += $info.securityOptions }

    foreach ($entry in $securityOptions) {
        if ($entry -is [string]) {
            $lower = $entry.ToLowerInvariant()
            if ($lower -match 'seccomp') { $hasSeccomp = $true }
            if ($lower -match 'apparmor') { $hasAppArmor = $true }
        }
    }

    $hostInfo = $info.host
    if ($hostInfo) {
        $security = $hostInfo.security
        if ($security) {
            if ($security.seccompProfilePath -or $security.seccompEnabled) {
                $hasSeccomp = $true
            }
            if ($security.apparmorEnabled) {
                $hasAppArmor = $true
            }
        }
        if ($hostInfo.seccomp -and $hostInfo.seccomp.ToString().ToLowerInvariant() -eq 'enabled') {
            $hasSeccomp = $true
        }
        if ($hostInfo.apparmor -and $hostInfo.apparmor.ToString().ToLowerInvariant() -eq 'enabled') {
            $hasAppArmor = $true
        }
    }

    if ($requireSeccomp -and -not $hasSeccomp) {
        Write-Error "Container runtime does not report seccomp support. Update Docker/Podman or set CODING_AGENTS_DISABLE_SECCOMP=1 to override."
        return $false
    }

    if ($requireAppArmor -and -not $hasAppArmor) {
        Write-Error "Container runtime does not report AppArmor support. Enable the module or set CODING_AGENTS_DISABLE_APPARMOR=1 to override."
        return $false
    }

    return $true
}

function Get-SanitizedDockerName {
    param([Parameter(Mandatory = $true)][string]$Name)

    $normalized = $Name.ToLowerInvariant()
    $builder = New-Object System.Text.StringBuilder
    foreach ($ch in $normalized.ToCharArray()) {
        if ($ch -match '[a-z0-9_.-]') {
            [void]$builder.Append($ch)
        } else {
            [void]$builder.Append('-')
        }
    }
    $result = $builder.ToString().Trim('-')
    if ([string]::IsNullOrWhiteSpace($result)) {
        $result = "agent"
    }
    if ($result.Length -gt 48) {
        $result = $result.Substring(0, 48)
    }
    return $result
}

function Get-ContainerVolumeName {
    param(
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [Parameter(Mandatory = $true)][string]$Suffix
    )

    $base = Get-SanitizedDockerName -Name $ContainerName
    $tail = Get-SanitizedDockerName -Name $Suffix
    return "$base-$tail"
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
        Write-AgentMessage -Message "⚠️  Skipping launcher update check (git not available)" -Color Yellow
        return
    }

    git -C $RepoRoot rev-parse HEAD 2> $null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return
    }

    $upstream = git -C $RepoRoot rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2> $null
    if ($LASTEXITCODE -ne 0 -or -not $upstream) {
        return
    }

    git -C $RepoRoot fetch --quiet --tags 2> $null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-AgentMessage -Message "⚠️  Unable to check launcher updates (git fetch failed)" -Color Yellow
        return
    }

    $localHead = git -C $RepoRoot rev-parse HEAD 2> $null
    $remoteHead = git -C $RepoRoot rev-parse '@{u}' 2> $null
    $base = git -C $RepoRoot merge-base HEAD '@{u}' 2> $null

    if ($localHead -eq $remoteHead) {
        return
    }

    if ($localHead -ne $base -and $remoteHead -ne $base) {
        Write-AgentMessage -Message "⚠️  Launcher repository has diverged from $upstream. Please sync manually." -Color Yellow
        return
    }

    $clean = $true
    git -C $RepoRoot diff --quiet 2> $null
    if ($LASTEXITCODE -ne 0) { $clean = $false }
    if ($clean) {
        git -C $RepoRoot diff --quiet --cached 2> $null
        if ($LASTEXITCODE -ne 0) { $clean = $false }
    }

    if ($policy -eq 'always') {
        if (-not $clean) {
            Write-AgentMessage -Message "⚠️  Launcher repository has local changes; cannot auto-update." -Color Yellow
            return
        }
        git -C $RepoRoot pull --ff-only | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-AgentMessage -Message "✅ Launcher scripts updated to match $upstream" -Color Green
        } else {
            Write-AgentMessage -Message "⚠️  Failed to auto-update launcher scripts. Please update manually." -Color Yellow
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
        Write-AgentMessage -Message "⚠️  Launcher scripts are behind $upstream. Update the repository when convenient." -Color Yellow
        return
    }

    $suffix = if ($Context) { " ($Context)" } else { "" }
    Write-AgentMessage -Message "ℹ️  Launcher scripts are behind $upstream.$suffix" -Color Cyan
    if (-not $clean) {
        Write-AgentMessage -Message "   Local changes detected; please update manually." -Color Yellow
        return
    }

    $response = Read-Host "Update Coding Agents launchers now? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($response)) { $response = "y" }
    if ($response.StartsWith('y', 'InvariantCultureIgnoreCase')) {
        git -C $RepoRoot pull --ff-only | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-AgentMessage -Message "✅ Launcher scripts updated." -Color Green
        } else {
            Write-AgentMessage -Message "⚠️  Failed to update launchers. Please update manually." -Color Yellow
        }
    } else {
        Write-AgentMessage -Message "⏭️  Skipped launcher update." -Color Yellow
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
        $null = docker info 2> $null
        if ($LASTEXITCODE -eq 0) {
            return "docker"
        }
    } catch {
        Write-Verbose "docker info probe failed: $_"
    }

    try {
        $null = podman info 2> $null
        if ($LASTEXITCODE -eq 0) {
            return "podman"
        }
    } catch {
        Write-Verbose "podman info probe failed: $_"
    }

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
        git show-ref --verify --quiet "refs/heads/$BranchName" 2> $null
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
        $commits = git log "$BaseBranch..$CompareBranch" --oneline 2> $null
        return $commits
    } finally {
        Pop-Location
    }
}

function Remove-GitBranch {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    [OutputType([bool])]
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
            git branch $flag $BranchName 2> $null | Out-Null
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
        git branch -m $OldName $NewName 2> $null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
}

function New-GitBranch {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
    [OutputType([bool])]
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
            git branch $BranchName $StartPoint 2> $null | Out-Null
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
    $branch = git branch --show-current 2> $null
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
            $null = & $runtime info 2> $null
            if ($LASTEXITCODE -eq 0) {
                $script:ContainerCli = $runtime
                return $true
            }
        } catch {
            Write-Verbose "Runtime '$runtime' info check failed: $_"
        }
    }

    Write-AgentMessage -Message "⚠️  Container runtime not running. Checking installation..." -Color Yellow

    # Try docker first
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    $podmanCmd = Get-Command podman -ErrorAction SilentlyContinue

    if (-not $dockerCmd -and -not $podmanCmd) {
        Write-AgentMessage -Message "❌ No container runtime found. Please install one:" -Color Red
        Write-AgentMessage -Message "   Docker: https://www.docker.com/products/docker-desktop" -Color Cyan
        Write-AgentMessage -Message "   Podman: https://podman.io/getting-started/installation" -Color Cyan
        Write-AgentMessage -Message "" -Color Red
        Write-AgentMessage -Message "   For Windows: Download Docker Desktop or Podman Desktop" -Color Cyan
        Write-AgentMessage -Message "   For Mac: Download Docker Desktop or brew install podman" -Color Cyan
        Write-AgentMessage -Message "   For Linux: Use your package manager" -Color Cyan
        return $false
    }

    # If podman is available and docker is not (or not running)
    if ($podmanCmd -and (-not $dockerCmd -or $runtime -eq "podman")) {
        Write-AgentMessage -Message "ℹ️  Using Podman as container runtime" -Color Cyan

        try {
            $null = podman info 2> $null
            if ($LASTEXITCODE -eq 0) {
                $script:ContainerCli = "podman"
                return $true
            }
        } catch {
            Write-Verbose "Podman info check failed: $_"
        }

        Write-AgentMessage -Message "❌ Podman is installed but not working properly" -Color Red
        Write-AgentMessage -Message "   Try: podman machine init && podman machine start" -Color Cyan
        return $false
    }

    # Docker is installed but not running
    Write-AgentMessage -Message "Docker is installed but not running." -Color Yellow

    # On Windows, try to start Docker Desktop
    if ($IsWindows -or $env:OS -match 'Windows') {
        Write-AgentMessage -Message "Attempting to start Docker Desktop..." -Color Cyan

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
            Write-AgentMessage -Message "Starting Docker Desktop from: $dockerDesktop" -Color Gray
            Start-Process -FilePath $dockerDesktop -WindowStyle Hidden

            # Wait for Docker to start (max 60 seconds)
            Write-AgentMessage -Message "Waiting for Docker to start (max 60 seconds)..." -Color Cyan
            $maxWait = 60
            $waited = 0

            while ($waited -lt $maxWait) {
                Start-Sleep -Seconds 2
                $waited += 2

                try {
                    $null = docker info 2> $null
                    if ($LASTEXITCODE -eq 0) {
                        Write-AgentMessage -Message "✅ Docker started successfully!" -Color Green
                        $script:ContainerCli = "docker"
                        return $true
                    }
                } catch {
                    Write-Verbose "Docker info retry failed: $_"
                }

                Write-AgentMessage -Message "  Still waiting... ($waited/$maxWait seconds)" -Color Gray
            }

            Write-AgentMessage -Message "❌ Docker failed to start within $maxWait seconds." -Color Red
            Write-AgentMessage -Message "   Please start Docker Desktop manually and try again." -Color Yellow
            return $false
        } else {
            Write-AgentMessage -Message "❌ Could not find Docker Desktop executable." -Color Red
            Write-AgentMessage -Message "   Please start Docker Desktop manually." -Color Yellow
            return $false
        }
    } else {
        # On Linux/Mac, provide guidance
        Write-AgentMessage -Message "❌ Please start Docker manually:" -Color Red
        Write-AgentMessage -Message "" -Color Red
        Write-AgentMessage -Message "   On Linux: sudo systemctl start docker" -Color Cyan
        Write-AgentMessage -Message "   Or: sudo service docker start" -Color Cyan
        Write-AgentMessage -Message "   On Mac: Open Docker Desktop application" -Color Cyan
        return $false
    }
}

function Get-PythonRunnerImage {
    if ($env:CODING_AGENTS_PYTHON_IMAGE) {
        return $env:CODING_AGENTS_PYTHON_IMAGE
    }
    return "python:3.11-slim"
}

function Invoke-PythonTool {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter()]
        [string[]]$MountPaths,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ScriptArgs
    )

    if (-not (Test-DockerRunning)) {
        return $false
    }

    $repoRoot = if ($env:CODING_AGENTS_REPO_ROOT) { $env:CODING_AGENTS_REPO_ROOT } else { $script:RepoRootDefault }
    if (-not (Test-Path $repoRoot)) {
        Write-Error "Repo root '$repoRoot' not found for python runner"
        return $false
    }

    $cli = Get-ContainerCli
    $image = Get-PythonRunnerImage
    $containerArgs = @("run", "--rm", "-w", $repoRoot, "-e", "PYTHONUNBUFFERED=1")

    if ($IsLinux) {
        try {
            $uid = & id -u 2> $null
            $gid = & id -g 2> $null
            if ($uid -and $gid) {
                $containerArgs += "--user"
                $containerArgs += "${uid}:${gid}"
            }
        } catch {
            Write-Verbose "Unable to determine host UID/GID for helper runner: $_"
        }
    }

    $tzValue = if ($env:TZ) { $env:TZ } else { "UTC" }
    $containerArgs += "-e"
    $containerArgs += "TZ=$tzValue"
    $containerArgs += "--pids-limit"
    $containerArgs += $script:HelperPidLimit
    $containerArgs += "--security-opt"
    $containerArgs += "no-new-privileges"
    $containerArgs += "--cap-drop"
    $containerArgs += "ALL"
    if ($script:HelperMemory) {
        $containerArgs += "--memory"
        $containerArgs += $script:HelperMemory
    }

    $helperNetwork = if ($env:CODING_AGENTS_HELPER_NETWORK_POLICY) { $env:CODING_AGENTS_HELPER_NETWORK_POLICY } else { $script:HelperNetworkPolicy }
    switch ($helperNetwork.ToLowerInvariant()) {
        "loopback" { $containerArgs += "--network"; $containerArgs += "none" }
        "none" { $containerArgs += "--network"; $containerArgs += "none" }
        "host" { $containerArgs += "--network"; $containerArgs += "host" }
        "bridge" { $containerArgs += "--network"; $containerArgs += "bridge" }
        Default { $containerArgs += "--network"; $containerArgs += $helperNetwork }
    }

    $containerArgs += "--tmpfs"
    $containerArgs += "/tmp:rw,nosuid,nodev,noexec,size=64m"
    $containerArgs += "--tmpfs"
    $containerArgs += "/var/tmp:rw,nosuid,nodev,noexec,size=32m"

    if ($env:CODING_AGENTS_DISABLE_HELPER_SECCOMP -ne "1") {
        try {
            $seccompProfile = Get-SeccompProfilePath -RepoRoot $repoRoot
            if ($seccompProfile) {
                $containerArgs += "--security-opt"
                $containerArgs += "seccomp=$seccompProfile"
            }
        } catch {
            Write-Verbose "Failed to resolve helper seccomp profile: $_"
        }
    }

    foreach ($entry in [System.Environment]::GetEnvironmentVariables().GetEnumerator()) {
        if ($entry.Key -like "CODING_AGENTS_*") {
            $containerArgs += "-e"
            $containerArgs += ("{0}={1}" -f $entry.Key, $entry.Value)
        }
    }

    $mounts = New-Object System.Collections.Generic.List[string]
    $mounts.Add($repoRoot) | Out-Null
    if ($env:HOME) { $mounts.Add($env:HOME) | Out-Null }
    if ($MountPaths) {
        foreach ($mp in $MountPaths) {
            if (-not [string]::IsNullOrWhiteSpace($mp)) {
                $mounts.Add($mp) | Out-Null
            }
        }
    }

    $seen = @{}
    foreach ($mount in $mounts) {
        if ([string]::IsNullOrWhiteSpace($mount)) { continue }
        if (-not (Test-Path $mount)) {
            try { New-Item -ItemType Directory -Path $mount -Force | Out-Null } catch {
                Write-Verbose "Unable to create mount path '$mount': $_"
            }
        }
        if ($seen.ContainsKey($mount)) { continue }
        $seen[$mount] = $true
        $containerArgs += "--mount"
        $containerArgs += "type=bind,src=$mount,dst=$mount"
    }

    $containerArgs += $image
    $containerArgs += "python3"
    $containerArgs += $ScriptPath
    if ($ScriptArgs) {
        $containerArgs += $ScriptArgs
    }

    & $cli @containerArgs
    return ($LASTEXITCODE -eq 0)
}

function Get-ContainerLabel {
    param(
        [string]$ContainerName,
        [string]$LabelKey
    )

    if ([string]::IsNullOrWhiteSpace($ContainerName) -or [string]::IsNullOrWhiteSpace($LabelKey)) {
        return $null
    }

    try {
        $format = "{{ index .Config.Labels \"$LabelKey\" }}"
        $value = Invoke-ContainerCli -CliArgs @('inspect', '-f', $format, $ContainerName) 2> $null
        if ($value -and $value -eq '<no value>') {
            return $null
        }
        return $value
    } catch {
        return $null
    }
}

function Copy-AgentDataExports {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [Parameter(Mandatory = $true)][string]$AgentName,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    if ([string]::IsNullOrWhiteSpace($AgentName)) {
        return $false
    }

    if (-not (Test-Path $DestinationRoot)) {
        New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    }

    $containerPath = "/run/agent-data-export/$AgentName"
    $cli = Get-ContainerCli
    $output = & $cli cp "$ContainerName:$containerPath" $DestinationRoot 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($output -match 'No such' -or $output -match 'not found') {
            return $false
        }
        Write-AgentMessage -Message "⚠️  Failed to copy agent data export for $AgentName: $output" -Color Yellow
        return $false
    }

    return $true
}

function Merge-AgentDataExports {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$AgentName,
        [Parameter(Mandatory = $true)][string]$StagedDir,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$HomeDir
    )

    if (-not (Test-Path $StagedDir -PathType Container)) {
        return $false
    }

    $scriptPath = Join-Path $RepoRoot "scripts/utils/package-agent-data.py"
    if (-not (Test-Path $scriptPath -PathType Leaf)) {
        return $false
    }

    $manifests = Get-ChildItem -LiteralPath $StagedDir -Filter *.manifest.json -File -ErrorAction SilentlyContinue
    if (-not $manifests) {
        return $false
    }

    $merged = $false
    foreach ($manifest in $manifests) {
        $tarName = ($manifest.Name -replace '\.manifest\.json$', '') + '.tar'
        $tarPath = Join-Path $manifest.DirectoryName $tarName
        if (-not (Test-Path $tarPath -PathType Leaf)) {
            continue
        }

        $args = @('--mode', 'merge', '--agent', $AgentName, '--manifest', $manifest.FullName, '--tar', $tarPath, '--target-home', $HomeDir)
        $result = Invoke-PythonTool -ScriptPath $scriptPath -MountPaths @($StagedDir, $HomeDir) -ScriptArgs $args
        if ($result) {
            $merged = $true
            Remove-Item -LiteralPath $manifest.FullName -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tarPath -Force -ErrorAction SilentlyContinue
        } else {
            Write-AgentMessage -Message "⚠️  Failed to merge data export manifest $($manifest.Name)" -Color Yellow
        }
    }

    if ($merged) {
        Write-AgentMessage -Message "📥 Merged $AgentName data export into host profile" -Color Cyan
        return $true
    }

    return $false
}

function Process-AgentDataExports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [Parameter()][string]$RepoRoot,
        [Parameter()][string]$HomeDir,
        [Parameter()][string]$StagingRoot
    )

    if ([string]::IsNullOrWhiteSpace($ContainerName)) { return }

    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = if ($env:CODING_AGENTS_REPO_ROOT) { $env:CODING_AGENTS_REPO_ROOT } else { $script:RepoRootDefault }
    }

    if ([string]::IsNullOrWhiteSpace($HomeDir)) {
        $HomeDir = $HOME
    }

    if (-not (Test-Path $RepoRoot)) { return }
    if (-not (Test-Path $HomeDir)) { return }

    $agentName = Get-ContainerLabel -ContainerName $ContainerName -LabelKey 'coding-agents.agent'
    if ([string]::IsNullOrWhiteSpace($agentName)) {
        return
    }

    $cleanup = $false
    if ([string]::IsNullOrWhiteSpace($StagingRoot)) {
        $StagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-export-" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $StagingRoot -Force | Out-Null
        $cleanup = $true
    }

    try {
        if (Copy-AgentDataExports -ContainerName $ContainerName -AgentName $agentName -DestinationRoot $StagingRoot) {
            $stagedPath = Join-Path $StagingRoot $agentName
            if (Test-Path $stagedPath) {
                Merge-AgentDataExports -AgentName $agentName -StagedDir $stagedPath -RepoRoot $RepoRoot -HomeDir $HomeDir | Out-Null
                Remove-Item -LiteralPath $stagedPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } finally {
        if ($cleanup -and (Test-Path $StagingRoot)) {
            Remove-Item -LiteralPath $StagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
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

    $normalized = $Agent.ToLowerInvariant()
    switch ($normalized) {
        'base' {
            $registryImage = 'ghcr.io/novotnyllc/coding-agents-base:latest'
            $localImage = 'coding-agents-base:local'
        }
        'all' {
            $registryImage = 'ghcr.io/novotnyllc/coding-agents:latest'
            $localImage = 'coding-agents:local'
        }
        'all-agents' {
            $registryImage = 'ghcr.io/novotnyllc/coding-agents:latest'
            $localImage = 'coding-agents:local'
        }
        'proxy' {
            $registryImage = 'ghcr.io/novotnyllc/coding-agents-proxy:latest'
            $localImage = 'coding-agents-proxy:local'
        }
        default {
            $registryImage = "ghcr.io/novotnyllc/coding-agents-${Agent}:latest"
            $localImage = "coding-agents-${Agent}:local"
        }
    }

    Write-AgentMessage -Message "📦 Checking for image updates ($Agent)..." -Color Cyan

    # Try to pull with retries
    $attempt = 0
    $pulled = $false

    while ($attempt -lt $MaxRetries -and -not $pulled) {
        $attempt++
        try {
            if ($attempt -gt 1) {
                Write-AgentMessage -Message "  Retry attempt $attempt of $MaxRetries..." -Color Yellow
            }
            Invoke-ContainerCli -CliArgs @('pull', '--quiet', $registryImage) 2> $null | Out-Null
            Invoke-ContainerCli -CliArgs @('tag', $registryImage, $localImage) 2> $null | Out-Null
            $pulled = $true
        } catch {
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    if (-not $pulled) {
        Write-AgentMessage -Message "  ⚠️  Warning: Could not pull latest image, using cached version" -Color Yellow
    }
}

function Test-ContainerExists {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Exists is semantically correct for testing existence')]
    param([string]$ContainerName)

    $existing = Invoke-ContainerCli -CliArgs @('ps', '-a', '--filter', "name=^${ContainerName}$", '--format', '{{.Names}}') 2> $null
    return ($existing -eq $ContainerName)
}

function Get-ContainerStatus {
    param([string]$ContainerName)
    $status = Invoke-ContainerCli -CliArgs @('inspect', '-f', '{{.State.Status}}', $ContainerName) 2> $null
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
        Write-AgentMessage -Message "⏭️  Skipping git push (--no-push specified)" -Color Yellow
        return
    }

    Write-AgentMessage -Message "💾 Pushing changes to local remote..." -Color Cyan

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
        $pushScript | & $cli exec -i $ContainerName bash 2> $null
        if ($LASTEXITCODE -ne 0) {
            throw "Push failed"
        }
    } catch {
        Write-AgentMessage -Message "⚠️  Could not push changes" -Color Yellow
    }
}

function Get-AgentContainers {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Returns multiple containers - plural is correct')]
    param()
    $listArgs = @(
        'ps',
        '-a',
        '--filter', 'label=coding-agents.type=agent',
        '--format', 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.CreatedAt}}'
    )
    Invoke-ContainerCli -CliArgs $listArgs
}

function Get-ProxyContainer {
    param([string]$AgentContainer)
    Invoke-ContainerCli -CliArgs @('inspect', '-f', '{{ index .Config.Labels "coding-agents.proxy-container" }}', $AgentContainer) 2> $null
}

function Get-ProxyNetwork {
    param([string]$AgentContainer)
    Invoke-ContainerCli -CliArgs @('inspect', '-f', '{{ index .Config.Labels "coding-agents.proxy-network" }}', $AgentContainer) 2> $null
}

function Remove-ContainerWithSidecars {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    [OutputType([bool])]
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
        Write-AgentMessage -Message "❌ Container '$ContainerName' does not exist" -Color Red
        return $false
    }

    # Get container labels to find repo and branch info
    $agentBranch = Invoke-ContainerCli -CliArgs @('inspect', '-f', '{{ index .Config.Labels "coding-agents.branch" }}', $ContainerName) 2> $null
    $repoPath = Invoke-ContainerCli -CliArgs @('inspect', '-f', '{{ index .Config.Labels "coding-agents.repo-path" }}', $ContainerName) 2> $null
    $localRemotePath = Invoke-ContainerCli -CliArgs @('inspect', '-f', '{{ index .Config.Labels "coding-agents.local-remote" }}', $ContainerName) 2> $null

    $containerStatus = Get-ContainerStatus $ContainerName

    # Push changes first while container is running
    if ($containerStatus -eq "running") {
        Push-ToLocal -ContainerName $ContainerName -SkipPush:$SkipPush
        Write-AgentMessage -Message "⏹️  Stopping container to finalize exports..." -Color Cyan
        try {
            Invoke-ContainerCli -CliArgs @('stop', $ContainerName) 2> $null | Out-Null
        } catch {
            Write-AgentMessage -Message "⚠️  Failed to stop container gracefully; exports may be incomplete" -Color Yellow
        }
        $containerStatus = Get-ContainerStatus $ContainerName
    }

    $repoRoot = if ($env:CODING_AGENTS_REPO_ROOT) { $env:CODING_AGENTS_REPO_ROOT } else { $script:RepoRootDefault }
    $homeDir = if ($HOME) { $HOME } else { [Environment]::GetFolderPath('UserProfile') }
    Process-AgentDataExports -ContainerName $ContainerName -RepoRoot $repoRoot -HomeDir $homeDir

    # Get associated resources
    $proxyContainer = Get-ProxyContainer $ContainerName
    $proxyNetwork = Get-ProxyNetwork $ContainerName

    # Remove main container
    Write-AgentMessage -Message "🗑️  Removing container: $ContainerName" -Color Cyan
    Invoke-ContainerCli -CliArgs @('rm', '-f', $ContainerName) 2> $null | Out-Null

    # Remove proxy if exists
    if ($proxyContainer -and (Test-ContainerExists $proxyContainer)) {
        Write-AgentMessage -Message "🗑️  Removing proxy: $proxyContainer" -Color Cyan
        Invoke-ContainerCli -CliArgs @('rm', '-f', $proxyContainer) 2> $null | Out-Null
    }

    # Remove network if exists and no containers attached
    if ($proxyNetwork) {
        $attached = Invoke-ContainerCli -CliArgs @('network', 'inspect', '-f', '{{range .Containers}}{{.Name}} {{end}}', $proxyNetwork) 2> $null
        if (-not $attached) {
            Write-AgentMessage -Message "🗑️  Removing network: $proxyNetwork" -Color Cyan
            Invoke-ContainerCli -CliArgs @('network', 'rm', $proxyNetwork) 2> $null | Out-Null
        }
    }

    if ($agentBranch -and $repoPath -and (Test-Path $repoPath) -and $localRemotePath) {
        Write-AgentMessage -Message ""
        Write-AgentMessage -Message "🔄 Syncing agent branch back to host repository..." -Color Cyan
        Sync-LocalRemoteToHost -RepoPath $repoPath -LocalRemotePath $localRemotePath -AgentBranch $agentBranch
    }

    # Clean up agent branch in host repo if applicable
    if (-not $KeepBranch -and $agentBranch -and $repoPath -and (Test-Path $repoPath)) {
        Write-AgentMessage -Message ""
        Write-AgentMessage -Message "🌿 Cleaning up agent branch: $agentBranch" -Color Cyan

        if (Test-BranchExists -RepoPath $repoPath -BranchName $agentBranch) {
            # Check if branch has unpushed work
            Push-Location $repoPath
            try {
                $currentBranch = git branch --show-current 2> $null
                $unmergedCommits = Get-UnmergedCommits -RepoPath $repoPath -BaseBranch $currentBranch -CompareBranch $agentBranch

                if ($unmergedCommits) {
                    Write-AgentMessage -Message "   ⚠️  Branch has unmerged commits - keeping branch" -Color Yellow
                    Write-AgentMessage -Message "   Manually merge or delete: git branch -D $agentBranch" -Color Gray
                } else {
                    if (Remove-GitBranch -RepoPath $repoPath -BranchName $agentBranch -Force) {
                        Write-AgentMessage -Message "   ✅ Agent branch removed" -Color Green
                    } else {
                        Write-AgentMessage -Message "   ⚠️  Could not remove agent branch" -Color Yellow
                    }
                }
            } finally {
                Pop-Location
            }
        }
    }

    Write-AgentMessage -Message ""
    Write-AgentMessage -Message "✅ Cleanup complete" -Color Green
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
        Write-AgentMessage -Message "❌ Error: Invalid proxy container name: $ProxyContainer" -Color Red
        throw "Invalid proxy container name"
    }

    if ([string]::IsNullOrWhiteSpace($SquidAllowedDomains)) {
        Write-AgentMessage -Message "⚠️  Warning: No allowed domains specified for proxy" -Color Yellow
        $SquidAllowedDomains = "*.github.com"
    }

    # Create network if needed
    $networkExists = Invoke-ContainerCli -CliArgs @('network', 'inspect', $NetworkName) 2> $null
    if (-not $networkExists) {
        Invoke-ContainerCli -CliArgs @('network', 'create', $NetworkName) | Out-Null
    }

    # Check if proxy exists
    if (Test-ContainerExists $ProxyContainer) {
        $state = Get-ContainerStatus $ProxyContainer
        if ($state -ne "running") {
            Invoke-ContainerCli -CliArgs @('start', $ProxyContainer) | Out-Null
        }
    } else {
        # Create new proxy
        $proxyArgs = @(
            'run', '-d',
            '--name', $ProxyContainer,
            '--hostname', $ProxyContainer,
            '--network', $NetworkName,
            '--restart', 'unless-stopped',
            '-e', "SQUID_ALLOWED_DOMAINS=$SquidAllowedDomains",
            '--label', "coding-agents.proxy-of=$AgentContainer",
            '--label', "coding-agents.proxy-image=$ProxyImage",
            $ProxyImage
        )
        Invoke-ContainerCli -CliArgs $proxyArgs | Out-Null
    }
}

function New-RepoSetupScript {
    [CmdletBinding()]
    [OutputType([string])]
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

if [ "$SOURCE_TYPE" = "prompt" ]; then
    echo "🆕 Prompt session requested without repository: leaving workspace empty"
    exit 0
elif [ "$SOURCE_TYPE" = "url" ]; then
    echo "🌐 Cloning repository from $GIT_URL..."
    git clone "$GIT_URL" "$TARGET_DIR"
else
    echo "📁 Copying repository from host..."
    cp -a /tmp/source-repo/. "$TARGET_DIR/"
fi

cd "$TARGET_DIR"

# Configure local remote when copying from the host
if [ "$SOURCE_TYPE" = "local" ]; then
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

# Remove origin remote to keep the container isolated from upstream
if git remote get-url origin >/dev/null 2>&1; then
    git remote remove origin
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

    git --git-dir=$LocalRemotePath rev-parse --verify --quiet "refs/heads/$AgentBranch" 2> $null | Out-Null
    if (-not $?) {
        return
    }

    Push-Location $RepoPath
    try {
        $tempRef = "refs/coding-agents-sync/$AgentBranch" -replace ' ', '-'
        git fetch $LocalRemotePath "${AgentBranch}:$tempRef" 2> $null | Out-Null
        if (-not $?) {
            Write-Warning "Failed to fetch agent branch from secure remote"
            return
        }

        $fetchedSha = git rev-parse $tempRef 2> $null
        if (-not $?) { return }

        $currentBranch = git branch --show-current 2> $null
        $hostHasBranch = git show-ref --verify --quiet "refs/heads/$AgentBranch" 2> $null
        $hostHasBranch = $?

        if ($hostHasBranch) {
            if ($currentBranch -eq $AgentBranch) {
                $worktreeState = git status --porcelain 2> $null
                if ($worktreeState) {
                    Write-Warning "Working tree dirty on $AgentBranch; skipped auto-sync"
                } else {
                    git merge --ff-only $tempRef 2> $null | Out-Null
                    if ($?) {
                        Write-AgentMessage -Message "✅ Host branch '$AgentBranch' fast-forwarded from secure remote"
                    } else {
                        Write-Warning "Unable to fast-forward '$AgentBranch' (merge required)"
                    }
                }
            } else {
                git update-ref "refs/heads/$AgentBranch" $fetchedSha 2> $null | Out-Null
                if ($?) {
                    Write-AgentMessage -Message "✅ Host branch '$AgentBranch' updated from secure remote"
                } else {
                    Write-Warning "Failed to update branch '$AgentBranch'"
                }
            }
        } else {
            git branch $AgentBranch $tempRef 2> $null | Out-Null
            if ($?) {
                Write-AgentMessage -Message "✅ Created branch '$AgentBranch' from secure remote"
            } else {
                Write-Warning "Failed to create branch '$AgentBranch'"
            }
        }
    }
    finally {
        git update-ref -d $tempRef 2> $null | Out-Null
        Pop-Location
    }
}
