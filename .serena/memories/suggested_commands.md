# Suggested Commands for CodingAgents

## System (Windows with WSL2)

### File Operations
```powershell
# PowerShell
Get-ChildItem          # List files
Get-Content file.txt   # Read file
Set-Location path      # Change directory
Remove-Item path       # Delete file/folder
```

```bash
# Bash (in WSL)
ls                     # List files
cat file.txt           # Read file
cd path                # Change directory
rm -rf path            # Delete file/folder
```

### Git Operations
```bash
git status             # Check repository status
git branch             # List branches
git checkout -b name   # Create new branch
git add .              # Stage all changes
git commit -m "msg"    # Commit changes
git push local         # Push to local remote (host)
git push origin        # Push to GitHub
```

## Testing

### Unit Tests (Fast - Run after every change)
```bash
# Bash unit tests
./scripts/test/test-launchers.sh
./scripts/test/test-branch-management.sh

# PowerShell unit tests
pwsh scripts/test/test-launchers.ps1
pwsh scripts/test/test-branch-management.ps1
```

### Integration Tests (Slower - Run before PR)
```bash
# Fast mode: Use existing images (~3-5 min)
./scripts/test/integration-test.sh --mode launchers

# Full mode: Build all images (~10-15 min)
./scripts/test/integration-test.sh --mode full

# Debug mode: Preserve resources for inspection
./scripts/test/integration-test.sh --mode full --preserve
```

## Code Quality

### PowerShell Linting
```powershell
# Install PSScriptAnalyzer (one-time)
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser

# Check all PowerShell scripts
Get-ChildItem -Path "scripts" -Filter "*.ps1" -Recurse | 
    ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings PSGallery }

# Should return NO errors or warnings
```

### Bash Linting
```bash
# If shellcheck is installed
shellcheck scripts/**/*.sh
```

## Container Management

### Build Images
```bash
# Build all images
./scripts/build.sh

# PowerShell
pwsh scripts/build.ps1
```

### Launch Agents
```bash
# Quick ephemeral session (auto-removes on exit)
cd ~/my-project
run-copilot           # GitHub Copilot
run-codex             # OpenAI Codex
run-claude            # Anthropic Claude

# PowerShell
run-copilot.ps1
```

```bash
# Persistent container (background, reconnectable)
cd ~/my-project
launch-agent copilot                  # Copilot on current branch
launch-agent codex            # Codex on current branch
launch-agent copilot --branch feature-auth    # Copilot on feature-auth branch

# PowerShell
launch-agent.ps1 -Agent codex -Branch feature-auth
```

### Manage Containers
```bash
# List all running agent containers
list-agents

# Remove agent container (with auto-push)
remove-agent copilot-myproject-main

# Remove without pushing changes
remove-agent codex-myproject-auth --no-push

# Keep the git branch when removing
remove-agent claude-myproject-api --keep-branch

# PowerShell
list-agents.ps1
remove-agent.ps1 copilot-myproject-main
remove-agent.ps1 codex-myproject-auth -NoPush
```

### Docker Operations
```bash
# List all containers (including stopped)
docker ps -a

# List agent containers only
docker ps -a --filter "label=coding-agents.type=agent"

# Remove all test containers
docker ps -aq --filter "label=coding-agents.test=true" | xargs docker rm -f

# Check container logs
docker logs container-name

# Inspect container labels
docker inspect container-name | grep -A 10 Labels

# Clean up Docker resources
docker system prune -a --volumes
```

### Container Runtime Detection
```bash
# Check which container runtime is available
# Scripts automatically detect and prefer Docker, fall back to Podman

# Force specific runtime
export CONTAINER_RUNTIME=podman  # bash
$env:CONTAINER_RUNTIME = "podman"  # PowerShell
```

## Development Workflow

### After Making Code Changes
```bash
# 1. Run unit tests immediately
./scripts/test/test-launchers.sh
pwsh scripts/test/test-launchers.ps1

# 2. If tests pass, test manually
cd ~/test-project
launch-agent copilot --branch test-feature

# 3. Make more changes in container, test, iterate

# 4. Before committing, run all unit tests
./scripts/test/test-launchers.sh
./scripts/test/test-branch-management.sh
pwsh scripts/test/test-launchers.ps1
pwsh scripts/test/test-branch-management.ps1

# 5. Before PR, run integration tests
./scripts/test/integration-test.sh --mode launchers
```

### Debugging Failed Tests
```bash
# Preserve test resources for inspection
./scripts/test/integration-test.sh --mode full --preserve

# Then inspect
docker ps -a --filter "label=coding-agents.test-session=<PID>"
docker logs <container-name>
docker network ls | grep test-coding-agents
ls -la /tmp/test-coding-agents-repo-<PID>

# Manual cleanup after inspection
docker ps -aq --filter "label=coding-agents.test-session=<PID>" | xargs docker rm -f
docker network rm test-coding-agents-net-<PID>
rm -rf /tmp/test-coding-agents-repo-<PID>
```

## Common Utilities

### WSL Path Conversion (Windows)
```powershell
# PowerShell function (from common-functions.ps1)
. scripts/utils/common-functions.ps1
Convert-WindowsPathToWsl "C:\Users\test\project"
# Returns: /mnt/c/Users/test/project
```

### Branch Name Sanitization
```powershell
# PowerShell
ConvertTo-SafeBranchName "feature/auth-module"
# Returns: feature-auth-module
```

```bash
# Bash
sanitize_branch_name "feature/auth-module"
# Returns: feature-auth-module
```

### Repository Name Extraction
```powershell
# PowerShell
Get-RepoName "C:\Users\test\my-project"
# Returns: my-project
```

```bash
# Bash
get_repo_name "/home/user/my-project"
# Returns: my-project
```

## When Task is Completed

See `task_completion_checklist.md` for the complete checklist to run before submitting changes.
