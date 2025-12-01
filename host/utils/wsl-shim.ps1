<#
.SYNOPSIS
    Shared helper that proxies ContainAI PowerShell entrypoints into WSL.
.DESCRIPTION
    Validates WSL availability, translates Windows paths to Linux paths, and
    executes the requested Bash script with the caller's working directory.
#>
$ErrorActionPreference = "Stop"

# Detect Linux environment (use different name to avoid conflict with automatic $IsLinux)
$script:RunningOnLinux = $IsLinux -or ($PSVersionTable.PSVersion.Major -ge 6 -and $PSVersionTable.OS -match 'Linux')

function Get-WslExecutablePath {
    if ($script:RunningOnLinux) { return $null }
    $candidate = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($null -ne $candidate) {
        return $candidate.Source
    }
    # Return null instead of throwing - caller will check WslDistributionAvailable
    return $null
}

function Test-WslDistributionAvailable {
    if ($script:RunningOnLinux) { return $true }
    if ($null -eq $script:WslExePath) { return $false }
    
    # Check if any WSL distribution is installed
    $output = & $script:WslExePath --list --quiet 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
        return $false
    }
    return $true
}

$script:WslExePath = Get-WslExecutablePath
$script:WslDistributionAvailable = Test-WslDistributionAvailable
$script:RepoRootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).ProviderPath

function Skip-IfNoWsl {
    <#
    .SYNOPSIS
        Checks if WSL is available and skips the calling test if not.
    .DESCRIPTION
        For use in Pester tests to gracefully skip when WSL isn't configured.
    #>
    if (-not $script:RunningOnLinux -and -not $script:WslDistributionAvailable) {
        Set-ItResult -Skipped -Because "No WSL distribution is installed"
    }
}

function Convert-ToWslPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    
    if ($script:RunningOnLinux) {
        return $resolved
    }

    if (-not $script:WslDistributionAvailable) {
        throw "No WSL distribution is installed. Please run 'wsl --install' and try again."
    }

    $output = & $script:WslExePath wslpath -u "$resolved" 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
        throw "Could not translate path '$resolved' to a WSL path. Output: $output"
    }
    return $output.Trim()
}

function Invoke-ContainAIWslScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptRelativePath,
        [string[]]$Arguments
    )

    $scriptPath = Join-Path $script:RepoRootPath $ScriptRelativePath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Unable to locate Bash script '$ScriptRelativePath' under repo root."
    }

    if ($script:RunningOnLinux) {
        # On Linux, execute directly with bash
        $bashArgs = @($scriptPath)
        if ($Arguments) {
            $bashArgs += $Arguments
        }
        & bash $bashArgs
        return $LASTEXITCODE
    }

    $workingDir = (Get-Location).ProviderPath
    $wslScriptPath = Convert-ToWslPath -Path $scriptPath
    $wslWorkingDir = Convert-ToWslPath -Path $workingDir

    $wslArgs = @("--cd", $wslWorkingDir, "--", $wslScriptPath)
    if ($Arguments) {
        $wslArgs += $Arguments
    }

    & $script:WslExePath @wslArgs
    return $LASTEXITCODE
}
