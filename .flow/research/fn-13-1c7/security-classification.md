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
| `privileged` | **BLOCKED** | Sandbox-host | Reject with error | `--privileged` grants nearly full host capabilities. Enforced by sandbox-host Docker daemon when launching devcontainer. Defeats container isolation entirely. |
| `capAdd` | **FILTERED** | Sandbox-host | Allowlist only | Capabilities are applied by sandbox-host Docker daemon. Some are safe (e.g., SYS_PTRACE for debugging). Block dangerous ones (SYS_ADMIN, NET_ADMIN, etc.). |
| `securityOpt` | **FILTERED** | Sandbox-host | Allowlist only | Security options enforced by sandbox-host Docker daemon. `seccomp=unconfined` is dangerous. Allow only known-safe options. Block `apparmor=unconfined`, `seccomp=unconfined`. Require `no-new-privileges` (enabled form). |
| `runArgs` | **FILTERED** | Sandbox-host | Parse and filter | Args passed to sandbox-host Docker daemon. Can include `--privileged`, `--cap-add`, `-v /:/host`. Parse args and block dangerous flags. |
| `init` | **SAFE** | Sandbox-host | Pass through | `--init` uses tini for zombie reaping. No security impact. |
| `overrideCommand` | **SAFE** | Sandbox-host | Pass through | Boolean controlling whether to override image CMD. No direct security impact. |
| `shutdownAction` | **SAFE** | N/A | Pass through | Controls what happens on disconnect (none/stopContainer/stopCompose). |

**Note on Execution Scope:** Runtime options (`privileged`, `capAdd`, `securityOpt`, `runArgs`, `init`, `overrideCommand`) are enforced by the Docker daemon running inside the Sysbox container (sandbox-host), not inside the devcontainer itself. This distinction matters: sandbox-host is already isolated by Sysbox, providing one layer of defense even if these options are misused.

**Capability Allowlist (suggested):**
- SAFE: `SYS_PTRACE` (debugging - needed for strace/gdb)
- RISKY (only if explicitly required): `NET_RAW` (raw sockets for ping - higher risk in sandbox models), `SETPCAP`, `SETFCAP` (capability manipulation - high-leverage)
- BLOCKED: `SYS_ADMIN`, `NET_ADMIN`, `SYS_RAWIO`, `SYS_MODULE`, `DAC_READ_SEARCH`, `MKNOD`

**Note:** Strict mode should default to an empty capability allowlist. Only add capabilities when explicitly required by the devcontainer and reviewed for security implications.

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
| `mounts` | **FILTERED** | Sandbox-host | Validate paths | Mount options passed to sandbox-host Docker daemon. Can mount arbitrary paths within sandbox. Must validate: no sensitive paths. Allow workspace-relative and named volumes only. |
| `workspaceMount` | **FILTERED** | Sandbox-host | Remap to cai paths | Workspace mount handled by sandbox-host Docker daemon. Must validate source path is within allowed directories. |
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
| `dockerComposeFile` | **WARN** | Devcontainer (runtime) | Allow with log | Multi-container support. Primarily affects runtime composition (services, mounts, networks), not just build. Complex attack surface. Log for audit. |
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

| Category | Properties |
|----------|------------|
| **BLOCKED** | `initializeCommand`, `privileged` |
| **FILTERED** | `capAdd`, `securityOpt`, `runArgs`, `mounts`, `workspaceMount`, `build`, `build.options`, `features`, `remoteUser`, `containerUser`, `forwardPorts`, `appPort` |
| **WARN** | `onCreateCommand`, `updateContentCommand`, `postCreateCommand`, `postStartCommand`, `postAttachCommand`, `image`, `build.args`, `dockerComposeFile`, `containerEnv`, `remoteEnv` |
| **SAFE** | All others (metadata, paths, booleans, enums) |

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

---

## Appendix: Complete Property Enumeration

All root properties from `devContainer.base.schema.json` (commit `1b2baddb5f1071ca0e8bcb7eb56dbc9d3e4a674f`):

### devContainerCommon Properties

| Property | Category | Scope | Default Action | Notes |
|----------|----------|-------|----------------|-------|
| `$schema` | SAFE | N/A | Ignore | Schema URI reference |
| `name` | SAFE | N/A | Pass through | Display name |
| `features` | FILTERED | Build-time | Allowlist/audit | Feature installation |
| `overrideFeatureInstallOrder` | SAFE | N/A | Pass through | Install order array |
| `secrets` | SAFE | N/A | Pass through | Secret recommendations (metadata only) |
| `forwardPorts` | FILTERED | Devcontainer | Merge | Port forwarding |
| `portsAttributes` | SAFE | N/A | Pass through | Port metadata |
| `otherPortsAttributes` | SAFE | N/A | Pass through | Default port attributes |
| `updateRemoteUserUID` | SAFE | Devcontainer | Pass through | UID sync boolean |
| `containerEnv` | WARN | Devcontainer | Merge | Container environment |
| `containerUser` | FILTERED | Devcontainer | Remap | Container start user |
| `mounts` | FILTERED | Sandbox-host | Validate | Mount definitions |
| `init` | SAFE | Sandbox-host | Pass through | --init flag |
| `privileged` | BLOCKED | Sandbox-host | Reject | --privileged flag |
| `capAdd` | FILTERED | Sandbox-host | Allowlist | Capability additions |
| `securityOpt` | FILTERED | Sandbox-host | Allowlist | Security options |
| `remoteEnv` | WARN | Devcontainer | Merge | Remote process env |
| `remoteUser` | FILTERED | Devcontainer | Remap | Remote process user |
| `initializeCommand` | BLOCKED | Host-machine | Reject | Pre-container host command |
| `onCreateCommand` | WARN | Devcontainer | Log | Container creation hook |
| `updateContentCommand` | WARN | Devcontainer | Log | Content update hook |
| `postCreateCommand` | WARN | Devcontainer | Log | Post-create hook |
| `postStartCommand` | WARN | Devcontainer | Log | Post-start hook |
| `postAttachCommand` | WARN | Devcontainer | Log | Post-attach hook |
| `waitFor` | SAFE | N/A | Pass through | Wait-for enum |
| `userEnvProbe` | SAFE | Devcontainer | Pass through | Shell profile probe |
| `hostRequirements` | SAFE | N/A | Pass through | Host resource requirements |
| `customizations` | SAFE | N/A | Pass through | Tool-specific settings |

### nonComposeBase Properties (image/Dockerfile mode)

| Property | Category | Scope | Default Action | Notes |
|----------|----------|-------|----------------|-------|
| `appPort` | FILTERED | Devcontainer | Merge | Application ports |
| `runArgs` | FILTERED | Sandbox-host | Filter | Docker run arguments |
| `shutdownAction` | SAFE | N/A | Pass through | Disconnect behavior |
| `overrideCommand` | SAFE | Sandbox-host | Pass through | Override CMD boolean |
| `workspaceFolder` | SAFE | N/A | Remap | Container workspace path |
| `workspaceMount` | FILTERED | Sandbox-host | Validate | Workspace mount string |

### dockerfileContainer Properties

| Property | Category | Scope | Default Action | Notes |
|----------|----------|-------|----------------|-------|
| `build` | FILTERED | Build-time | Validate | Build config object |
| `build.dockerfile` | SAFE | Build-time | Pass through | Dockerfile path |
| `build.context` | SAFE | Build-time | Pass through | Build context path |
| `build.target` | SAFE | Build-time | Pass through | Multi-stage target |
| `build.args` | WARN | Build-time | Log | Build arguments |
| `build.cacheFrom` | SAFE | Build-time | Pass through | Cache sources |
| `build.options` | FILTERED | Build-time | Filter | Additional build options |
| `dockerFile` | SAFE | Build-time | Pass through | Legacy Dockerfile path |
| `context` | SAFE | Build-time | Pass through | Legacy context path |

### imageContainer Properties

| Property | Category | Scope | Default Action | Notes |
|----------|----------|-------|----------------|-------|
| `image` | WARN | Build-time | Log | Base image reference |

### composeContainer Properties

| Property | Category | Scope | Default Action | Notes |
|----------|----------|-------|----------------|-------|
| `dockerComposeFile` | WARN | Devcontainer | Log | Compose file(s) |
| `service` | SAFE | N/A | Pass through | Primary service name |
| `runServices` | SAFE | N/A | Pass through | Services to start |
| `workspaceFolder` | SAFE | N/A | Remap | Container workspace path |
| `shutdownAction` | SAFE | N/A | Pass through | Disconnect behavior |
| `overrideCommand` | SAFE | Sandbox-host | Pass through | Override CMD boolean |

### VS Code Extension Properties

| Property | Category | Scope | Default Action | Notes |
|----------|----------|-------|----------------|-------|
| `customizations.vscode.extensions` | SAFE | Devcontainer | Pass through | Extension IDs |
| `customizations.vscode.settings` | SAFE | Devcontainer | Pass through | VS Code settings |
| `customizations.vscode.devPort` | SAFE | Devcontainer | Pass through | Backend port |
| `extensions` (deprecated) | SAFE | Devcontainer | Pass through | Legacy extensions |
| `settings` (deprecated) | SAFE | Devcontainer | Pass through | Legacy settings |
| `devPort` (deprecated) | SAFE | Devcontainer | Pass through | Legacy devPort |

### Codespaces Extension Properties

| Property | Category | Scope | Default Action | Notes |
|----------|----------|-------|----------------|-------|
| `customizations.codespaces.repositories` | SAFE | N/A | Ignore | Multi-repo permissions |
| `customizations.codespaces.openFiles` | SAFE | N/A | Ignore | Files to open |
| `customizations.codespaces.disableAutomaticConfiguration` | SAFE | N/A | Ignore | Auto-config disable |
| `codespaces` (deprecated) | SAFE | N/A | Ignore | Legacy codespaces config |

**Total properties enumerated:** 62 (including nested and deprecated)
