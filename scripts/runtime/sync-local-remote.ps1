#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory=$true)][string]$BareRepo,
    [Parameter(Mandatory=$true)][string]$HostRepo,
    [Parameter(Mandatory=$true)][string]$Branch,
    [string]$ContainerName,
    [int]$IntervalSeconds = $env:CODING_AGENTS_LOCAL_SYNC_INTERVAL
)

if (-not $IntervalSeconds -or $IntervalSeconds -le 0) {
    $IntervalSeconds = 5
}

if (-not (Test-Path $BareRepo)) {
    Write-Error "sync-local-remote.ps1: bare repo not found at $BareRepo"
    exit 1
}

if (-not (Test-Path (Join-Path $HostRepo '.git'))) {
    Write-Error "sync-local-remote.ps1: host repo not found at $HostRepo"
    exit 1
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $projectRoot 'scripts/utils/common-functions.ps1')

$lockFile = Join-Path $BareRepo '.coding-agents-sync.lock'
$lastSha = ""

function Write-DebugLog {
    param([string]$Message)
    if ($env:CODING_AGENTS_LOCAL_SYNC_DEBUG -eq '1') {
        $timestamp = (Get-Date).ToUniversalTime().ToString('o')
        Write-Host "[$timestamp] $Message"
    }
}

while ($true) {
    if (-not (Test-Path $BareRepo)) {
        Write-DebugLog "Bare repo removed; stopping"
        break
    }

    if ($ContainerName -and -not (Test-ContainerExists $ContainerName)) {
        Write-DebugLog "Container $ContainerName missing; stopping"
        break
    }

    $sha = git --git-dir=$BareRepo rev-parse --verify --quiet "refs/heads/$Branch" 2>$null
    if ($LASTEXITCODE -ne 0) {
        $sha = $null
    }

    if ($sha -and $sha -ne $lastSha) {
        $fileStream = New-Object System.IO.FileStream($lockFile, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            Sync-LocalRemoteToHost -RepoPath $HostRepo -LocalRemotePath $BareRepo -AgentBranch $Branch
        } finally {
            $fileStream.Dispose()
        }
        $lastSha = $sha
    }

    Start-Sleep -Seconds $IntervalSeconds
}
