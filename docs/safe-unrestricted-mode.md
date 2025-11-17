# Safe-Unrestricted Mode: Quick Reference

This guide explains how to use AI coding agents in safe-unrestricted mode for maximum productivity with structural security.

## What is Safe-Unrestricted Mode?

Safe-unrestricted mode is the **default operating mode** for AI coding agents. It provides:

✅ **Full development capabilities** - Install packages, run builds, access external APIs  
✅ **Minimal prompts** - Most operations run without asking  
✅ **Structural safety** - Security enforced by container architecture, not prompts  
✅ **Host isolation** - Container cannot affect your host system  
✅ **Audit trail** - Git history + network logs for forensics  

## Quick Start

```bash
# Launch an agent (uses safe-unrestricted mode by default)
launch-agent copilot

# Or for ephemeral session
run-copilot

# Explicitly specify squid proxy (recommended default)
launch-agent copilot --network-proxy squid
```

That's it! The agent can now work freely while staying within safety boundaries.

## What Agents Can Do (Without Prompts)

### ✅ Always Allowed (Tier 1)
- Read and write files in /workspace
- Install npm, pip, nuget packages from registries
- Run builds, tests, linters
- Commit code and push to agent branch
- Access allowlisted external APIs
- Use MCP tools (GitHub, Playwright, Serena, etc.)

### ✅ Allowed and Logged (Tier 2)
- Push to remote repositories
- Install packages from git URLs
- Make large network requests
- Execute compiled binaries

### ❌ Blocked (Tier 3)
- Access docker.sock or control Docker
- Install system packages (apt/yum)
- Access private IPs (10.x, 192.168.x)
- Access cloud metadata (169.254.169.254)
- Escalate privileges
- Write to host filesystem

## Safety Features (Always Active)

### 1. Host Isolation
- Container runs as non-root user (UID 1000)
- All Linux capabilities dropped
- No docker.sock access
- No host filesystem mounts
- No privileged mode

### 2. Network Safety
- Squid proxy with domain allowlist
- Private IPs blocked (10.x, 172.x, 192.168.x)
- Cloud metadata endpoints blocked
- All requests logged for audit

### 3. Git Safety
- All changes on dedicated branch (e.g., `copilot/session-1`)
- Automatic snapshots before destructive operations
- Auto-commit on shutdown
- Full git history for rollback

### 4. Credential Safety
- All credentials mounted read-only
- Cannot be modified by agent
- Revoke on host = instant container loss
- Proxied via secure sockets when possible

## Network Modes Explained

### Squid Proxy (Default, Recommended)
```bash
launch-agent copilot --network-proxy squid
```
- ✅ MCP tools work
- ✅ Package installs work
- ✅ External APIs work (if allowlisted)
- ✅ Full audit trail
- ❌ Private IPs blocked
- ❌ Metadata endpoints blocked

**Use for:** 95% of development work

### Restricted (Maximum Security)
```bash
launch-agent copilot --network-proxy restricted
```
- ✅ Maximum security
- ✅ Zero exfiltration risk
- ❌ No external access at all
- ❌ MCP tools requiring network won't work
- ❌ Package installs won't work

**Use for:** Reviewing untrusted code, compliance requirements

### Allow-All (Fastest)
```bash
launch-agent copilot --network-proxy allow-all
```
- ✅ Fastest (no proxy overhead)
- ✅ No restrictions
- ❌ No audit trail
- ❌ No blocking of dangerous endpoints

**Use for:** Fully trusted code, development only

## Common Workflows

### Standard Development
```bash
# 1. Launch agent
launch-agent copilot

# 2. Agent works freely, all changes on copilot/session-1 branch

# 3. Review changes
git diff main copilot/session-1

# 4. Merge if good
git checkout main
git merge copilot/session-1
git push origin main
```

### Code Review (Untrusted Code)
```bash
# 1. Clone to temp directory
git clone https://github.com/untrusted/repo /tmp/review
cd /tmp/review

# 2. Launch in restricted mode
run-copilot --network-proxy restricted

# 3. Agent reviews code (no network access)

# 4. Check squid logs (if using squid mode instead)
docker logs copilot-review-proxy
```

### Long-Running Task
```bash
# 1. Launch persistent container
launch-agent copilot

# 2. Detach from session
# (container keeps running)

# 3. Reconnect later
connect-agent copilot

# 4. Or attach via VS Code
# Remote Containers: Attach to Running Container
```

## Monitoring and Verification

### Check What Agent Did
```bash
# View git changes
git log copilot/session-1
git diff main copilot/session-1

# View network activity (squid mode)
docker logs copilot-myproject-session-1-proxy

# View container processes
docker exec copilot-myproject-session-1 ps aux
```

### Verify Security Settings
```bash
# Check container is non-root
docker exec copilot-test whoami
# Expected: agentuser

# Check capabilities are dropped
docker exec copilot-test cat /proc/self/status | grep Cap
# Expected: All zeros

# Check docker.sock is not available
docker exec copilot-test ls /var/run/docker.sock
# Expected: No such file or directory
```

### Review Squid Logs
```bash
# View all requests
docker logs copilot-myproject-session-1-proxy

# Search for specific domain
docker logs copilot-myproject-session-1-proxy | grep github.com

# Count requests per domain
docker logs copilot-myproject-session-1-proxy | \
  grep -oP '(?<=//)[^/]+' | sort | uniq -c | sort -rn
```

## When to Use Different Modes

| Scenario | Network Mode | Rationale |
|----------|-------------|-----------|
| Normal development | `squid` | Balance of safety and functionality |
| Trusted team repo | `allow-all` | Fastest, minimal overhead |
| Untrusted PR review | `restricted` | No exfiltration possible |
| Compliance/audit | `squid` + `--no-push` | Full logs, no auto-push |
| Sensitive data | `restricted` or custom squid allowlist | Minimal attack surface |
| Quick prototype | `allow-all` | Speed over security |
| Production config | `restricted` | Read-only, no network |

## Troubleshooting

### "Package install failed"
- **Cause:** Restricted mode blocks npm/pip registry access
- **Solution:** Use `--network-proxy squid` or `allow-all`

### "Cannot access github.com"
- **Cause:** Domain not in squid allowlist
- **Solution:** Add domain to allowlist or use allow-all mode

```bash
launch-agent copilot --network-proxy squid \
  --squid-domains "*.github.com,*.npmjs.org,custom.domain.com"
```

### "Permission denied" when writing files
- **Cause:** Trying to write outside /workspace
- **Solution:** Only /workspace is writable, write files there

### "docker: command not found"
- **Cause:** Docker is not available in containers (by design)
- **Solution:** Cannot run docker inside agent containers (host isolation)

### "sudo: command not found"
- **Cause:** No sudo in container (non-root user)
- **Solution:** Cannot install system packages; use userspace alternatives

## Safety Checklist Before Merge

When reviewing agent changes before merging to main:

- [ ] Review git diff: `git diff main copilot/session-1`
- [ ] Check for suspicious code patterns (obfuscation, credential harvesting)
- [ ] Review CI/CD file changes (.github/workflows/*)
- [ ] Check new dependencies (package.json, requirements.txt, etc.)
- [ ] Review squid logs for unusual network activity
- [ ] Verify no secrets in commit messages or code
- [ ] Check for modifications to security checks or validation
- [ ] Look for weakening of authentication or authorization

## Emergency Procedures

### Stop Suspicious Agent
```bash
# Stop container immediately
docker stop copilot-myproject-session-1

# Stop and remove
docker rm -f copilot-myproject-session-1

# Also stop proxy if using squid
docker rm -f copilot-myproject-session-1-proxy
```

### Review What Happened
```bash
# Check git changes
git diff main copilot/session-1

# Check network logs
docker logs copilot-myproject-session-1-proxy > network-audit.log

# Look for exfiltration attempts
grep -E "(POST|PUT)" network-audit.log
grep -E "169\.254|10\.|192\.168\." network-audit.log
```

### Clean Up
```bash
# Delete agent branch
git branch -D copilot/session-1

# Rotate credentials if suspected compromise
gh auth logout
gh auth login

# Remove container and volumes
docker rm -f copilot-myproject-session-1
docker volume prune
```

## Advanced Configuration

### Custom Squid Allowlist (Minimal)
```bash
launch-agent copilot --network-proxy squid \
  --squid-domains "api.openai.com,api.anthropic.com,*.github.com"
```

### Custom Squid Allowlist (Extended)
```bash
launch-agent copilot --network-proxy squid \
  --squid-domains "$(cat << EOF
*.github.com
*.githubcopilot.com
*.npmjs.org
*.pypi.org
api.openai.com
api.anthropic.com
docs.python.org
*.stackoverflow.com
EOF
)"
```

### Disable Auto-Push
```bash
launch-agent copilot --no-push
# Agent commits locally but doesn't push to remote
```

### Custom Branch Name
```bash
launch-agent copilot --branch feature-xyz
# Creates copilot/feature-xyz instead of copilot/session-N
```

### Resource Limits
```bash
launch-agent copilot --cpu 2 --memory 4g
# Limit to 2 CPUs and 4GB RAM
```

## Best Practices

### ✅ Do
- Use squid mode by default for balance of safety and functionality
- Review agent branches before merging to main
- Check squid logs periodically for unusual patterns
- Use restricted mode for reviewing untrusted code
- Keep container images updated
- Use dedicated branches for agent work

### ❌ Don't
- Use allow-all mode with untrusted code
- Merge agent branches without review
- Share squid logs publicly (may contain URLs with sensitive data)
- Mount host directories directly (defeats isolation)
- Run containers as root
- Disable security features for convenience

## FAQ

**Q: Is unrestricted mode safe for production code?**  
A: Yes, with proper review. Agent changes are isolated to a branch that requires explicit merge to reach production.

**Q: Can the agent access my AWS/Azure credentials?**  
A: Only if you mount them. By default, only GitHub and model API credentials are mounted.

**Q: Can the agent escape the container?**  
A: No. All capabilities are dropped, no docker.sock access, no privileged mode, and no host mounts.

**Q: Can the agent steal my GitHub token?**  
A: The token is visible to the agent (needed for functionality), but exfiltration to non-allowlisted domains is blocked in squid mode.

**Q: What if I need to install a system package?**  
A: You can't (no sudo). Use userspace alternatives or build from source in /workspace.

**Q: Can I use agents with private repositories?**  
A: Yes. Your GitHub credentials are mounted read-only and work with private repos.

**Q: How do I trust the agent's code changes?**  
A: Review the branch before merging. Agent cannot auto-merge to main.

## Further Reading

- [Security Architecture Analysis](security-architecture-analysis.md) - Complete threat model
- [Tool Danger Matrix](tool-danger-matrix.md) - Detailed risk classifications
- [SECURITY.md](../SECURITY.md) - Full security policy
- [USAGE.md](../USAGE.md) - Complete usage guide

## Getting Help

- Security questions: Open issue with `security` label
- Security vulnerabilities: Use [GitHub Security Advisories](https://github.com/novotnyllc/CodingAgents/security/advisories/new)
- General questions: Open issue with `question` label
