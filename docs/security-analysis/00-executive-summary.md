# Executive Summary: Safe Unrestricted Agent Architecture

## Purpose

This document presents a comprehensive security analysis and architectural design for operating AI coding agents in "unrestricted mode" with minimal confirmation prompts while maintaining strong isolation guarantees.

## Core Finding: Current Architecture is Already Well-Designed

The CodingAgents system implements a **defense-in-depth** approach with multiple layers of isolation that makes it structurally safe for unrestricted operation:

### ✅ Existing Strong Security Measures

1. **Container Isolation**
   - Non-root user (UID 1000)
   - `--security-opt no-new-privileges:true` (prevents privilege escalation)
   - Resource limits (CPU, memory)
   - No Docker socket access
   - **PowerShell: `--cap-drop=ALL`** (removes all Linux capabilities)

2. **Filesystem Isolation**
   - Workspace is **copied**, not bind-mounted (true isolation)
   - Host auth configs mounted read-only
   - No host filesystem access beyond workspace
   - Git-based sync model maintains host boundaries

3. **Network Controls**
   - Three modes: allow-all, restricted (`--network none`), squid proxy
   - Squid mode: domain allowlist + full logging
   - Configurable per-launch

4. **Credential Security**
   - All auth configs read-only mounts
   - Socket-based credential proxy (no files in container)
   - GPG proxy for commit signing (keys stay on host)

5. **Reversibility**
   - Branch isolation pattern
   - Auto-commit/push preserves work
   - Git-based rollback available

## Risk Assessment

### ⚠️ Risks That Remain Possible (By Design)

| Risk Category | Current Status | Mitigation | Residual Risk |
|---------------|----------------|------------|---------------|
| **Destructive Changes (Container)** | Possible | Isolated to container + copied workspace | Low - easy cleanup |
| **Destructive Changes (Workspace)** | Possible | Branch isolation + git history | Low - reversible |
| **Data Exfiltration (Network)** | Possible in allow-all | Squid mode provides visibility | Medium - functional requirement |
| **Lateral Movement** | Possible with read tokens | Read-only mounts, scoped tokens | Low - tokens already scoped |
| **Persistence (Repo)** | Possible | Review before merge, branch isolation | Medium - requires review |
| **Container Escape** | Blocked | Multiple layers of isolation | **Very Low** |
| **Host Tampering** | Blocked | No host mounts outside workspace | **Very Low** |

### ✅ Risks That Are Structurally Blocked

- **Direct host filesystem modification** - Blocked by container boundary
- **Docker socket access** - Not mounted
- **Privileged container operations** - no-new-privileges enforced
- **Permanent host system changes** - Ephemeral containers
- **Credential modification** - Read-only mounts

## Recommended "Safe-Unrestricted" Profile

For minimal prompts with strong safety:

```bash
launch-agent copilot \
  --network-proxy squid \
  --cpu 4 \
  --memory 8g \
  --no-push  # Or allow auto-push with review workflow
```

**Key Properties:**
1. No prompts for file operations (confined to workspace)
2. No prompts for command execution (within container)
3. No prompts for network requests (logged via squid)
4. Optional prompt for git push to origin (not local)
5. Container escape structurally impossible

## Gaps Identified

### Critical Gaps

1. **Inconsistent Capability Dropping**
   - PowerShell: `--cap-drop=ALL` ✅
   - Bash: Missing capability drop ❌
   - **Fix Required:** Add `--cap-drop=ALL` to bash launcher

2. **Missing Seccomp Profile**
   - No seccomp policy currently applied
   - **Recommendation:** Add restrictive seccomp profile

3. **Docker Socket Risk (Theoretical)**
   - Currently not mounted (good)
   - **Recommendation:** Explicitly document as forbidden

### Minor Gaps

4. **Tool Classification System**
   - No formal tiering of operations by risk
   - **Recommendation:** Implement tool danger matrix

5. **Network Allowlist Customization**
   - Squid allowlist is reasonable but hard-coded
   - **Recommendation:** Make easily customizable

6. **Audit Logging**
   - Squid logs HTTP/HTTPS
   - No unified audit trail for all operations
   - **Recommendation:** Add structured logging layer

## Implementation Priority

### Phase 1: Critical Fixes (Immediate)
1. Add `--cap-drop=ALL` to bash launcher (parity with PowerShell)
2. Document no-docker-socket policy explicitly
3. Add seccomp profile option

### Phase 2: Enhanced Safety (Short-term)
4. Implement tool danger matrix
5. Add customizable network allowlists
6. Create safe abstraction wrappers

### Phase 3: Operational Improvements (Medium-term)
7. Add unified audit logging
8. Implement automated attack detection
9. Create safe-unrestricted preset profiles

## Answer to Core Question

> **"How close can we get to 'click once to enable unrestricted mode and just let it work' without making catastrophe easy?"**

**Answer:** We can get **very close**. The current architecture already provides:

1. ✅ **No host escape** - Structurally impossible with current design
2. ✅ **Bounded damage** - Limited to container and workspace copy
3. ✅ **Reversible changes** - Git-based, branch-isolated
4. ✅ **Observable behavior** - Squid logs, container logs
5. ✅ **Clean isolation** - Ephemeral containers, no host pollution

**With the recommended fixes:**
- Add `--cap-drop=ALL` to bash launcher (critical)
- Add seccomp profile (important)
- Implement tool tiering (nice-to-have)

**We can confidently support unrestricted mode with zero prompts for:**
- File operations in workspace
- Command execution in container
- Network requests (with squid logging)
- Package installations
- Build operations

**And minimal prompts only for:**
- Git push to origin remote (optional)
- Explicit user-invoked destructive operations (if implemented)

## Conclusion

The CodingAgents architecture is **already well-designed for safe unrestricted operation**. The workspace-copy model, read-only auth mounts, and lack of docker socket access create strong isolation. With minor fixes (capability drop parity, seccomp), it becomes an exemplar of safe-by-design agent infrastructure.

The key insight: **Structural safety through isolation is far superior to behavioral safety through prompts.** This system gets it right.

## Document Structure

This analysis is organized into the following documents:

1. `00-executive-summary.md` (this document)
2. `01-current-architecture.md` - Detailed analysis of current implementation
3. `02-threat-model.md` - Prompt-injection-focused threat analysis
4. `03-tool-danger-matrix.md` - Risk classification of all tools and operations
5. `04-hardened-architecture.md` - Proposed enhancements and architecture
6. `05-implementation-roadmap.md` - Concrete steps to implement recommendations
7. `06-attack-scenarios.md` - Example attack chains and mitigations
8. `07-safe-unrestricted-profile.md` - Default configuration for unrestricted mode

**Next:** See `01-current-architecture.md` for detailed analysis of the existing system.
