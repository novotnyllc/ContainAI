# Option A: CLI Wrapping with Filtering

## Overview

Evaluate using `@devcontainers/cli` as the parsing layer, filtering its output before container creation. The CLI provides `read-configuration` to parse devcontainer.json and merge configurations, which ContainAI could intercept and filter before launching containers.

## CLI-Inside-Sysbox Feasibility Assessment

### Preferred Approach: CLI Running Inside Sysbox Container

**Verdict: FEASIBLE with caveats**

The @devcontainers/cli can run inside a Sysbox system container, communicating with the nested Docker daemon (DinD) to create devcontainers. This keeps Node.js dependencies isolated from the host.

**Requirements:**
1. Node.js 20+ runtime inside Sysbox container (adds ~150-200MB including npm modules)
2. Python3 and build-essential for npm native module compilation
3. Docker CLI configured to talk to inner DinD daemon
4. `DOCKER_HOST` pointing to DinD socket (e.g., `unix:///var/run/docker.sock`)

**Dockerfile snippet for CLI installation:**
```dockerfile
FROM node:20-slim
RUN apt-get update && apt-get install -y python3 build-essential && rm -rf /var/lib/apt/lists/*
RUN npm install -g @devcontainers/cli
```

**Architecture:**
```
┌─────────────────────────────────────────────────────────┐
│ Host (user's machine)                                   │
│  └─ Docker with Sysbox runtime                          │
│      └─ Sysbox System Container (ContainAI outer)       │
│          ├─ SSH daemon (sshd)                           │
│          ├─ systemd (PID 1)                             │
│          ├─ Node.js + @devcontainers/cli               │
│          └─ DinD Docker daemon                          │
│              └─ Devcontainer (nested)                   │
└─────────────────────────────────────────────────────────┘
```

### Fallback: CLI on Host (NOT recommended)

Installing @devcontainers/cli on the host would:
- Add Node.js as a host dependency
- Require Python3 + C++ compiler for native modules
- Mix ContainAI's shell-based approach with npm toolchain
- Create security boundary confusion (CLI runs on true host)

**Recommendation:** Reject host installation. The CLI-inside-Sysbox approach maintains ContainAI's isolation model.

---

## CLI Output Format Analysis

### `read-configuration` Command

**Options (key subset):**
- `--workspace-folder <path>` - Path to workspace
- `--config <path>` - Explicit devcontainer.json path
- `--include-features-configuration` - Include resolved features
- `--include-merged-configuration` - Include base+image merged config
- `--log-format json|text` - Output format
- `--log-level info|debug|trace` - Verbosity

**Output Structure:**
```json
{
  "configuration": {
    // Parsed devcontainer.json with variable substitution applied
    "name": "My Container",
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": { ... },
    "runArgs": [ ... ],
    // ... all other properties
  },
  "workspace": {
    "workspaceFolder": "/workspaces/project",
    "workspaceMount": "..."
  },
  "featuresConfiguration": {
    // Resolved feature metadata (if --include-features-configuration)
  },
  "mergedConfiguration": {
    // Base config + image metadata merged (if --include-merged-configuration)
  }
}
```

**Known Issue:** Logs may be written to stdout instead of stderr (GitHub issue #873), requiring parsing to extract clean JSON. Workaround: parse last JSON object from output, or use `jq` to extract `.configuration`.

---

## Security-Sensitive Fields in CLI Output

Based on the security classification from fn-13-1c7.1, these fields in CLI output require filtering:

### BLOCKED (must reject if present)
| Field | Risk | Action |
|-------|------|--------|
| `initializeCommand` | Executes outside devcontainer (in CLI host: Sysbox if CLI-inside-Sysbox, or true host otherwise) | Hard error before any container action |
| `privileged` | Full container escape | Reject devcontainer.json |

### FILTERED (must sanitize)
| Field | Risk | Filtering Strategy |
|-------|------|---------------------|
| `runArgs` | Can include `--privileged`, `-v /:/host` | Parse args, apply blocklist |
| `capAdd` | Dangerous capabilities (SYS_ADMIN, etc.) | Allowlist only SYS_PTRACE |
| `securityOpt` | `seccomp=unconfined`, `apparmor=unconfined` | Allowlist known-safe options |
| `mounts` | Arbitrary host path access | Validate paths, reject host-root mounts |
| `workspaceMount` | Mount source validation | Ensure within allowed directories |
| `features` | Supply-chain risk (install.sh as root) | Allowlist official features only |
| `build.options` | Can pass `--network=host`, etc. | Parse and filter build args |

### WARN (log but allow)
| Field | Risk | Action |
|-------|------|--------|
| `onCreateCommand`, `postCreateCommand`, etc. | Arbitrary code in container | Log for audit trail |
| `image` | Supply-chain (arbitrary images) | Log image reference + digest |
| `containerEnv`, `remoteEnv` | May override security env vars | Log, define precedence |

---

## Filtering Feasibility

### Approach: Filter `read-configuration` Output

**Workflow:**
1. Run `devcontainer read-configuration --workspace-folder /path --include-merged-configuration`
2. Parse JSON output (handle log noise)
3. Apply security policy:
   - Check for BLOCKED fields → error if present
   - Sanitize FILTERED fields → modify or remove
   - Log WARN fields → emit warnings
4. **Critical decision point**: What to do with filtered config?

### The Interception Problem

**Key Question:** Can we use filtered config to launch the container?

**Option 1: Pass filtered config to `devcontainer up`**
- Problem: `devcontainer up` re-reads devcontainer.json from disk
- No way to pass in-memory config to the CLI
- Workaround: Write filtered config to temp file, use `--config` to point to it
- Limitation: Original file may contain `extends` or relative paths that break

**Option 2: Use CLI only for parsing, launch manually**
- Parse with `read-configuration --include-merged-configuration`
- Extract Docker run parameters from merged config
- Execute `docker run` directly in DinD
- Problem: Loses feature installation, lifecycle command execution
- Would need to reimplement feature installation logic

**Option 3: Modify devcontainer.json in-place (NOT recommended)**
- Mutate user's file before CLI invocation
- Restore after
- Race conditions, potential data loss
- Violates principle of not modifying user files

**Recommendation:** Start with Option 1 (temp file) for faster implementation, migrate to Option 2 (manual launch) if tighter security control is needed. Option 1 is pragmatic for initial release; Option 2 provides maximum control.

---

## Build Handling Analysis

### Where Does Image Build Execute?

With CLI-inside-Sysbox approach:

| Scenario | Build Location | Security Level |
|----------|---------------|----------------|
| `devcontainer up` inside Sysbox | DinD daemon (nested) | Best - already sandboxed |
| `devcontainer build` inside Sysbox | DinD daemon (nested) | Best |
| Feature installation | Inside build (DinD) | Already sandboxed |

**Key insight:** Because the CLI runs inside Sysbox and talks to the nested DinD daemon, ALL build operations happen within the sandbox. This is a significant security advantage over running CLI on host.

### Feature Allowlist Enforcement

**Challenge:** The CLI handles feature installation internally during `devcontainer up`. ContainAI cannot intercept individual feature installs.

**Options:**
1. **Pre-filter features in config:** Remove non-allowlisted features from parsed config before passing to CLI
2. **Post-build verification:** Inspect built image layers for unexpected additions
3. **Allow all, audit:** Log all features, accept supply-chain risk for convenience

**Recommended:** Pre-filter features against allowlist of official `ghcr.io/devcontainers/features/*`

### Supply-Chain Exposure During Build

| Component | Exposure | Mitigation |
|-----------|----------|------------|
| Base images | Network fetch inside sandbox | Already sandboxed, log digests |
| Features | HTTPS fetch during build | Allowlist, log sources |
| .git directory | May be in build context | No special risk (already exposed to devcontainer) |
| Tokens/credentials | In env during build | ContainAI doesn't inject secrets; user-provided |
| Network | Full outbound from DinD | Expected per threat model |

---

## Node.js Dependency Implications

### Impact on Shell-Based ContainAI

| Aspect | Impact | Severity |
|--------|--------|----------|
| Image size | +150-200MB (Node.js + npm modules) | Medium |
| Build time | +30-60s for npm install | Low |
| Maintenance | Node.js security updates needed | Medium |
| Complexity | Mixed shell + Node.js debugging | Medium |
| User perception | "Why does container tool need Node?" | Low |

### Alternatives to Node.js Dependency

1. **Statically compiled CLI:** Not available (TypeScript/Node.js only)
2. **Go port of CLI:** Does not exist
3. **Parse JSON directly:** Loses feature resolution, variable substitution
4. **DevPod (Go):** Alternative tool, different approach (see option-devpod.md)

**Verdict:** Node.js dependency is acceptable given CLI-inside-Sysbox model. The dependency is contained within the sandbox, not exposed to host.

---

## Pros and Cons vs Direct Parsing

### Pros of CLI Wrapping

| Benefit | Explanation |
|---------|-------------|
| Spec compliance | CLI implements full devcontainer spec including edge cases |
| Variable substitution | `${localWorkspaceFolder}`, `${containerEnv:VAR}` handled |
| Feature resolution | Official feature installation logic |
| Configuration merging | Base config + image metadata merged correctly |
| Maintenance | Spec updates handled by CLI maintainers |
| Compose support | Multi-container via Docker Compose |
| Extends support | Configuration inheritance |

### Cons of CLI Wrapping

| Drawback | Explanation |
|----------|-------------|
| Filtering complexity | Must parse output, rewrite config, handle edge cases |
| Interception gap | Can't fully intercept between parse and launch |
| Node.js dependency | 150-200MB added to system container |
| Black-box behavior | CLI may do unexpected things during `up` |
| Log noise | Output format issues (logs mixed with JSON) |
| `initializeCommand` | CLI may execute before we can block (during `up`) |
| Re-read problem | `devcontainer up` re-reads original file |

### Risk: initializeCommand Execution

**Critical:** `devcontainer up` may execute `initializeCommand` BEFORE returning control. This runs on the "host" of wherever the CLI runs:
- If CLI on true host → runs on user's machine (DANGEROUS)
- If CLI inside Sysbox → runs inside Sysbox container (acceptable)

**Mitigation:** CLI-inside-Sysbox model means even if CLI executes initializeCommand, it's already sandboxed. Still should block configs with initializeCommand for clarity.

---

## Recommendation

### Viability: MODERATE

CLI wrapping is viable but has significant complexity:

**Strengths:**
- Full spec compliance without reimplementing parser
- Build operations sandboxed inside Sysbox DinD
- Feature installation handled by CLI

**Weaknesses:**
- Cannot cleanly intercept between parse and launch
- Must use workarounds (temp config file, manual docker run)
- Node.js dependency adds image bloat

### Preferred Implementation Path

If CLI wrapping is chosen, use a **phased approach**:

**Phase 1 (Option 1 - temp file, faster to ship):**
1. **Install CLI inside Sysbox system container** (not on host)
2. **Use `read-configuration` for parsing**
3. **Apply security policy to parsed output**
4. **Write sanitized config to temp file**
5. **Call `devcontainer up --config <temp-file>`**
6. **Block configs with `initializeCommand`** (defense in depth)
7. **Pre-filter features** against allowlist
8. **Log all WARN-level fields** for audit

**Phase 2 (Option 2 - manual launch, tighter control, optional):**
- Replace step 5 with direct `docker run` invocation in DinD
- Reimplement feature installation if needed
- Provides full control over container creation

### Comparison Summary

| Criterion | CLI Wrapping | Direct Parsing |
|-----------|--------------|----------------|
| Spec compliance | Full | Partial (no extends, limited features) |
| Security control | Moderate (workarounds needed) | High (full control) |
| Implementation | Medium | High |
| Maintenance | Low (CLI updates) | High (spec tracking) |
| Dependencies | Node.js | None (pure shell) |
| Image size | +150-200MB | +0 |

**Overall:** CLI wrapping is a viable middle-ground. Consider hybrid approach: CLI for parsing, manual Docker commands for launch (see Option E in spec).

---

## References

- [@devcontainers/cli repository](https://github.com/devcontainers/cli)
- [CLI output format issue #873](https://github.com/devcontainers/cli/issues/873)
- [devcontainer.json schema](https://containers.dev/implementors/json_schema/)
- [Docker-in-Docker security considerations](https://some-natalie.dev/blog/devcontainer-docker-in-docker/)
- [docker-in-docker feature](https://github.com/devcontainers/features/tree/main/src/docker-in-docker)
