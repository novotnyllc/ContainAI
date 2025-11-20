<#
.SYNOPSIS
    Shared helper that proxies CodingAgents PowerShell entrypoints into WSL.
.DESCRIPTION
    Validates WSL availability, translates Windows paths to Linux paths, and
    executes the requested Bash script with the caller's working directory.
#>
$ErrorActionPreference = "Stop"

function Get-WslExecutablePath {
    $candidate = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($null -ne $candidate) {
        return $candidate.Source
    }
    throw "WSL is not installed. Please run 'wsl --install' and try again."
}

$script:WslExePath = Get-WslExecutablePath
$script:RepoRootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).ProviderPath

function Convert-ToWslPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $output = & $script:WslExePath wslpath -u "$resolved" 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
        throw "Could not translate path '$resolved' to a WSL path. Output: $output"
    }
    return $output.Trim()
}

function Invoke-CodingAgentsWslScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptRelativePath,
        [string[]]$Arguments
    )

    $scriptPath = Join-Path $script:RepoRootPath $ScriptRelativePath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Unable to locate Bash script '$ScriptRelativePath' under repo root."
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
