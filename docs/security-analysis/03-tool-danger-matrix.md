# Tool Danger Matrix & Tiered Policy

## Purpose

This document classifies all tools and operations available to agents by risk level and defines a three-tier policy for prompt requirements.

## Tier Definitions

### Tier 1: Safe / Reversible (No Prompt)

**Characteristics:**
- Operations are confined to workspace
- Changes are reversible via git
- No network exfiltration risk (or logged)
- No credential access
- No privilege escalation risk

**User Experience:** Silent execution, no confirmation prompts

### Tier 2: Medium Risk (Logged / Rate-Limited)

**Characteristics:**
- Operations with moderate blast radius
- Network operations to allowlisted domains
- Package installations in container
- Higher resource usage
- May access credentials (read-only)

**User Experience:** Allowed but logged, possibly rate-limited, no prompt

### Tier 3: High Risk (Prompt Required or Blocked)

**Characteristics:**
- Operations with wide blast radius
- Irreversible or hard-to-reverse actions
- Push to origin (public repository)
- Access to container runtime
- Modification of host resources
- Attempts to weaken security

**User Experience:** Explicit user confirmation required, or blocked entirely

## Tool Danger Matrix

### File System Operations

| Tool/Action | Description | Destructive? | Reversible? | Tier | Rationale |
|-------------|-------------|--------------|-------------|------|-----------|
| `create_file` | Create new file in workspace | No | Yes (git) | 1 | Confined to workspace, git tracked |
| `edit_file` | Modify existing file | Yes | Yes (git) | 1 | Confined to workspace, git tracked |
| `delete_file` | Delete file in workspace | Yes | Yes (git) | 1 | Reversible via git history |
| `move_file` | Move/rename file | Yes | Yes (git) | 1 | Tracked by git |
| `chmod` | Change permissions | Yes | Yes | 1 | Confined to container |
| `read_file` | Read file contents | No | N/A | 1 | No side effects |
| `list_directory` | List files | No | N/A | 1 | No side effects |
| `create_directory` | Create directory | No | Yes (git) | 1 | Confined to workspace |
| `rm -rf /workspace/*` | Delete all workspace | Yes | Yes (git) | 1 | Reversible, container-only |
| `rm -rf /` | Delete container fs | Yes | Yes | 1 | Container only, ephemeral |
| Write to `/tmp` | Temp files | No | N/A | 1 | Ephemeral, container-only |
| Write to `~/.config` | Config files | Yes | No | 2 | Persists in container (ephemeral) |
| Write outside /workspace | System files | Yes | Maybe | 2 | Container only, may fail (readonly) |

**Assessment:** File operations are **Tier 1** - safe, reversible, workspace-confined.

### Command Execution

| Tool/Action | Description | Destructive? | Privileged? | Tier | Rationale |
|-------------|-------------|--------------|-------------|------|-----------|
| `bash -c "cmd"` | Execute shell command | Varies | No | 1-2 | Depends on command content |
| `python script.py` | Run Python script | Varies | No | 1-2 | Depends on script behavior |
| `npm install` | Install node packages | No | No | 2 | Downloads from network |
| `pip install` | Install python packages | No | No | 2 | Downloads from network |
| `dotnet build` | Build .NET project | No | No | 1 | No side effects |
| `make` | Run makefile | Varies | No | 1-2 | Depends on makefile content |
| `gcc` / `clang` | Compile code | No | No | 1 | No side effects |
| `apt install` | Install system packages | Yes | No | 2 | Container only, may fail (no sudo) |
| `sudo` | Elevate privileges | N/A | Yes | 3 | Blocked (not in sudoers) |
| `docker` | Control Docker | N/A | Yes | 3 | Blocked (socket not mounted) |
| Process fork bomb | Create many processes | Yes | No | 2 | Mitigated by --pids-limit |

**Assessment:** Most commands are **Tier 1-2**. Privileged operations are **Tier 3** (blocked).

### Git Operations

| Tool/Action | Description | Destructive? | Reversible? | Tier | Rationale |
|-------------|-------------|--------------|-------------|------|-----------|
| `git add` | Stage changes | No | Yes | 1 | Staging only, reversible |
| `git commit` | Commit changes | No | Yes (reflog) | 1 | Local commit, reversible |
| `git push local` | Push to host repo | Yes | Yes (reflog) | 1-2 | Syncs to host, visible |
| `git push origin` | Push to remote | Yes | Hard | 3 | Public, requires prompt |
| `git pull` | Pull changes | No | Yes | 1 | Read operation |
| `git fetch` | Fetch changes | No | N/A | 1 | Read operation |
| `git checkout` | Switch branch | No | Yes | 1 | Local operation |
| `git branch -D` | Delete branch | Yes | Hard | 2 | Local delete, recoverable |
| `git reset --hard` | Reset to commit | Yes | Yes (reflog) | 1 | Local, reversible |
| `git push --force` | Force push | Yes | Hard | 3 | Destructive, requires prompt |
| `git filter-branch` | Rewrite history | Yes | Hard | 3 | Very destructive |
| `git clean -fdx` | Delete untracked | Yes | No | 2 | Deletes work |

**Assessment:**
- Local git operations: **Tier 1**
- Push to local remote: **Tier 1-2** (visible, reversible)
- Push to origin: **Tier 3** (requires prompt)
- Force push / history rewrite: **Tier 3** (requires prompt)

### Network Operations

| Tool/Action | Description | Exfiltration? | Allowlisted? | Tier | Rationale |
|-------------|-------------|---------------|--------------|------|-----------|
| `curl http://npmjs.org` | HTTP request to allowed | Yes | Yes (squid) | 2 | Logged, functional need |
| `curl http://github.com` | HTTP to allowed | Yes | Yes (squid) | 2 | Logged, functional need |
| `curl http://evil.com` | HTTP to arbitrary | Yes | No | 2-3 | Blocked in squid, allowed in allow-all |
| `git clone <url>` | Clone repository | Read | Varies | 2 | Network read operation |
| `npm install <pkg>` | Download package | Read | Yes | 2 | Functional, logged |
| `wget` | Download file | Read | Varies | 2 | Functional, logged |
| DNS queries | Name resolution | Info leak | N/A | 2 | Minor info leak |
| `ssh user@host` | SSH to other system | Lateral | Varies | 3 | Lateral movement |
| Upload large data | Exfiltrate files | Yes | Varies | 3 | Obvious exfiltration |

**Assessment (by network mode):**
- **restricted mode:** All network operations **blocked**
- **squid mode:** Allowlisted domains **Tier 2** (logged), others **Tier 3** (blocked)
- **allow-all mode:** Most operations **Tier 2**, obvious exfil **Tier 3** (if detectable)

### Credential & Secret Access

| Tool/Action | Description | Modifiable? | Exfiltratable? | Tier | Rationale |
|-------------|-------------|-------------|----------------|------|-----------|
| Read `~/.config/gh/` | Read GitHub CLI config | No | Yes | 2 | Read-only, functional need |
| Read `~/.gitconfig` | Read git config | No | Yes | 2 | Read-only, functional need |
| Read `~/.mcp-secrets.env` | Read MCP secrets | No | Yes | 2 | Read-only, functional need |
| Read `~/.git-credentials` | Read git credentials | No | Yes | 2 | Read-only, functional need |
| Write to credential files | Modify credentials | No | N/A | 3 | Blocked (read-only mount) |
| `gh auth login` | Authenticate | No | N/A | 3 | Blocked (interactive) |
| Use credential proxy | Git operations | No | No | 1 | Socket-based, mediated |

**Assessment:** 
- Reading credentials: **Tier 2** (functional requirement, logged)
- Modifying credentials: **Tier 3** (blocked)
- Using credentials for git: **Tier 1** (mediated by proxy)

### MCP Server Operations

| Tool/Action | Description | Network? | Exfiltration? | Tier | Rationale |
|-------------|-------------|----------|---------------|------|-----------|
| GitHub MCP: list repos | Read operation | Yes | No | 2 | Functional, logged |
| GitHub MCP: create issue | Write operation | Yes | Yes | 2 | Logged, limited exfil channel |
| GitHub MCP: create PR | Write operation | Yes | Maybe | 2 | Logged, visible |
| Playwright: navigate | Browse web | Yes | No | 2 | Functional, logged |
| Playwright: screenshot | Capture page | No | No | 1 | Local operation |
| Context7: search docs | Read docs | Yes | No | 2 | Functional, logged |
| Sequential-thinking | Planning | No | No | 1 | Local reasoning |
| Serena: read code | Navigate code | No | No | 1 | Local operation |
| Serena: write file | Modify code | No | No | 1 | Same as file operations |

**Assessment:** Most MCP operations are **Tier 1-2**. Network MCPs are **Tier 2** (logged).

### Container & System Operations

| Tool/Action | Description | Escalation? | Host Access? | Tier | Rationale |
|-------------|-------------|-------------|--------------|------|-----------|
| `id` | Show user info | No | No | 1 | Read-only |
| `ps` | List processes | No | No | 1 | Read-only |
| `mount` | List mounts | No | No | 1 | Read-only (info gathering) |
| `df` | Disk usage | No | No | 1 | Read-only |
| `kill <pid>` | Kill process | Maybe | No | 2 | Container-only |
| `kill -9 1` | Kill init | Maybe | No | 2 | Container-only, may fail |
| `mount /dev/sda1` | Mount device | Yes | Maybe | 3 | Blocked (no privileges) |
| `insmod kernel.ko` | Load kernel module | Yes | Yes | 3 | Blocked (no privileges) |
| Access docker socket | Control Docker | Yes | Yes | 3 | Blocked (not mounted) |
| `/proc/sys` writes | Modify kernel | Yes | Maybe | 3 | Blocked (no privileges) |
| Capability use | Use Linux caps | Yes | Maybe | 3 | Dropped in PowerShell |

**Assessment:**
- Read operations: **Tier 1**
- Container process management: **Tier 2**
- Privileged operations: **Tier 3** (blocked)

### Package Management

| Tool/Action | Description | Network? | Malicious? | Tier | Rationale |
|-------------|-------------|----------|------------|------|-----------|
| `npm install <pkg>` | Install node package | Yes | Maybe | 2 | Functional, dependency risk |
| `pip install <pkg>` | Install python package | Yes | Maybe | 2 | Functional, dependency risk |
| `dotnet add package` | Install .NET package | Yes | Maybe | 2 | Functional, dependency risk |
| `apt install <pkg>` | Install system package | Yes | Maybe | 2 | May fail (no sudo) |
| `npm install --global` | Global npm install | Yes | Maybe | 2 | Container-only, ephemeral |
| Install from custom URL | Install from URL | Yes | High | 3 | High risk |

**Assessment:** Standard package managers **Tier 2**. Custom sources **Tier 3**.

**Note:** We assume dependencies are not malicious (per threat model). If this assumption changes, all package operations would be Tier 3.

## Tiered Policy Summary

### Tier 1: No Prompt (Silent Allow)

**Scope:** Container-confined, workspace-scoped, reversible

**Operations:**
- ✅ File operations in `/workspace`
- ✅ Git local operations (add, commit, branch, checkout)
- ✅ Git push to `local` remote (host repository)
- ✅ Code compilation and builds
- ✅ Test execution
- ✅ Read-only system operations (ps, id, mount, df)
- ✅ MCP operations (local: Serena, Sequential-thinking)
- ✅ Credential use via socket proxy

**Rationale:** These operations are either reversible (git), container-confined (file ops), or read-only. No prompts needed.

### Tier 2: Logged / Rate-Limited (No Prompt)

**Scope:** Network operations, package installs, higher resource usage

**Operations:**
- ✅ HTTP/HTTPS to allowlisted domains (squid mode)
- ✅ Package installations (npm, pip, dotnet, apt)
- ✅ Clone/pull from remote repositories
- ✅ MCP operations requiring network (GitHub, Context7, etc.)
- ✅ Reading credential files (functional requirement)
- ✅ Process management within container
- ✅ High CPU/memory usage (within resource limits)

**Rationale:** These are functional requirements but carry risk. Logging provides visibility. No prompts, but rate limiting may apply.

**Logging Requirements:**
- HTTP requests logged by squid (in squid mode)
- Package installs logged to container stdout
- Credential file access could be monitored (future enhancement)

### Tier 3: Prompt or Block

**Scope:** Wide blast radius, irreversible, or privileged operations

**Operations Requiring Prompt:**
- ⚠️ `git push origin` (push to public remote)
- ⚠️ `git push --force` (force push to any remote)
- ⚠️ `git filter-branch` (history rewrite)
- ⚠️ Install from custom/untrusted sources
- ⚠️ Large uploads (potential data exfiltration)

**Operations Blocked Entirely:**
- ❌ Docker socket access (not mounted)
- ❌ Host filesystem writes (not mounted)
- ❌ Privilege escalation (no-new-privileges, non-root)
- ❌ Credential modification (read-only mounts)
- ❌ Container escape attempts (multiple barriers)
- ❌ Network access in `restricted` mode
- ❌ Non-allowlisted domains in `squid` mode

**Rationale:** Tier 3 operations either:
1. Have wide impact (push to origin), requiring user confirmation
2. Are security violations, blocked structurally

## Safe Abstraction Proposals

### 1. Safe File Writer

**Purpose:** Enforce workspace-only writes

```python
class SafeFileWriter:
    def __init__(self, workspace_root: str):
        self.workspace_root = Path(workspace_root).resolve()
    
    def write(self, path: str, content: str):
        target = (self.workspace_root / path).resolve()
        if not target.is_relative_to(self.workspace_root):
            raise SecurityError("Write outside workspace not allowed")
        target.write_text(content)
```

**Benefit:** Centralized enforcement, cannot bypass

### 2. Safe Command Executor

**Purpose:** Block obviously dangerous commands

```python
class SafeCommandExecutor:
    BLOCKED_COMMANDS = [
        'docker', 'podman',  # Container control
        'mount', 'umount',    # Filesystem control (write)
        'insmod', 'rmmod',    # Kernel modules
    ]
    
    TIER_3_COMMANDS = [
        'git push origin',
        'git push --force',
        'ssh',  # Lateral movement
    ]
    
    def execute(self, command: str):
        if any(cmd in command for cmd in self.BLOCKED_COMMANDS):
            raise SecurityError("Command blocked")
        if any(cmd in command for cmd in self.TIER_3_COMMANDS):
            if not self.prompt_user(f"Execute: {command}?"):
                raise SecurityError("User denied")
        return subprocess.run(command, shell=True)
```

**Benefit:** Defense in depth, catches prompt injection attempts

### 3. Safe Network Client

**Purpose:** Route through allowlist/proxy layer

```python
class SafeNetworkClient:
    def __init__(self, proxy_url: str, allowlist: List[str]):
        self.session = requests.Session()
        self.session.proxies = {'http': proxy_url, 'https': proxy_url}
        self.allowlist = allowlist
    
    def get(self, url: str):
        domain = urllib.parse.urlparse(url).netloc
        if not any(fnmatch(domain, pattern) for pattern in self.allowlist):
            raise SecurityError(f"Domain {domain} not allowlisted")
        return self.session.get(url)
```

**Benefit:** Enforcement in code, visible to agent tools

### 4. Safe Git Operations

**Purpose:** Differentiate local vs origin pushes

```python
class SafeGitOperations:
    def __init__(self, workspace: str):
        self.repo = git.Repo(workspace)
    
    def commit(self, message: str):
        # Tier 1: Always allowed
        self.repo.git.add('-A')
        self.repo.index.commit(message)
    
    def push_local(self, branch: str):
        # Tier 1: Push to host repository
        self.repo.git.push('local', branch)
    
    def push_origin(self, branch: str):
        # Tier 3: Requires prompt
        if not self.prompt_user(f"Push {branch} to origin?"):
            raise SecurityError("User denied push to origin")
        self.repo.git.push('origin', branch)
```

**Benefit:** Enforces review before public push

## Prompt Design Guidelines

When Tier 3 prompts are required:

### 1. Clear Action Description
```
⚠️  The agent wants to push branch 'copilot/feature-x' to origin (GitHub).

This will make changes publicly visible and create a pull request.
```

### 2. Show Context
```
Commits to be pushed:
- abc123: feat: Add authentication
- def456: fix: Handle edge case
- ghi789: refactor: Clean up code

Changed files:
- src/auth.py (+45, -12)
- tests/test_auth.py (+30, -0)
```

### 3. Risk Explanation
```
⚠️  Risk: Changes will be public and visible to your team
```

### 4. Simple Choice
```
Allow this push?
[Y]es  [N]o  [V]iew diff first
```

### 5. Remember Choice (Optional)
```
[ ] Remember for this session (no more prompts for git push)
```

## Anomaly Detection (Future Enhancement)

### Patterns That Should Trigger Alerts

**Tier 2 → Tier 3 Escalation:**

1. **Large Uploads:**
   - Multiple large POST requests in short time
   - Single request > 10MB
   - Encoded data in URL parameters

2. **Credential Abuse:**
   - Reading credential files followed by network request
   - Multiple credential file accesses
   - Accessing credentials for unrelated repositories

3. **MCP Abuse:**
   - Creating many GitHub issues rapidly
   - Issue/comment content is binary/encoded data
   - Unusual MCP operation patterns

4. **Repository Tampering:**
   - Modifications to `.git/` directory
   - Deletions of critical files (.gitignore, CI configs)
   - History rewrite operations

5. **Evasion Attempts:**
   - Encoding/obfuscation in commands
   - Process name changes
   - Unusual shell patterns

**Response:** Log alert, optionally prompt user, potentially block

## Implementation Notes

### Integration Points

1. **Agent Runtime:**
   - Wrap file operations with SafeFileWriter
   - Wrap subprocess calls with SafeCommandExecutor
   - Wrap network with SafeNetworkClient

2. **MCP Servers:**
   - MCP servers should use safe abstractions
   - Network MCPs route through SafeNetworkClient
   - Filesystem MCPs use SafeFileWriter

3. **Container Startup:**
   - Configure abstractions based on network mode
   - Set allowlists from launch parameters
   - Initialize logging/monitoring

4. **Monitoring:**
   - Structured logs for all Tier 2 operations
   - Alerts for suspicious patterns
   - Audit trail for forensics

## Conclusion

**Key Insight:** The tier system allows us to:
- Minimize prompts (Tier 1: no prompt)
- Maintain visibility (Tier 2: logged)
- Protect against disasters (Tier 3: prompt or block)

**Default for Unrestricted Mode:**
- Tier 1 operations: Silent (99% of operations)
- Tier 2 operations: Silent but logged
- Tier 3 operations: Prompt for dangerous, block for impossible

This provides a **"yes by default, no when it matters"** model that balances productivity with safety.

## Next Steps

See:
- `04-hardened-architecture.md` for implementation details
- `05-implementation-roadmap.md` for concrete changes needed
- `07-safe-unrestricted-profile.md` for default configuration
