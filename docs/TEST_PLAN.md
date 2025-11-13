# Test Plan for CodingAgents

Comprehensive step-by-step test procedures to validate all features of the AI Coding Agents container system.

## Test Environment Prerequisites

### Required Software
- [ ] Docker Desktop with WSL2 backend (Windows) or Docker Desktop (Mac/Linux)
- [ ] Git installed and in PATH
- [ ] GitHub CLI (`gh`) installed
- [ ] PowerShell 5.1+ (Windows) or Bash (Linux/Mac)
- [ ] VS Code with Dev Containers extension installed

### Authentication Prerequisites
- [ ] GitHub CLI authenticated: `gh auth login`
- [ ] Git configured:
  ```bash
  git config --global user.name "Your Name"
  git config --global user.email "your@email.com"
  ```
- [ ] (Optional) GitHub Copilot subscription active
- [ ] (Optional) OpenAI Codex access configured at `~/.config/codex/`
- [ ] (Optional) Anthropic Claude access configured at `~/.config/claude/`

### Test Repository Setup
- [ ] Create test repository or use existing: `e:\dev\CodingAgents\test-workspace`
- [ ] Initialize with README.md and sample code files
- [ ] Push to GitHub (for testing GitHub URL cloning)
- [ ] Note GitHub URL for tests: `https://github.com/<user>/<repo>`

---

## Test Suite 1: Building Images Locally

### Test 1.1: Build Base Image
**Objective**: Verify base image builds successfully with all dependencies

**Steps**:
1. Navigate to repository root: `cd e:\dev\CodingAgents`
2. Build base image:
   ```bash
   docker build -f Dockerfile.base -t coding-agents-base:local .
   ```
3. Monitor build output for errors
4. Verify build completes successfully

**Expected Results**:
- [ ] Build completes without errors
- [ ] Image created: `docker images | grep coding-agents-base`
- [ ] Image size approximately 3-4 GB
- [ ] Build time: 10-15 minutes (first build)

**Validation**:
```bash
docker run --rm coding-agents-base:local node --version  # Should show v20.x
docker run --rm coding-agents-base:local python3 --version  # Should show 3.11.x
docker run --rm coding-agents-base:local dotnet --version  # Should show 8.0.x
docker run --rm coding-agents-base:local gh --version  # Should show gh version
```

### Test 1.2: Build All-Agents Image
**Objective**: Verify all-agents image builds on top of base

**Steps**:
1. Build all-agents image:
   ```bash
   docker build -f Dockerfile -t coding-agents:local .
   ```
2. Monitor build output for script copying

**Expected Results**:
- [ ] Build completes without errors
- [ ] Image created: `docker images | grep "coding-agents:local"`
- [ ] Image size approximately +50 MB from base
- [ ] Build time: ~1 minute

**Validation**:
```bash
docker run --rm coding-agents:local ls -la /usr/local/bin/
# Should show: entrypoint.sh, setup-mcp-configs.sh, convert-toml-to-mcp.py
```

### Test 1.3: Build Specialized Agent Images
**Objective**: Build agent-specific images (copilot, codex, claude, proxy)

**Steps**:
1. Build Copilot image:
   ```bash
   docker build -f Dockerfile.copilot -t coding-agents-copilot:local .
   ```
2. Build Codex image:
   ```bash
   docker build -f Dockerfile.codex -t coding-agents-codex:local .
   ```
3. Build Claude image:
   ```bash
   docker build -f Dockerfile.claude -t coding-agents-claude:local .
   ```
4. Build Proxy image:
   ```bash
   docker build -f Dockerfile.proxy -t coding-agents-proxy:local .
   ```

**Expected Results**:
- [ ] All builds complete without errors
- [ ] Four new images created (copilot, codex, claude, proxy)
- [ ] Each image approximately +10 MB from all-agents
- [ ] Build time: ~30 seconds each

**Validation**:
```bash
docker images | grep coding-agents
# Should list: base, all-agents, copilot, codex, claude, proxy
```

### Test 1.4: Use Build Scripts
**Objective**: Verify automated build scripts work correctly

**Steps (Windows)**:
```powershell
.\scripts\build.ps1
```

**Steps (Linux/Mac)**:
```bash
chmod +x scripts/build.sh
./scripts/build.sh
```

**Expected Results**:
- [ ] Script builds all images in correct order
- [ ] All 6 images present after completion
- [ ] No errors during automated build

---

## Test Suite 2: Pulling from GHCR

### Test 2.1: Pull Pre-Built Images
**Objective**: Verify images can be pulled from GitHub Container Registry

**Steps**:
1. Remove local images (if present):
   ```bash
   docker rmi coding-agents-copilot:local
   docker rmi coding-agents-codex:local
   docker rmi coding-agents-claude:local
   ```

2. Pull from GHCR:
   ```bash
   docker pull ghcr.io/novotnyllc/coding-agents-copilot:latest
   docker pull ghcr.io/novotnyllc/coding-agents-codex:latest
   docker pull ghcr.io/novotnyllc/coding-agents-claude:latest
   ```

**Expected Results**:
- [ ] All images pull successfully
- [ ] Downloaded size matches expected (~4 GB per agent image)
- [ ] Images listed: `docker images | grep ghcr.io`

**Validation**:
```bash
docker run --rm ghcr.io/novotnyllc/coding-agents-copilot:latest echo "Success"
# Should print: Success
```

### Test 2.2: Tag GHCR Images as Local
**Objective**: Use GHCR images with launch scripts (expecting :local tag)

**Steps**:
```bash
docker tag ghcr.io/novotnyllc/coding-agents-copilot:latest coding-agents-copilot:local
docker tag ghcr.io/novotnyllc/coding-agents-codex:latest coding-agents-codex:local
docker tag ghcr.io/novotnyllc/coding-agents-claude:latest coding-agents-claude:local
```

**Expected Results**:
- [ ] Local tags created
- [ ] `docker images` shows both GHCR and local tags pointing to same image ID

---

## Test Suite 3: Launching Containers (Network Modes)

### Test 3.1: Launch with Default Network (allow-all)
**Objective**: Verify default bridge network mode works

**Steps (PowerShell)**:
```powershell
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace --agent copilot
```

**Steps (Bash)**:
```bash
./launch-agent ~/test-workspace --agent copilot
```

**Expected Results**:
- [ ] Container created: `copilot-test-workspace`
- [ ] Container running: `docker ps | grep copilot-test-workspace`
- [ ] Network mode is bridge: `docker inspect copilot-test-workspace | grep NetworkMode`
- [ ] Repository copied to `/workspace` inside container

**Validation**:
```bash
docker exec -it copilot-test-workspace bash -c "ls /workspace"
# Should show repository contents

docker exec -it copilot-test-workspace bash -c "curl -I https://www.google.com"
# Should succeed (network access enabled)
```

**Cleanup**:
```bash
docker rm -f copilot-test-workspace
```

### Test 3.2: Launch with Restricted Network Mode
**Objective**: Verify `--network none` isolation works

**Steps**:
```powershell
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace --agent copilot --network-proxy restricted
```

**Expected Results**:
- [ ] Container created with `--network none`
- [ ] Container running: `docker ps | grep copilot-test-workspace`
- [ ] Network mode is none: `docker inspect copilot-test-workspace | grep NetworkMode`

**Validation**:
```bash
docker exec -it copilot-test-workspace bash -c "curl -I https://www.google.com"
# Should FAIL with network unreachable error

docker exec -it copilot-test-workspace bash -c "ls /workspace"
# Should still work (local filesystem access)
```

**Cleanup**:
```bash
docker rm -f copilot-test-workspace
```

### Test 3.3: Launch with Squid Proxy Network Mode
**Objective**: Verify Squid proxy sidecar works with HTTP/HTTPS routing

**Steps**:
```powershell
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace --agent copilot --network-proxy squid
```

**Expected Results**:
- [ ] Proxy container created: `copilot-test-workspace-proxy`
- [ ] Agent container created: `copilot-test-workspace`
- [ ] Custom network created: `copilot-test-workspace-net`
- [ ] Both containers running: `docker ps | grep test-workspace`

**Validation**:
```bash
# Check proxy container is running
docker ps | grep copilot-test-workspace-proxy

# Check custom network exists
docker network ls | grep copilot-test-workspace-net

# Check agent container has proxy configured
docker exec -it copilot-test-workspace bash -c "env | grep -i proxy"
# Should show HTTP_PROXY and HTTPS_PROXY set to http://copilot-test-workspace-proxy:3128

# Test HTTP/HTTPS through proxy
docker exec -it copilot-test-workspace bash -c "curl -I https://www.google.com"
# Should succeed (proxied)

# Check proxy logs
docker logs copilot-test-workspace-proxy
# Should show Squid access logs with requests
```

**Cleanup**:
```bash
docker rm -f copilot-test-workspace
docker rm -f copilot-test-workspace-proxy
docker network rm copilot-test-workspace-net
```

### Test 3.4: Launch Multiple Agents on Same Repository
**Objective**: Verify multiple isolated agents can work on same repo

**Steps**:
```powershell
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace -b feature-auth --agent copilot
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace -b feature-db --agent codex
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace -b feature-ui --agent claude
```

**Expected Results**:
- [ ] Three containers created: `copilot-test-workspace`, `codex-test-workspace`, `claude-test-workspace`
- [ ] All three running simultaneously: `docker ps`
- [ ] Each has own isolated `/workspace`

**Validation**:
```bash
# Check branches in each container
docker exec -it copilot-test-workspace git branch
# Should show: copilot/feature-auth

docker exec -it codex-test-workspace git branch
# Should show: codex/feature-db

docker exec -it claude-test-workspace git branch
# Should show: claude/feature-ui

# Verify workspaces are isolated (create file in one)
docker exec -it copilot-test-workspace touch /workspace/copilot-only.txt
docker exec -it codex-test-workspace ls /workspace/copilot-only.txt
# Should FAIL - file not found (isolation confirmed)
```

**Cleanup**:
```bash
docker rm -f copilot-test-workspace codex-test-workspace claude-test-workspace
```

### Test 3.5: Launch from GitHub URL
**Objective**: Verify container can clone from GitHub URL

**Steps**:
```powershell
.\launch-agent.ps1 https://github.com/<user>/<test-repo> --agent copilot
```

**Expected Results**:
- [ ] Container clones repository from GitHub
- [ ] Repository present at `/workspace`
- [ ] Git remotes configured (origin = GitHub URL)

**Validation**:
```bash
docker exec -it copilot-<test-repo> bash -c "git remote -v"
# Should show origin pointing to GitHub URL

docker exec -it copilot-<test-repo> bash -c "ls /workspace"
# Should show cloned repository contents
```

**Cleanup**:
```bash
docker rm -f copilot-<test-repo>
```

---

## Test Suite 4: VS Code Dev Containers Integration

### Test 4.1: Attach to Running Container
**Objective**: Verify VS Code can attach to agent container

**Prerequisites**:
- [ ] Launch a test container: `.\launch-agent.ps1 . --agent copilot`
- [ ] VS Code installed with Dev Containers extension

**Steps**:
1. Open VS Code
2. Click remote indicator (bottom-left corner)
3. Select "Attach to Running Container..."
4. Choose `copilot-<repo-name>` from list
5. Wait for VS Code to connect

**Expected Results**:
- [ ] VS Code opens new window connected to container
- [ ] Explorer shows `/workspace` contents
- [ ] Terminal opens inside container (prompt shows `agentuser@<container-id>`)
- [ ] Extensions load in container context

**Validation**:
- [ ] Open terminal, run `pwd` → should show `/workspace`
- [ ] Open terminal, run `whoami` → should show `agentuser`
- [ ] Create/edit a file in VS Code → changes visible in container
- [ ] Run `git status` in terminal → works correctly

### Test 4.2: Reattach to Existing Container
**Objective**: Verify can reconnect after VS Code window closes

**Steps**:
1. Close VS Code window (container keeps running)
2. Verify container still running: `docker ps | grep copilot`
3. Reopen VS Code
4. Attach to same container again

**Expected Results**:
- [ ] VS Code reconnects successfully
- [ ] Previous workspace state preserved
- [ ] Files and terminal history intact

### Test 4.3: Container Restart and Reconnect
**Objective**: Verify container can be stopped/started and reconnected

**Steps**:
1. Stop container: `docker stop copilot-<repo>`
2. Start container: `docker start copilot-<repo>`
3. Attach from VS Code

**Expected Results**:
- [ ] Container starts successfully
- [ ] VS Code attaches without issues
- [ ] Workspace contents preserved

**Validation**:
```bash
docker exec -it copilot-<repo> ls /workspace
# Should show all previous files
```

---

## Test Suite 5: Git Workflow (Dual Remotes)

### Test 5.1: Verify Dual Remote Configuration
**Objective**: Confirm both `origin` and `local` remotes configured

**Steps**:
```bash
docker exec -it copilot-test-workspace git remote -v
```

**Expected Results**:
- [ ] `origin` remote points to GitHub URL
- [ ] `local` remote points to host repository path
- [ ] Push default is `local`: `git config remote.pushDefault`

### Test 5.2: Push to Local Remote (Default)
**Objective**: Verify changes push back to host repository

**Steps**:
1. Make change in container:
   ```bash
   docker exec -it copilot-test-workspace bash
   cd /workspace
   echo "Test from container" >> test-file.txt
   git add test-file.txt
   git commit -m "Test commit from container"
   git push
   ```
2. Check host repository for changes

**Expected Results**:
- [ ] `git push` succeeds without errors
- [ ] Changes appear in host repository branch
- [ ] Host git log shows new commit

**Validation (on host)**:
```bash
cd e:\dev\CodingAgents\test-workspace
git log --oneline -1
# Should show "Test commit from container"
```

### Test 5.3: Push to Origin Remote (GitHub)
**Objective**: Verify can push to GitHub explicitly

**Steps**:
```bash
docker exec -it copilot-test-workspace bash
cd /workspace
git push origin copilot/feature-auth
```

**Expected Results**:
- [ ] Push succeeds (requires authentication)
- [ ] Branch appears on GitHub repository
- [ ] Can create PR from GitHub UI

**Validation**:
- Visit GitHub repository in browser
- [ ] Branch `copilot/feature-auth` exists
- [ ] Commits are visible

### Test 5.4: Pull from Local Remote
**Objective**: Verify can pull changes from host

**Steps**:
1. Make change on host repository:
   ```bash
   cd e:\dev\CodingAgents\test-workspace
   echo "Host change" >> host-file.txt
   git add host-file.txt
   git commit -m "Change from host"
   ```

2. Pull in container:
   ```bash
   docker exec -it copilot-test-workspace bash
   cd /workspace
   git pull local main
   ```

**Expected Results**:
- [ ] Pull succeeds
- [ ] `host-file.txt` appears in container workspace
- [ ] Git log shows "Change from host" commit

### Test 5.5: Branch Naming Convention
**Objective**: Verify agent-prefixed branches are created correctly

**Steps**:
```powershell
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace -b my-feature --agent copilot
```

**Expected Results**:
- [ ] Branch created: `copilot/my-feature`
- [ ] Container checks out branch automatically

**Validation**:
```bash
docker exec -it copilot-test-workspace git branch --show-current
# Output: copilot/my-feature
```

---

## Test Suite 6: MCP Configuration Setup

### Test 6.1: Verify config.toml Conversion
**Objective**: Confirm config.toml is converted to agent-specific JSON

**Prerequisites**:
- [ ] Place config.toml in test repository root

**Steps**:
```powershell
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace --agent copilot
```

**Expected Results**:
- [ ] Container startup logs show "Converting config.toml..."
- [ ] MCP JSON configs created for each agent

**Validation**:
```bash
# Check conversion logs
docker logs copilot-test-workspace | grep -i "mcp\|config"

# Check generated JSON files
docker exec -it copilot-test-workspace bash -c "cat ~/.config/github-copilot/mcp/config.json"
# Should show JSON with mcpServers object

docker exec -it copilot-test-workspace bash -c "cat ~/.config/codex/mcp/config.json"
# Should show JSON (if codex config present)

docker exec -it copilot-test-workspace bash -c "cat ~/.config/claude/mcp/config.json"
# Should show JSON (if claude config present)
```

### Test 6.2: MCP Secrets Loading
**Objective**: Verify environment variables loaded from mcp-secrets.env

**Prerequisites**:
- [ ] Create `~/.config/coding-agents/mcp-secrets.env`:
  ```bash
  GITHUB_TOKEN=test_token_value
  CONTEXT7_API_KEY=test_api_key
  ```

**Steps**:
```powershell
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace --agent copilot
```

**Expected Results**:
- [ ] Secrets file mounted at `~/.mcp-secrets.env` (read-only)
- [ ] Environment variables available in container

**Validation**:
```bash
docker exec -it copilot-test-workspace bash -c "env | grep -E 'GITHUB_TOKEN|CONTEXT7_API_KEY'"
# Should show:
# GITHUB_TOKEN=test_token_value
# CONTEXT7_API_KEY=test_api_key
```

### Test 6.3: MCP Server Execution
**Objective**: Verify MCP servers can be invoked

**Steps**:
```bash
docker exec -it copilot-test-workspace bash
npx @modelcontextprotocol/server-sequential-thinking --version
npx @playwright/mcp@latest --help
```

**Expected Results**:
- [ ] MCP server packages execute without errors
- [ ] Help/version output displays correctly

### Test 6.4: Environment Variable Substitution
**Objective**: Confirm ${VAR} substitution works in config.toml

**Prerequisites**:
- [ ] `config.toml` contains:
  ```toml
  [mcp_servers.context7]
  command = "npx"
  args = ["-y", "@upstash/context7-mcp", "--api-key", "${CONTEXT7_API_KEY}"]
  ```
- [ ] `mcp-secrets.env` contains: `CONTEXT7_API_KEY=real_key`

**Steps**:
1. Launch container
2. Check generated JSON config

**Expected Results**:
- [ ] JSON config shows `"${CONTEXT7_API_KEY}"` placeholder
- [ ] At runtime, variable expands to actual key value

**Validation**:
```bash
docker exec -it copilot-test-workspace bash -c "cat ~/.config/github-copilot/mcp/config.json | grep CONTEXT7_API_KEY"
# Should show: "${CONTEXT7_API_KEY}"

docker exec -it copilot-test-workspace bash -c "echo \$CONTEXT7_API_KEY"
# Should show: real_key
```

---

## Test Suite 7: .NET Preview SDK Installation

### Test 7.1: Install .NET 9.0 Preview
**Objective**: Verify .NET preview SDK installs at container startup

**Steps**:
```powershell
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace --agent copilot --dotnet-preview 9.0
```

**Expected Results**:
- [ ] Container startup logs show .NET 9.0 installation
- [ ] Installation completes without errors

**Validation**:
```bash
docker exec -it copilot-test-workspace dotnet --list-sdks
# Should show both 8.0.x (stable) and 9.0.x (preview)

docker exec -it copilot-test-workspace dotnet --version
# Should show 9.0.x if set as default
```

### Test 7.2: No Preview SDK (Default)
**Objective**: Verify containers work without preview SDK

**Steps**:
```powershell
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace --agent claude
```

**Expected Results**:
- [ ] Container starts normally
- [ ] Only .NET 8.0 SDK present

**Validation**:
```bash
docker exec -it claude-test-workspace dotnet --list-sdks
# Should show only 8.0.x
```

---

## Test Suite 8: Squid Proxy Functionality

### Test 8.1: Proxy Container Startup
**Objective**: Verify Squid proxy sidecar starts correctly

**Steps**:
```powershell
.\launch-agent.ps1 e:\dev\CodingAgents\test-workspace --agent copilot --network-proxy squid
```

**Expected Results**:
- [ ] Proxy container `copilot-test-workspace-proxy` created
- [ ] Proxy container running: `docker ps | grep proxy`
- [ ] Squid process active inside proxy container

**Validation**:
```bash
docker exec -it copilot-test-workspace-proxy ps aux | grep squid
# Should show squid processes running

docker logs copilot-test-workspace-proxy
# Should show Squid startup logs
```

### Test 8.2: HTTP Traffic Routing
**Objective**: Verify HTTP requests go through Squid

**Steps**:
```bash
docker exec -it copilot-test-workspace curl -I http://www.example.com
```

**Expected Results**:
- [ ] Request succeeds
- [ ] Proxy logs show HTTP request

**Validation**:
```bash
docker logs copilot-test-workspace-proxy | grep example.com
# Should show access log entry with timestamp and URL
```

### Test 8.3: HTTPS Traffic Routing
**Objective**: Verify HTTPS requests go through Squid

**Steps**:
```bash
docker exec -it copilot-test-workspace curl -I https://www.google.com
```

**Expected Results**:
- [ ] Request succeeds
- [ ] Proxy logs show CONNECT request (HTTPS tunnel)

**Validation**:
```bash
docker logs copilot-test-workspace-proxy | grep CONNECT | grep google.com
# Should show CONNECT method log entry
```

### Test 8.4: Proxy Environment Variables
**Objective**: Confirm proxy variables set correctly in agent container

**Steps**:
```bash
docker exec -it copilot-test-workspace env | grep -i proxy
```

**Expected Results**:
```
HTTP_PROXY=http://copilot-test-workspace-proxy:3128
HTTPS_PROXY=http://copilot-test-workspace-proxy:3128
http_proxy=http://copilot-test-workspace-proxy:3128
https_proxy=http://copilot-test-workspace-proxy:3128
NO_PROXY=localhost,127.0.0.1,.internal,::1
no_proxy=localhost,127.0.0.1,.internal,::1
```

### Test 8.5: Proxy Access Logs
**Objective**: Verify Squid logs are accessible and readable

**Steps**:
1. Generate some traffic:
   ```bash
   docker exec -it copilot-test-workspace bash -c "for i in {1..5}; do curl -s https://api.github.com > /dev/null; done"
   ```

2. Check logs:
   ```bash
   docker logs copilot-test-workspace-proxy | tail -20
   ```

**Expected Results**:
- [ ] Access log contains 5+ entries
- [ ] Each entry shows timestamp, client IP, method, URL, status code

---

## Test Suite 9: Security & Edge Cases

### Test 9.1: Non-Root User
**Objective**: Verify container runs as non-root (UID 1000)

**Steps**:
```bash
docker exec -it copilot-test-workspace id
```

**Expected Results**:
```
uid=1000(agentuser) gid=1000(agentuser) groups=1000(agentuser)
```

### Test 9.2: Read-Only Auth Mounts
**Objective**: Confirm authentication directories are read-only

**Steps**:
```bash
docker exec -it copilot-test-workspace touch ~/.config/gh/test.txt
```

**Expected Results**:
- [ ] Command fails with "Read-only file system" error
- [ ] Cannot modify mounted authentication configs

### Test 9.3: No Privilege Escalation
**Objective**: Verify security-opt prevents privilege escalation

**Steps**:
```bash
docker inspect copilot-test-workspace | grep -i securityopt
```

**Expected Results**:
```json
"SecurityOpt": [
    "no-new-privileges:true"
]
```

### Test 9.4: Missing Authentication
**Objective**: Verify container warns but doesn't fail without auth

**Steps**:
1. Temporarily move auth config:
   ```bash
   mv ~/.config/gh ~/.config/gh.backup
   ```

2. Launch container:
   ```powershell
   .\launch-agent.ps1 e:\dev\CodingAgents\test-workspace --agent copilot
   ```

3. Restore auth:
   ```bash
   mv ~/.config/gh.backup ~/.config/gh
   ```

**Expected Results**:
- [ ] Container launches successfully
- [ ] Warning logged: "GitHub CLI: Run 'gh auth login'..."
- [ ] Container does not exit

---

## Test Suite 10: Cleanup & Teardown

### Test 10.1: Remove Single Container
**Objective**: Verify container removal works correctly

**Steps**:
```bash
docker rm -f copilot-test-workspace
```

**Expected Results**:
- [ ] Container removed: `docker ps -a | grep copilot-test-workspace` returns nothing

### Test 10.2: Remove Container with Proxy
**Objective**: Clean up proxy sidecar and network

**Steps**:
```bash
docker rm -f copilot-test-workspace
docker rm -f copilot-test-workspace-proxy
docker network rm copilot-test-workspace-net
```

**Expected Results**:
- [ ] Both containers removed
- [ ] Custom network removed
- [ ] No orphaned resources

### Test 10.3: Full System Cleanup
**Objective**: Remove all test artifacts

**Steps**:
```bash
# Remove all test containers
docker ps -a --filter "name=test-workspace" -q | ForEach-Object { docker rm -f $_ }

# Remove test images (if built locally)
docker rmi coding-agents-copilot:local -f
docker rmi coding-agents-codex:local -f
docker rmi coding-agents-claude:local -f
docker rmi coding-agents:local -f
docker rmi coding-agents-base:local -f
docker rmi coding-agents-proxy:local -f

# Remove networks
docker network ls --filter "name=test-workspace" -q | ForEach-Object { docker network rm $_ }
```

**Expected Results**:
- [ ] All test containers removed
- [ ] All test images removed
- [ ] All custom networks removed

---

## Test Execution Checklist

### Pre-Test Setup
- [ ] All prerequisites installed
- [ ] GitHub authentication configured
- [ ] Test repository prepared
- [ ] Docker daemon running

### Execution Order
1. [ ] Suite 1: Building Images Locally
2. [ ] Suite 2: Pulling from GHCR
3. [ ] Suite 3: Launching Containers (Network Modes)
4. [ ] Suite 4: VS Code Dev Containers Integration
5. [ ] Suite 5: Git Workflow (Dual Remotes)
6. [ ] Suite 6: MCP Configuration Setup
7. [ ] Suite 7: .NET Preview SDK Installation
8. [ ] Suite 8: Squid Proxy Functionality
9. [ ] Suite 9: Security & Edge Cases
10. [ ] Suite 10: Cleanup & Teardown

### Post-Test Cleanup
- [ ] All containers stopped and removed
- [ ] Test files cleaned up
- [ ] System resources freed

---

## Test Results Summary

| Test Suite | Status | Notes |
|------------|--------|-------|
| 1. Building Images Locally | ⬜ | |
| 2. Pulling from GHCR | ⬜ | |
| 3. Launching Containers | ⬜ | |
| 4. VS Code Integration | ⬜ | |
| 5. Git Workflow | ⬜ | |
| 6. MCP Configuration | ⬜ | |
| 7. .NET Preview SDK | ⬜ | |
| 8. Squid Proxy | ⬜ | |
| 9. Security & Edge Cases | ⬜ | |
| 10. Cleanup & Teardown | ⬜ | |

**Legend**: ✅ Pass | ❌ Fail | ⚠️ Warning | ⬜ Not Run

---

## Troubleshooting Common Issues

### Build Failures
- **Issue**: Base image build fails on package installation
- **Solution**: Check internet connectivity, retry with `--no-cache`

### Container Won't Start
- **Issue**: Container exits immediately
- **Solution**: Check logs with `docker logs <container>`, verify mounts exist

### VS Code Can't Attach
- **Issue**: "Cannot attach to container" error
- **Solution**: Ensure container is running (`docker ps`), restart Docker daemon

### Git Push Fails
- **Issue**: "remote not found" or authentication errors
- **Solution**: Verify `gh auth status`, check git remote configuration

### MCP Conversion Fails
- **Issue**: config.toml not converted to JSON
- **Solution**: Verify TOML syntax, check entrypoint logs

### Proxy Traffic Not Logged
- **Issue**: Squid access.log empty
- **Solution**: Verify proxy environment variables set, check Squid configuration

---

**Document Version**: 1.0  
**Last Updated**: 2025-11-13  
**Maintained By**: CodingAgents Team
