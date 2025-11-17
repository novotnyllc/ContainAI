# Tool Danger Matrix

This document classifies all tools and operations available to AI coding agents by risk level and defines the tiered policy for safe-unrestricted mode.

## Tier Definitions

- **Tier 1 (Green - Always Allow):** Safe or easily reversible operations. No prompts, no restrictions.
- **Tier 2 (Yellow - Log and Monitor):** Higher risk but necessary for development. No prompts, but logged for forensics and rate-limited.
- **Tier 3 (Red - Restrict or Prompt):** Dangerous operations. Blocked by architecture or require explicit user confirmation.

## Tool Classification Matrix

| Tool/Action | Destructive | Exfiltration | Lateral Movement | Host Escape | Tier | Mitigation |
|-------------|-------------|--------------|------------------|-------------|------|------------|
| **Filesystem Operations** |
| Read files in /workspace | None | High¹ | None | None | 1 | Allow (source code context) |
| Write files in /workspace | Medium² | None | None | None | 1 | Allow (branch isolated) |
| Delete files in /workspace | High³ | None | None | None | 1 | Allow with auto-snapshot |
| Modify .git directory | Critical | None | None | None | 2 | Allow but log |
| Write to /tmp | Low | None | None | None | 1 | Allow (tmpfs, ephemeral) |
| Read ~/.config credentials | None | Critical | High | None | 1 | Read-only mount only |
| Write to / (root) | N/A⁹ | N/A | N/A | High | - | Blocked (read-only rootfs option) |
| **Git Operations** |
| git status, diff, log, show | None | Low | None | None | 1 | Allow always |
| git add, commit | None | None | None | None | 1 | Allow always |
| git push (to local remote) | None | None | None | None | 1 | Allow always |
| git push (to origin) | Medium⁴ | Medium⁵ | None | None | 2 | Log and rate limit |
| git checkout (files) | Medium | None | None | None | 1 | Auto-snapshot created |
| git reset --hard | High³ | None | None | None | 2 | Auto-snapshot created |
| git rebase | High³ | None | None | None | 2 | Auto-snapshot created |
| git filter-branch | Critical | None | None | None | 3 | Block or prompt |
| git filter-repo | Critical | None | None | None | 3 | Block or prompt |
| **Network Operations** |
| HTTP GET (allowlisted) | None | None⁶ | None | None | 1 | Allow via proxy |
| HTTP POST (allowlisted) | None | High | Medium | None | 2 | Allow via proxy + log |
| HTTP (non-allowlisted) | None | Critical | High | None | 3 | Blocked by squid |
| Access private IPs | None | Critical | High | None | 3 | Blocked by squid |
| Access cloud metadata | None | Critical | Critical | None | 3 | Blocked by squid |
| DNS queries | None | Medium⁷ | Low | None | 2 | Logged via proxy |
| Large uploads (>10MB) | None | High | Medium | None | 2 | Rate limited |
| **Package Management** |
| npm install (from registry) | Low⁸ | None | None | None | 1 | Allow via proxy |
| pip install (from PyPI) | Low⁸ | None | None | None | 1 | Allow via proxy |
| dotnet restore | Low⁸ | None | None | None | 1 | Allow via proxy |
| npm install (from git URL) | Medium | Medium | Medium | None | 2 | Allow via proxy + log |
| pip install (from git URL) | Medium | Medium | Medium | None | 2 | Allow via proxy + log |
| apt install | N/A⁹ | N/A | N/A | N/A | - | Blocked (no sudo) |
| Install global packages | N/A⁹ | N/A | N/A | N/A | - | Blocked (no sudo) |
| **Build and Execution** |
| Compile code (gcc, make) | None | None | None | None | 1 | Allow always |
| Build (npm, dotnet, cargo) | None | None | None | None | 1 | Allow always |
| Run tests | None | None¹⁰ | None | None | 1 | Allow always |
| Execute workspace binaries | High³ | High | High | Low¹¹ | 2 | Allow with monitoring |
| Run containers (docker run) | N/A⁹ | N/A | N/A | Critical | - | Blocked (no docker CLI) |
| **MCP Operations** |
| GitHub MCP (read repos) | None | Medium | Low | None | 1 | Allow always |
| GitHub MCP (list issues/PRs) | None | Low | None | None | 1 | Allow always |
| GitHub MCP (create issue) | Low | None | None | None | 2 | Log and rate limit |
| GitHub MCP (push code) | Medium | Medium | Medium | None | 2 | Log and rate limit |
| GitHub MCP (admin ops) | High | High | High | None | 3 | Require approval |
| Playwright (allowlisted sites) | None | Low | None | None | 1 | Allow via proxy |
| Playwright (arbitrary sites) | Medium | Medium | Medium | None | 2 | Via proxy + log |
| Serena (read code) | None | Low | None | None | 1 | Allow always |
| Serena (edit code) | Medium² | None | None | None | 1 | Allow (branch isolated) |
| Context7 (docs lookup) | None | None | None | None | 1 | Allow always |
| Sequential Thinking | None | None | None | None | 1 | Allow always |
| **System Operations** |
| View processes (ps, top) | None | Low | None | None | 1 | Allow always |
| Kill processes | Medium | None | None | None | 1 | Allow (container only) |
| Access docker.sock | N/A | N/A | N/A | Critical | - | Not mounted |
| Mount filesystems | N/A⁹ | N/A | N/A | Critical | - | Blocked (no sudo, no cap) |
| Load kernel modules | N/A⁹ | N/A | N/A | Critical | - | Blocked (no cap) |
| Change networking | N/A⁹ | N/A | N/A | High | - | Blocked (no CAP_NET_ADMIN) |
| ptrace (debugging) | Low | Low | None | Medium | 2 | Allowed (no CAP_SYS_PTRACE for cross-process) |

## Footnotes

1. **Can exfiltrate source code:** Agent can read and send source code, but this is often intentional (e.g., sending code to model API for analysis). Exfiltration to non-allowlisted domains is blocked.

2. **Can modify code to inject backdoors:** Agent can write malicious code on its branch, but branch isolation and user review prevent auto-merge to main.

3. **Damage limited to agent's workspace/branch:** Destructive operations only affect the container's ephemeral workspace copy and the agent's isolated branch. Auto-snapshots enable easy rollback.

4. **Can push malicious code to remote:** Agent can push to origin, but still on agent-specific branch requiring user review before merge.

5. **Could push secrets to public repo:** Agent could accidentally or maliciously push credentials, but squid logs would show the push and credentials are read-only (cannot be rotated by agent).

6. **Via squid logs:** All HTTP/HTTPS traffic is logged, making exfiltration patterns detectable during forensic review.

7. **DNS tunneling possible but limited:** Agent could encode data in DNS queries, but this is low-bandwidth and detectable in logs.

8. **Malicious packages possible:** Packages could contain malicious code, but execution is contained within isolated container with no host access.

9. **Blocked by architecture:** Operation requires sudo, docker access, or Linux capabilities that are not available in the container.

10. **Tests could contain exfiltration code:** Test code can make network requests, but these go through squid proxy and are subject to allowlist/logging.

11. **Theoretical kernel exploit:** If a compiled binary exploits a kernel vulnerability, it could potentially escape, but all capabilities are dropped and modern container runtimes have additional protections.

## Default Policy for Safe-Unrestricted Mode

**Tier 1 Operations:**
- Execute silently without prompts
- Essential for productive development
- Damage is contained and reversible

**Tier 2 Operations:**
- Execute silently without prompts
- Logged for forensic analysis
- Rate limited to prevent abuse
- User can review logs post-hoc

**Tier 3 Operations:**
- Blocked by container architecture (no docker.sock, no capabilities, no sudo)
- OR require explicit user approval (if not blockable by architecture)
- Reserved for truly dangerous operations

## Monitoring and Alerting

The following patterns should trigger alerts for security review:

**High Priority Alerts:**
- Access attempts to blocked domains (cloud metadata, private IPs)
- Large data uploads (>10MB POST requests)
- Rapid API rate (>100 requests/minute)
- Git operations on .git internals
- Multiple failed authentication attempts

**Medium Priority Alerts:**
- Package installs from non-registry sources (git URLs)
- Execution of newly compiled binaries
- Git history rewriting operations
- Access to credential files

**Low Priority Alerts:**
- High volume of network requests (even if allowlisted)
- Large numbers of file modifications
- Process creation (for baseline understanding)

## Safe Operation Wrappers

The following wrapper scripts enforce safety automatically:

### git-safe-operation

Wraps destructive git operations with automatic snapshots:

```bash
# Instead of: git reset --hard HEAD~5
# Use: git-safe-operation reset --hard HEAD~5

# Automatically creates snapshot tag like "agent-snapshot-1700000000"
# User can rollback: git reset --hard agent-snapshot-1700000000
```

**Operations that get snapshots:**
- git reset
- git rebase
- git filter-branch
- git filter-repo
- git checkout (when checking out old commits)

### Future Wrappers (Roadmap)

**safe-file-write:** Validates files are within /workspace before writing

**safe-shell-exec:** Blocks obviously dangerous command patterns

**safe-http-request:** Enforces allowlist even without squid proxy

## Usage Examples

### Development Scenario (Tier 1 - All Silent)

```bash
# Agent performs these operations without any prompts:
git checkout -b copilot/feature-xyz
echo "new code" > src/new-file.ts
npm install express
npm test
git add .
git commit -m "Add feature"
git push local copilot/feature-xyz
```

**Result:** All operations succeed silently. User reviews branch before merging.

### Code Review Scenario (Tier 2 - Silent but Logged)

```bash
# Agent needs to fetch external documentation
curl https://docs.python.org/api.json  # Via squid, logged
npm install git+https://github.com/example/lib.git  # Logged as non-registry

# Agent pushes to remote for CI testing
git push origin copilot/feature-xyz  # Logged and rate limited
```

**Result:** Operations succeed. User can review squid logs if suspicious.

### Blocked Scenario (Tier 3)

```bash
# Agent attempts dangerous operations
curl http://169.254.169.254/latest/meta-data/  # BLOCKED by squid
curl http://192.168.1.1/admin  # BLOCKED by squid (private IP)
docker run ubuntu  # BLOCKED (no docker CLI installed)
sudo apt install malware  # BLOCKED (no sudo)
```

**Result:** Operations fail. User sees blocked attempts in logs.

## Recommendations by Use Case

### Trusted Repository + External APIs Needed
```bash
launch-agent copilot --network-proxy squid
```
- Best balance of functionality and security
- Allows MCP tools, package installs, documentation lookup
- Blocks metadata and private IPs
- Full audit trail

### Untrusted Repository + No External Access Needed
```bash
launch-agent copilot --network-proxy restricted
```
- Maximum security
- No exfiltration possible
- Agent can only modify local files
- Use for code review of untrusted pull requests

### Trusted Repository + High Performance Needed
```bash
launch-agent copilot --network-proxy allow-all
```
- No proxy overhead
- Faster package installs
- No audit trail
- Use only for fully trusted code

### Sensitive Repository + Compliance Required
```bash
launch-agent copilot --network-proxy squid --no-push
```
- Network traffic logged
- No automatic push to remote
- Full audit trail for compliance
- Use for regulated industries

## Testing the Policy

### Verify Tier 1 Operations Work
```bash
docker exec copilot-test git status
docker exec copilot-test touch /workspace/test.txt
docker exec copilot-test npm install express
```

### Verify Tier 2 Operations Are Logged
```bash
docker exec copilot-test git push origin copilot/test-branch
docker logs copilot-test-proxy | grep push
```

### Verify Tier 3 Operations Are Blocked
```bash
docker exec copilot-test curl http://169.254.169.254
# Expected: Connection timeout or denied

docker exec copilot-test docker ps
# Expected: docker: command not found

docker exec copilot-test sudo apt install test
# Expected: sudo: command not found
```

## Roadmap

**Phase 1 (Implemented):**
- ✅ Capability dropping (--cap-drop=ALL)
- ✅ Network blocking (metadata, private IPs)
- ✅ Git safe operations wrapper
- ✅ Rate limiting in squid

**Phase 2 (Near-term):**
- ⏭️ Automated security scanning on agent branches
- ⏭️ Credential scoping (short-lived, repo-specific tokens)
- ⏭️ Read-only root filesystem option
- ⏭️ Real-time monitoring dashboard

**Phase 3 (Future):**
- ⏭️ Seccomp/AppArmor profiles
- ⏭️ AI-powered anomaly detection in logs
- ⏭️ Credential mediation service
- ⏭️ Per-file operation policies

## References

- [Security Architecture Analysis](security-architecture-analysis.md) - Complete threat model
- [SECURITY.md](../SECURITY.md) - Security policy and guidelines
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [NIST SP 800-190: Container Security Guide](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)
