# Code Style and Conventions

## Core Principles

### 1. Script Parity (CRITICAL)
- **All functionality must exist in both PowerShell and bash**
- Equivalent features, equivalent error handling, equivalent behavior
- Test coverage must be equal across both languages

### 2. Test Coverage
- All functions must have comprehensive unit tests
- Both bash and PowerShell test files must pass identically
- Integration tests validate end-to-end system behavior

### 3. Code Quality
- PowerShell must pass PSScriptAnalyzer with **zero warnings/errors** (PSGallery settings)
- Bash scripts must use `set -euo pipefail`
- Complete error handling for all external commands

### 4. Documentation
- Keep CONTRIBUTING.md and docs/ updated with workflow changes
- Clear, actionable error messages
- No hardcoded secrets or credentials

## PowerShell Conventions

### Function Names
- Use approved verbs: `Get-`, `Set-`, `New-`, `Remove-`, `Test-`, `Initialize-`
- Use **singular nouns** for cmdlet names (except when semantically plural)
- Example: `Test-ContainerExists`, `Get-RepoName`, `Remove-Agent`

### Function Structure
```powershell
function Verb-Noun {
    [CmdletBinding(SupportsShouldProcess=$true)]  # For state-changing functions
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('RuleName', '', Justification='reason')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ParameterName,
        
        [switch]$FlagParameter
    )
    
    # Function body with proper error handling
    try {
        # Implementation
    }
    catch {
        Write-Error "Clear error message"
        exit 1
    }
}
```

### Parameter Validation
- Use `[Parameter(Mandatory=$true)]` for required parameters
- Use `[switch]` for boolean flags
- Validate inputs before processing

### Error Handling
- Use try/catch blocks
- Provide descriptive error messages
- Exit with code 1 on failure

## Bash Conventions

### Function Names
- Use `snake_case` for function names
- Clear, descriptive names
- Example: `test_container_exists`, `get_repo_name`, `remove_agent`

### Script Header
```bash
#!/usr/bin/env bash
set -euo pipefail  # Exit on error, undefined variables, pipe failures
```

### Error Handling
```bash
if ! command_that_might_fail; then
    echo "❌ Error: Clear description of what went wrong" >&2
    exit 1
fi

# Or with || operator
command || {
    echo "❌ Error message" >&2
    exit 1
}
```

## Naming Conventions

### Container Names
- Pattern: `{agent}-{repo}-{branch}`
- Branch names sanitized (slashes → dashes, lowercase)
- Examples: `copilot-myapp-main`, `codex-website-feature-auth`

### Docker Labels
- All agent containers must have:
  - `containai.type=agent`
  - `containai.agent={copilot|codex|claude}`
  - `containai.repo={repo-name}`
  - `containai.branch={branch-name}`
  - `containai.repo-path={absolute-path}`

### Git Branches
- Agent branches: `{agent}/{base-branch}`
- Examples: `copilot/main`, `codex/feature-auth`
- Archived branches: `{agent}/{branch}-archived-{timestamp}`

### Test Isolation
- Test containers: `label=containai.test=true`
- Test sessions: `label=containai.test-session={PID}`
- Test repos: `/tmp/test-containai-repo-{PID}` (bash) or `$env:TEMP\test-containai-{PID}` (PowerShell)

## File Naming

### Scripts
- Bash: lowercase with hyphens (`launch-agent`, `common-functions.sh`)
- PowerShell: lowercase with hyphens, `.ps1` extension (`launch-agent.ps1`, `common-functions.ps1`)
- Quick launchers: `run-{agent}` (bash) and `run-{agent}.ps1` (PowerShell)

### Documentation
- Markdown: UPPERCASE.md for repo-level docs (`README.md`, `CONTRIBUTING.md`, `AGENTS.md`)
- Docs folder: CamelCase.md (`Architecture.md`, `BuildGuide.md`)

## Comments and Documentation

### PowerShell
- Use comment-based help for functions:
```powershell
<#
.SYNOPSIS
    Brief description
.DESCRIPTION
    Longer description
.PARAMETER Name
    Parameter description
#>
```

### Bash
- Use comments above functions:
```bash
# Brief description of function
# Arguments:
#   $1 - First parameter description
#   $2 - Second parameter description
# Returns:
#   0 on success, 1 on failure
function_name() {
    # Implementation
}
```

## Best Practices

### Security
- **No secrets in code**: Use environment variables or runtime mounts
- **No secrets in images**: Bake nothing sensitive into containers
- **Read-only mounts**: Use `:ro` for host-mounted authentication
- **Non-root user**: Run as `agentuser` (UID 1000) in containers

### Error Messages
- Start with emoji: ❌ for errors, ⚠️ for warnings, ✅ for success
- Be specific: Tell users what went wrong
- Be actionable: Tell users how to fix it
- Example: `❌ Error: Docker is not running. Start Docker Desktop and try again.`

### Git Operations
- Always check if in git repository before operations
- Use `-q` flag for quiet operations in automation
- Configure user.name and user.email in test repos
- Set `remote.pushDefault local` for safety
