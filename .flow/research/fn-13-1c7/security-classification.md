# Devcontainer.json Security Classification for ContainAI

## Schema Source

**Repository:** https://github.com/devcontainers/spec
**Commit:** `1b2baddb5f1071ca0e8bcb7eb56dbc9d3e4a674f`
**Date:** 2024-01-22
**Files analyzed:**
- `schemas/devContainer.base.schema.json` (primary)
- `schemas/devContainer.schema.json` (references base + VS Code + Codespaces schemas)
- VS Code schema: `microsoft/vscode/.../devContainer.vscode.schema.json`
- Codespaces schema: `microsoft/vscode/.../devContainer.codespaces.schema.json`

## Security Categories

| Category | Definition | Enforcement | Default Action in cai |
|----------|------------|-------------|----------------------|
| **SAFE** | Property has no security implications | None | Pass through unchanged |
| **FILTERED** | Property needs sanitization (remove dangerous values) | Transform before use | Apply filter, use safe subset |
| **BLOCKED** | Property is inherently dangerous | Hard error | Reject with error message |
| **WARN** | Property may be risky but allowed | Log warning | Allow but log, suggest review |

## Execution Scope Definitions

| Scope | Description | Isolation Level |
|-------|-------------|-----------------|
| **Host-machine** | Runs on user's actual host machine | None - highest risk |
| **Sandbox-host** | Runs inside Sysbox container's "host" (outer container) | Sysbox isolation |
| **Devcontainer** | Runs inside the nested devcontainer (DinD) | Double isolation |
| **Build-time** | Executes during docker build | Varies by where build runs |
| **N/A** | No code execution, purely declarative | N/A |

---

## Property Classifications

### Lifecycle Commands

These properties execute arbitrary commands at various stages. The execution location is critical for security classification.

| Property | Category | Execution Scope | Default Action | Justification |
|----------|----------|-----------------|----------------|---------------|
| `initializeCommand` | **BLOCKED** | Host-machine | Reject with error | Runs on TRUE host before container creation. Cannot be sandboxed. Highest risk - arbitrary host code execution. |
| `onCreateCommand` | **WARN** | Devcontainer | Allow with log | Runs inside devcontainer after creation. Already isolated by Sysbox + DinD. Log for audit. |
| `updateContentCommand` | **WARN** | Devcontainer | Allow with log | Runs inside devcontainer. Same isolation as onCreateCommand. |
| `postCreateCommand` | **WARN** | Devcontainer | Allow with log | Runs inside devcontainer after onCreateCommand. |
| `postStartCommand` | **WARN** | Devcontainer | Allow with log | Runs inside devcontainer on every start. |
| `postAttachCommand` | **WARN** | Devcontainer | Allow with log | Runs inside devcontainer on attach. |
| `waitFor` | **SAFE** | N/A | Pass through | Enum controlling which command to wait for. No code execution. |

**Recommendation:** Block `initializeCommand` entirely. All other lifecycle commands run inside the devcontainer and are acceptable with logging since network exfil is an expected risk per SECURITY.md.

---

### Container Runtime Options

These properties control how the container is started and what capabilities it has.

| Property | Category | Execution Scope | Default Action | Justification |
|----------|----------|-----------------|----------------|---------------|
| `privileged` | **BLOCKED** | Devcontainer | Reject with error | `--privileged` grants nearly full host capabilities. Defeats container isolation entirely. |
| `capAdd` | **FILTERED** | Devcontainer | Allowlist only | Some capabilities are safe (e.g., SYS_PTRACE for debugging). Block dangerous ones (SYS_ADMIN, NET_ADMIN, etc.). |
| `securityOpt` | **FILTERED** | Devcontainer | Allowlist only | `seccomp=unconfined` is dangerous. Allow only known-safe options. Block apparmor=unconfined, no-new-privileges=false. |
| `runArgs` | **FILTERED** | Devcontainer | Parse and filter | Can include `--privileged`, `--cap-add`, `-v /:/host`. Parse args and block dangerous flags. |
| `init` | **SAFE** | Devcontainer | Pass through | `--init` uses tini for zombie reaping. No security impact. |
| `overrideCommand` | **SAFE** | Devcontainer | Pass through | Boolean controlling whether to override image CMD. No direct security impact. |
| `shutdownAction` | **SAFE** | N/A | Pass through | Controls what happens on disconnect (none/stopContainer/stopCompose). |

**Capability Allowlist (suggested):**
- SAFE: `SYS_PTRACE`, `NET_RAW` (for ping), `SETPCAP`, `SETFCAP`
- BLOCKED: `SYS_ADMIN`, `NET_ADMIN`, `SYS_RAWIO`, `SYS_MODULE`, `DAC_READ_SEARCH`, `MKNOD`

**runArgs Blocklist (suggested):**
- `--privileged`
- `--cap-add=SYS_ADMIN` (and other dangerous caps)
- `--security-opt=apparmor=unconfined`
- `--security-opt=seccomp=unconfined`
- `--pid=host`, `--network=host`, `--ipc=host`, `--uts=host`
- `-v /:/...`, `-v /etc:/...`, `-v /var/run/docker.sock:...` (host root/sensitive mounts)
- `--device=/dev/...` (except safe devices)

---

### Mount Configuration

| Property | Category | Execution Scope | Default Action | Justification |
|----------|----------|-----------------|----------------|---------------|
| `mounts` | **FILTERED** | Devcontainer | Validate paths | Can mount arbitrary host paths. Must validate: no `/`, `/etc`, `/var/run/docker.sock`, etc. Allow workspace-relative and named volumes only. |
| `workspaceMount` | **FILTERED** | Devcontainer | Remap to cai paths | Specifies workspace mount. Must validate source path is within allowed directories. |
| `workspaceFolder` | **SAFE** | N/A | Remap | Path inside container. No host impact. Remap to `/home/agent/workspace`. |

**Mount filtering rules:**
1. Reject bind mounts with absolute host paths outside workspace
2. Reject mounts targeting sensitive container paths (`/etc/shadow`, etc.)
3. Allow named volumes (no host path)
4. Allow workspace-relative paths (resolve and validate)
5. Reject paths containing `/../` traversal

---

### Build Configuration

| Property | Category | Execution Scope | Default Action | Justification |
|----------|----------|-----------------|----------------|---------------|
| `image` | **WARN** | Build-time | Allow with log | Pulls arbitrary image. Supply chain risk. Log image digest. |
| `build` | **FILTERED** | Build-time | Validate sub-properties | Contains dockerfile, context, args, options. |
| `build.dockerfile` / `dockerFile` | **SAFE** | Build-time | Pass through | Path to Dockerfile. Build runs inside Sysbox DinD. |
| `build.context` / `context` | **SAFE** | Build-time | Pass through | Build context path. Relative to devcontainer.json. |
| `build.target` | **SAFE** | Build-time | Pass through | Multi-stage build target. |
| `build.args` | **WARN** | Build-time | Allow with log | Build args can influence build. Log for audit. |
| `build.cacheFrom` | **SAFE** | Build-time | Pass through | Cache image references. |
| `build.options` | **FILTERED** | Build-time | Parse and filter | Additional build args. Block `--network=host`, `--security-opt`, etc. |
| `dockerComposeFile` | **WARN** | Build-time | Allow with log | Multi-container support. Complex attack surface. Log for audit. |
| `service` | **SAFE** | N/A | Pass through | Service name in compose file. |
| `runServices` | **SAFE** | N/A | Pass through | Array of service names. |

**Note:** If build runs inside Sysbox DinD, build-time risks are contained. If build runs on host, all build properties become higher risk.

---

### Features

Features are installable components that execute `install.sh` scripts during build.

| Property | Category | Execution Scope | Default Action | Justification |
|----------|----------|-----------------|----------------|---------------|
| `features` | **FILTERED** | Build-time | Allowlist or audit | Features run install.sh as root during build. Each feature is a potential supply chain attack. |
| `overrideFeatureInstallOrder` | **SAFE** | N/A | Pass through | Controls install order. No security impact. |

**Feature handling options:**
1. **Allowlist approach:** Only permit well-known features from `ghcr.io/devcontainers/features/*`
2. **Audit approach:** Allow all but log feature sources and hashes
3. **Block approach:** Reject all features (most restrictive)

**Recommendation:** Allowlist official features, WARN on third-party features, log all.

---

### User Configuration

| Property | Category | Execution Scope | Default Action | Justification |
|----------|----------|-----------------|----------------|---------------|
| `remoteUser` | **FILTERED** | Devcontainer | Remap to `agent` | User for processes inside container. ContainAI expects `agent` user. |
| `containerUser` | **FILTERED** | Devcontainer | Remap or warn | User the container starts with. May conflict with ContainAI model. |
| `updateRemoteUserUID` | **SAFE** | Devcontainer | Pass through or ignore | UID sync with host. May be ignored if using fixed UID. |

---

### Environment Variables

| Property | Category | Execution Scope | Default Action | Justification |
|----------|----------|-----------------|----------------|---------------|
| `containerEnv` | **WARN** | Devcontainer | Allow with merge | Environment for container. May override ContainAI env. Define precedence. |
| `remoteEnv` | **WARN** | Devcontainer | Allow with merge | Environment for remote processes. Same considerations. |
| `userEnvProbe` | **SAFE** | Devcontainer | Pass through | Controls shell profile sourcing. |

**Recommendation:** ContainAI env takes precedence over devcontainer env for security-critical variables.

---

### Port Configuration

| Property | Category | Execution Scope | Default Action | Justification |
|----------|----------|-----------------|----------------|---------------|
| `forwardPorts` | **FILTERED** | Devcontainer | Merge with cai ports | May conflict with ContainAI SSH ports (2300-2500). |
| `portsAttributes` | **SAFE** | N/A | Pass through | Port metadata (labels, auto-forward behavior). |
| `otherPortsAttributes` | **SAFE** | N/A | Pass through | Default port attributes. |
| `appPort` | **FILTERED** | Devcontainer | Merge with cai ports | Same as forwardPorts. |

**Port conflict resolution:** ContainAI SSH port takes precedence. Other ports can be forwarded.

---

### Metadata and Informational

| Property | Category | Execution Scope | Default Action | Justification |
|----------|----------|-----------------|----------------|---------------|
| `$schema` | **SAFE** | N/A | Ignore | Schema reference. |
| `name` | **SAFE** | N/A | Pass through | Display name. |
| `secrets` | **SAFE** | N/A | Pass through or ignore | Secret recommendations (not values). |
| `hostRequirements` | **SAFE** | N/A | Pass through or ignore | CPU/memory/GPU requirements. Advisory only. |
| `customizations` | **SAFE** | N/A | Pass through | Tool-specific settings (VS Code, etc.). |

---

### VS Code/Codespaces Specific

| Property | Category | Execution Scope | Default Action | Justification |
|----------|----------|-----------------|----------------|---------------|
| `customizations.vscode.extensions` | **SAFE** | Devcontainer | Pass through | VS Code extensions list. |
| `customizations.vscode.settings` | **SAFE** | Devcontainer | Pass through | VS Code settings. |
| `customizations.vscode.devPort` | **SAFE** | Devcontainer | Pass through or ignore | VS Code backend port. |
| `customizations.codespaces.repositories` | **SAFE** | N/A | Ignore | GitHub Codespaces multi-repo config. Not relevant to cai. |
| `customizations.codespaces.openFiles` | **SAFE** | N/A | Ignore | Files to open. Not relevant to cai. |
| `extensions` (deprecated) | **SAFE** | Devcontainer | Pass through | Legacy VS Code extensions. |
| `settings` (deprecated) | **SAFE** | Devcontainer | Pass through | Legacy VS Code settings. |

---

## Summary Tables

### Properties by Category

| Category | Count | Properties |
|----------|-------|------------|
| **BLOCKED** | 2 | `initializeCommand`, `privileged` |
| **FILTERED** | 11 | `capAdd`, `securityOpt`, `runArgs`, `mounts`, `workspaceMount`, `features`, `remoteUser`, `containerUser`, `forwardPorts`, `appPort`, `build.options` |
| **WARN** | 8 | `onCreateCommand`, `updateContentCommand`, `postCreateCommand`, `postStartCommand`, `postAttachCommand`, `image`, `containerEnv`, `remoteEnv`, `build.args`, `dockerComposeFile` |
| **SAFE** | 25+ | All others (metadata, paths, booleans, enums) |

### Critical Security Boundaries

| Boundary | Risk | Mitigation |
|----------|------|------------|
| Host code execution | `initializeCommand` runs on true host | Block entirely |
| Privilege escalation | `privileged`, `capAdd`, `securityOpt` | Block or allowlist |
| Sandbox escape | `mounts`, `runArgs` with host paths | Validate and filter |
| Supply chain | `features`, `image` | Allowlist or audit |

---

## Recommendations for Implementation

### Phase 1: Strict Mode (MVP)

Block or filter all dangerous properties. Maximize security at cost of compatibility.

```
BLOCKED: initializeCommand, privileged
FILTERED: capAdd (empty), securityOpt (empty), runArgs (empty), mounts (workspace only), features (official only)
WARN: All lifecycle commands logged
```

### Phase 2: Balanced Mode

Allow more properties with filtering and logging.

```
BLOCKED: initializeCommand, privileged
FILTERED: capAdd (allowlist), securityOpt (allowlist), runArgs (blocklist), mounts (validated), features (all with logging)
WARN: Lifecycle commands, third-party features, non-standard images
```

### Phase 3: Permissive Mode (Future)

For trusted environments, allow more flexibility.

```
BLOCKED: initializeCommand only
FILTERED: Minimal filtering
WARN: Extensive logging
```

---

## Open Questions for Follow-up Tasks

1. **Feature allowlist:** Which official features should be pre-approved?
2. **Build location:** Should devcontainer builds always run inside Sysbox DinD?
3. **User remapping:** How to handle devcontainers expecting `root` or specific non-`agent` users?
4. **Compose support:** Should multi-container devcontainers be supported in v1?
5. **initializeCommand workarounds:** Can we provide a safe alternative (run in sandbox-host)?
