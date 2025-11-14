#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Install coding-agents launchers to PATH
.DESCRIPTION
    Adds the scripts/launchers directory to the user's PATH environment variable.
    On Windows, modifies the User PATH in the registry.
    On Linux/macOS, adds to ~/.bashrc or ~/.zshrc.
.EXAMPLE
    .\scripts\install.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $PSScriptRoot
$LaunchersPath = Join-Path $ScriptRoot "scripts\launchers"

if (-not (Test-Path $LaunchersPath)) {
    Write-Error "Launchers directory not found: $LaunchersPath"
    exit 1
}

function Install-Windows {
    Write-Host "Installing launchers to PATH (Windows)..." -ForegroundColor Cyan
    
    # Validate LaunchersPath
    if (-not (Test-Path $LaunchersPath -PathType Container)) {
        Write-Error "Invalid path: $LaunchersPath is not a directory"
        exit 1
    }
    
    # Validate no malicious characters in path
    if ($LaunchersPath -match '[<>"|?*]') {
        Write-Error "Path contains invalid characters: $LaunchersPath"
        exit 1
    }
    
    # Get current user PATH
    $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    
    # Check if already in PATH
    if ($currentPath -split ';' | Where-Object { $_ -eq $LaunchersPath }) {
        Write-Host "✓ Launchers already in PATH: $LaunchersPath" -ForegroundColor Green
        return
    }
    
    # Add to PATH
    $newPath = if ($currentPath) { "$currentPath;$LaunchersPath" } else { $LaunchersPath }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    
    # Update current session
    $env:PATH += ";$LaunchersPath"
    
    Write-Host "✓ Added to PATH: $LaunchersPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "NOTE: You may need to restart your terminal for the change to take effect." -ForegroundColor Yellow
    Write-Host "      Or run: `$env:PATH += ';$LaunchersPath'" -ForegroundColor Yellow
}

function Install-Unix {
    Write-Host "Installing launchers to PATH (Unix)..." -ForegroundColor Cyan
    
    $shell = $env:SHELL
    $rcFile = if ($shell -match 'zsh') {
        "$env:HOME/.zshrc"
    } else {
        "$env:HOME/.bashrc"
    }
    
    $exportLine = "export PATH=`"${LaunchersPath}:`$`{PATH}`""
    
    # Check if already in rc file
    if (Test-Path $rcFile) {
        $content = Get-Content $rcFile -Raw
        if ($content -match [regex]::Escape($LaunchersPath)) {
            Write-Host "✓ Launchers already in $rcFile" -ForegroundColor Green
            return
        }
    }
    
    # Add to rc file
    Add-Content -Path $rcFile -Value "`n# Coding Agents launchers"
    Add-Content -Path $rcFile -Value $exportLine
    
    # Update current session
    $env:PATH = "${LaunchersPath}:$env:PATH"
    
    Write-Host "✓ Added to $rcFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "NOTE: Restart your terminal or run: source $rcFile" -ForegroundColor Yellow
}

# Detect OS and install
if ($IsWindows -or $PSVersionTable.Platform -eq 'Win32NT' -or !$PSVersionTable.Platform) {
    Install-Windows
} else {
    Install-Unix
}

Write-Host ""
Write-Host "Installation complete! You can now run:" -ForegroundColor Green
Write-Host "  run-copilot, run-codex, run-claude" -ForegroundColor Cyan
Write-Host "  launch-agent, list-agents, remove-agent" -ForegroundColor Cyan
