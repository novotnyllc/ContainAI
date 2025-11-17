# Safe Unrestricted Mode Profile

## Purpose

This document defines the default configuration for "unrestricted mode" - a mode that requires **zero prompts** for normal operations while maintaining strong safety guarantees through structural design.

## Philosophy

**"Unrestricted" means unrestricted by prompts, not unrestricted by architecture.**

The goal is to remove friction (prompts) while maintaining safety through:
1. Container isolation (structural)
2. Filesystem boundaries (structural)
3. Network controls (configurable)
4. Branch isolation (reversibility)
5. Logging (visibility)

## Default Configuration

### Container Settings

```bash
docker run \
    --name "$CONTAINER_NAME" \
    \
    # User and privileges
    --user agentuser \                              # Non-root (UID 1000)
    --security-opt no-new-privileges:true \         # Block privilege escalation
    --cap-drop=ALL \                                # Drop all Linux capabilities
    --pids-limit=4096 \                             # Prevent fork bombs
    --security-opt seccomp=default.json \           # Syscall filtering
    \
    # Resources
    --cpus=4 \                                      # CPU limit
    --memory=8g \                                   # Memory limit
    \
    # Network
    --network agent-squid-network \                 # Squid proxy mode (recommended)
    -e HTTP_PROXY=http://squid:3128 \
    -e HTTPS_PROXY=http://squid:3128 \
    \
    # Filesystem
    -v /tmp/source-repo:/tmp/source-repo:ro \      # Source (read-only, temporary)
    -v ~/.config/gh:/home/agentuser/.config/gh:ro,noexec \  # Creds (read-only, no-exec)
    -v ~/.config/github-copilot:/home/agentuser/.config/github-copilot:ro,noexec \
    -v ~/.mcp-secrets.env:/home/agentuser/.mcp-secrets.env:ro,noexec \
    -v ~/.git-credentials:/home/agentuser/.git-credentials:ro,noexec \
    -v git-cred.sock:/tmp/git-credential-proxy.sock:ro \  # Socket proxy
    \
    # Environment
    -e AGENT_NAME=copilot \
    -e AGENT_BRANCH=copilot/session-1 \
    -e AUTO_PUSH_ON_SHUTDOWN=true \                # Auto-save work
    -e WORKSPACE_DIR=/workspace \
    \
    # Labels (for management)
    --label coding-agents.type=agent \
    --label coding-agents.agent=copilot \
    --label coding-agents.network-policy=squid \
    \
    coding-agents-copilot:latest
```

### Key Properties

| Property | Value | Why |
|----------|-------|-----|
| User | Non-root (UID 1000) | Reduced privileges |
| Capabilities | None (dropped all) | Blocks privilege operations |
| Seccomp | Restrictive profile | Blocks dangerous syscalls |
| Network | Squid proxy | Visibility + allowlist |
| Workspace | Copied (not mounted) | True isolation |
| Credentials | Read-only + noexec | Cannot modify or execute |
| Git remote | Local (default) | Safe auto-sync |
| Branch | Agent-specific | Isolated changes |
| Auto-save | Enabled | Work preserved |

## Operation Tiering

### Tier 1: Silent Allow (99% of operations)

**No prompts, full functionality:**

```bash
# File operations
echo "code" > /workspace/file.py
rm /workspace/old-file.py
mkdir /workspace/new-dir

# Code operations
npm install express
pip install requests
dotnet build
make
gcc program.c

# Git operations
git add -A
git commit -m "Changes"
git push local $BRANCH          # To host repo
git pull
git checkout feature
git branch new-branch

# Read operations
cat ~/.config/gh/hosts.yml
git log
docker ps  # Fails (no socket), but no prompt

# Tests and builds
npm test
pytest
cargo test

# MCP operations (local)
serena read-file file.py
sequential-thinking plan "Implement feature"
```

**Why Tier 1:**
- Confined to workspace/container
- Reversible via git
- Read-only system access
- No network or logged network
- Safe credentials use (proxy)

### Tier 2: Silent Allow + Logged

**No prompts, but activity logged:**

```bash
# Network operations (squid mode)
curl https://npmjs.org/package/express
git clone https://github.com/user/repo
wget https://files.pythonhosted.org/package.whl

# Package installs (logged to stdout)
npm install --save express
pip install --user requests

# MCP operations (network)
github.listRepos()
github.createIssue()
context7.searchDocs("react hooks")
playwright.navigate("https://example.com")

# Credential reads (could be logged)
cat ~/.config/gh/hosts.yml
cat ~/.mcp-secrets.env
```

**Why Tier 2:**
- Functional requirements
- Network to allowlisted domains
- Full logging provides visibility
- No prompts (friction-free)
- Audit trail for forensics

### Tier 3: Prompt or Block

**Prompts required or operation blocked:**

```bash
# Prompt required
git push origin $BRANCH         # ⚠️  "Push to public repo?"
git push --force                # ⚠️  "Force push?"
git filter-branch               # ⚠️  "Rewrite history?"

# Blocked (structurally impossible)
docker run --privileged         # ❌ No docker socket
mount /dev/sda1 /mnt           # ❌ No CAP_SYS_ADMIN, seccomp
echo "data" > /etc/passwd      # ❌ Read-only filesystem (outside workspace)
curl https://evil.com           # ❌ Not in allowlist (squid mode)
ssh internal.company.com        # ❌ Not HTTP/HTTPS (squid mode)

# Blocked (by network mode)
curl https://any.domain         # ❌ No network (restricted mode)
```

**Why Tier 3:**
- Wide impact (push origin)
- Destructive (force push, history rewrite)
- Security violations (docker, mount)
- Outside allowlist (squid)
- No network (restricted)

## Network Mode Selection

### Squid Mode (Recommended Default)

**Use for:** Normal development, most projects

**Properties:**
- HTTP/HTTPS to allowlisted domains
- Full request logging
- Blocks non-allowlisted destinations
- No prompts for allowed operations

**Allowlist (default):**
```
*.github.com
*.githubcopilot.com
*.npmjs.org
*.pypi.org
*.nuget.org
*.docker.io
registry-1.docker.io
learn.microsoft.com
docs.microsoft.com
api.openai.com
*.anthropic.com
```

**Launch:**
```bash
run-copilot  # Squid is default
# or
launch-agent copilot --network-proxy squid
```

### Restricted Mode (Maximum Security)

**Use for:** Sensitive codebases, security reviews, untrusted code

**Properties:**
- Zero network access
- Cannot clone from URLs
- Maximum isolation
- No data exfiltration possible

**Launch:**
```bash
run-copilot --network-proxy restricted
# or
launch-agent copilot --network-proxy restricted
```

**Trade-off:** Must provide local repository (cannot clone)

### Allow-All Mode (Convenience)

**Use for:** Trusted environments, internal networks

**Properties:**
- Full internet access
- No restrictions
- No logging
- Maximum flexibility

**Launch:**
```bash
run-copilot --network-proxy allow-all
# or
launch-agent copilot --network-proxy allow-all
```

**Trade-off:** No visibility, exfiltration possible

## Git Workflow

### Default: Local Remote Auto-Sync

**Setup:**
```bash
# In container
git remote -v
# local   /tmp/local-remote (default push)
# origin  https://github.com/user/repo

git config remote.pushDefault
# local
```

**Behavior:**
- All `git push` commands default to `local` remote
- Changes sync to host repository automatically
- Visible on host immediately
- No public push without explicit command

**Auto-save on shutdown:**
```bash
# Entrypoint cleanup hook
git add -A
git commit -m "Auto-save: <description>"
git push local $BRANCH
```

### Explicit Origin Push (Tier 3 - Prompts)

**When ready to publish:**
```bash
git push origin copilot/feature-x
```

**Prompt shown:**
```
⚠️  Git Push to Origin (Public Repository)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Branch: copilot/feature-x

Commits to be pushed:
abc123 feat: Add authentication
def456 fix: Handle edge case
ghi789 refactor: Clean up code

Files changed:
src/auth.py     (+45, -12)
tests/test.py   (+30, -0)

Push to origin? [y/N]
```

**User decision:**
- `y` - Pushes to origin (creates PR)
- `n` - Cancels push
- `v` - View full diff first

## Monitoring & Logging

### What's Logged (Squid Mode)

**HTTP/HTTPS Requests:**
```
2024-01-15 10:30:45 npmjs.org GET /package/express 200 1024
2024-01-15 10:31:12 github.com POST /repos/user/repo/issues 201 512
2024-01-15 10:32:05 evil.com POST /exfil 403 0  # BLOCKED
```

**Container Operations:**
```json
{
  "timestamp": "2024-01-15T10:30:45Z",
  "container": "copilot-myapp-main",
  "agent": "copilot",
  "category": "git",
  "action": "commit",
  "details": "feat: Add feature"
}
```

### What's NOT Logged

- File contents (unless explicitly configured)
- Credential values (only access events)
- Command arguments (unless explicitly configured)
- Local operations (confined anyway)

### Log Access

**Squid logs:**
```bash
# View request logs
docker logs copilot-myapp-main-proxy

# Or access logs directly
docker exec copilot-myapp-main-proxy cat /var/log/squid/access.log
```

**Container logs:**
```bash
docker logs copilot-myapp-main
```

## Preset Configurations

### Development (Default)

```bash
run-copilot
# = squid mode, auto-save, 4 CPU, 8GB RAM
```

### High-Security Review

```bash
run-copilot --network-proxy restricted --no-push
# = no network, no auto-push, manual commit only
```

### Performance Testing

```bash
run-copilot --cpu 8 --memory 16g --network-proxy allow-all
# = max resources, unrestricted network
```

### Custom Allowlist

```bash
# Create custom allowlist
cat > ~/.config/coding-agents/network-allowlist.txt << EOF
# Minimal allowlist
api.githubcopilot.com
*.github.com
EOF

run-copilot --network-proxy squid
# = Uses custom allowlist
```

## Comparison: Unrestricted vs Traditional

| Aspect | Traditional | Unrestricted Mode | Impact |
|--------|-------------|-------------------|--------|
| File edits | Prompt every time | Silent | -90% prompts |
| Command execution | Prompt each command | Silent (logged) | -90% prompts |
| Package installs | Prompt | Silent (logged) | -10% prompts |
| Network requests | Prompt or block | Silent (logged, allowlisted) | -50% prompts |
| Git local ops | Prompt | Silent | -80% prompts |
| Git push origin | Prompt | Prompt (necessary) | Same |
| Container escape | Try to prevent | Impossible | +Security |
| Host access | Try to prevent | Impossible | +Security |
| Data exfiltration | Try to detect | Logged/blocked | +Visibility |
| Reversibility | Manual backups | Git-based | +Safety |

**Net result:** ~80% fewer prompts, stronger safety guarantees

## User Experience Flow

### 1. Launch (One Command)

```bash
run-copilot
```

No prompts, container ready in 5 seconds.

### 2. Work (No Prompts)

```bash
# Inside container, zero prompts for:
vim src/app.py           # Edit files
npm install express      # Install packages
npm test                 # Run tests
git commit -m "Changes"  # Commit
git push                 # Push to host (local remote)
```

All operations silent, logged where appropriate.

### 3. Review (On Host)

```bash
# On host machine
git log copilot/session-1  # See agent's work
git diff main...copilot/session-1  # Review changes
```

All changes visible, git history intact.

### 4. Publish (One Prompt)

```bash
# In container
git push origin copilot/session-1
# ⚠️  Prompt shown with diff
# User confirms: Y
```

Single prompt for public action.

### 5. Cleanup

```bash
# Exit container
exit

# Auto-save runs:
# - Commits uncommitted changes
# - Pushes to local remote
# - Container stops
```

No data loss, work preserved.

## Security Guarantees

### What's Impossible (Structurally Blocked)

1. ✅ Container escape
2. ✅ Host filesystem modification
3. ✅ Credential modification
4. ✅ Docker daemon control
5. ✅ Privilege escalation
6. ✅ Kernel module loading
7. ✅ Network in restricted mode
8. ✅ Non-allowlisted domains in squid mode

### What's Possible (By Design)

1. ⚠️ Workspace modifications (reversible via git)
2. ⚠️ Credential reading (functional requirement, logged)
3. ⚠️ Network to allowlist (functional requirement, logged)
4. ⚠️ Repository backdoors (requires review before merge)
5. ⚠️ CI/CD tampering (requires review before merge)

### What's Mitigated (Multiple Layers)

1. ⚠️ Kernel exploits (cap-drop + no-new-privileges + seccomp + non-root)
2. ⚠️ Data exfiltration (squid logs + allowlist + monitoring)
3. ⚠️ Resource exhaustion (CPU + memory + pids limits)
4. ⚠️ Lateral movement (network isolation + squid blocking SSH)

## When to Use Each Mode

### Use Squid Mode (Default) When:
- ✅ Normal development work
- ✅ Trusted repositories
- ✅ Need package installations
- ✅ Want visibility into network activity
- ✅ MCP servers need external access

### Use Restricted Mode When:
- ✅ Reviewing untrusted code
- ✅ Working with sensitive data
- ✅ Maximum security required
- ✅ Offline work
- ✅ Compliance requirements

### Use Allow-All Mode When:
- ✅ Completely trusted environment
- ✅ Internal network access needed
- ✅ Custom network requirements
- ⚠️ Understand the risks

## Recommended Defaults

### For Teams

**`.coding-agents.yml` in repository:**
```yaml
# Coding Agents configuration
network-mode: squid
allowlist-file: .coding-agents-allowlist.txt
auto-push: true
resources:
  cpus: 4
  memory: 8g
```

### For Projects

**Custom allowlist per project:**
```
# .coding-agents-allowlist.txt
*.github.com
*.npmjs.org
# Add project-specific domains
api.mycompany.com
docs.mycompany.com
```

### For Security Reviews

**Override for sensitive work:**
```bash
# Ignore project config, use restricted
run-copilot --network-proxy restricted --no-push --cpu 2 --memory 4g
```

## Conclusion

**Safe unrestricted mode achieves:**

1. ✅ **99% of operations without prompts**
   - File operations
   - Code compilation
   - Tests
   - Local git
   - Package installs
   - Network to allowlist

2. ✅ **Strong safety through structure**
   - Container boundary prevents escape
   - No host access
   - No docker control
   - Reversible via git
   - Branch isolation

3. ✅ **Visibility without friction**
   - All network logged (squid)
   - All operations logged (container)
   - Git history complete
   - Forensic trail available

4. ✅ **Minimal prompts only when necessary**
   - Push to origin (public)
   - Force push (destructive)
   - History rewrite (destructive)

**Result:** A development experience that feels unrestricted while maintaining enterprise-grade security through architectural design, not behavioral control.

**Recommendation:** Enable by default, with squid mode as the standard network policy.
