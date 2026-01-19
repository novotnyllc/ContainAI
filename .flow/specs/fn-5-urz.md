# ContainAI Secure Sandboxed Agent Runtime

## Overview

Implement a secure CLI wrapper for running AI coding agents (Claude Code, Gemini CLI) in Docker Sandboxes with defense-in-depth isolation. The runtime enforces safe defaults (no host Docker socket, no host credentials) and provides an ECI-equivalent isolation path for users without Docker Business.

**Source PRD**: `.flow/specs/sysbox.md`

## Scope

### In Scope
- `containai doctor` - capability detection and remediation guidance
- `containai install secure-engine` - isolated Docker Engine setup (WSL/macOS)
- `containai run` - sandbox-first agent execution wrapper
- `containai sandbox reset` / `clear-credentials` - sandbox management
- Safe defaults with explicit unsafe opt-ins
- ECI detection and validation
- Secure Engine with Sysbox + userns-remap (where supported)
- TOML configuration (`.containai/config.toml`)

### Out of Scope
- Windows native (PowerShell) - WSL only
- Linux host support (defer to later)
- Docker-in-Docker as default (optional via `--enable-nested-docker`)
- Enterprise Settings Management integration

## Approach

### Phase 1: Core Infrastructure (Tasks 1-3)
1. Spike: Validate `docker sandbox` + `--context` interaction (blocker for Secure Engine)
2. Implement shell library structure (`containai.sh`, `lib/*.sh`)
3. TOML config parser (`parse-toml.py`)

### Phase 2: Doctor & Decision Engine (Tasks 4-6)
4. Docker Desktop + Sandboxes availability detection
5. ECI detection (uid_map + runtime check)
6. Decision engine + formatted output

### Phase 3: Sandbox Launcher (Tasks 7-9)
7. `containai run` with safe defaults
8. Context auto-selection (ECI vs Secure Engine)
9. Unsafe opt-ins with acknowledgements

### Phase 4: Secure Engine (Tasks 10-12)
10. WSL Secure Engine provisioning
11. macOS Lima VM provisioning
12. Runtime validation + integration tests

### Phase 5: Management Commands (Tasks 13-14)
13. `containai sandbox reset`
14. `containai sandbox clear-credentials`

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Sysbox does NOT support WSL2 officially | Secure Engine broken on Windows | Task 1 spike validates alternatives; may need to document as limitation |
| `docker sandbox` ignores `--context` | Secure Engine architecture invalid | Task 1 spike is blocking; if fails, fall back to ECI-only path |
| Docker Sandboxes API is experimental | Breaking changes possible | Pin to Docker Desktop 4.50+ behavior; add version checks |
| Lima + Sysbox on ARM64 untested | macOS Apple Silicon users blocked | Task 11 validates; document limitations if unsupported |

## Open Questions (from PRD + Gap Analysis)

1. **[CRITICAL]** Does `docker sandbox` respect `--context` / `DOCKER_CONTEXT`? (Task 1 spike)
2. **[CRITICAL]** What is WSL Secure Engine fallback given Sysbox WSL2 limitation?
3. Sysbox + userns-remap + daemon seccomp compatibility matrix?
4. Migration path from existing `asb` / `cai` commands?
5. Acknowledgement mechanism: CLI flag vs interactive prompt vs config?
6. Config precedence: repo-local vs user-global?

## Quick Commands

```bash
# After implementation, verify with:
containai doctor                          # Should detect Docker Desktop 4.50+, sandbox availability
containai run --agent claude --workspace . # Should run Claude in sandbox with safe defaults
docker inspect --format '{{.HostConfig.Runtime}}' <container>  # Should show sysbox-runc (ECI/Secure Engine)
```

## Acceptance Criteria

1. [ ] `containai doctor` detects Docker Desktop version, sandbox availability, and ECI status
2. [ ] `containai run` always uses `docker sandbox run` (never `docker run`)
3. [ ] Default runs have `--credentials=none` and no `--mount-docker-socket`
4. [ ] ECI detection validates uid_map + sysbox-runc runtime
5. [ ] Unsafe opt-ins require explicit acknowledgement flags
6. [ ] Secure Engine creates `containai-secure` context without modifying default context
7. [ ] `containai sandbox reset` removes sandbox for config changes to take effect
8. [ ] All shell functions use `local` for loop variables (per memory pitfall)
9. [ ] Uses `command -v` instead of `which` for portability (per memory convention)

## Test Strategy

- Unit tests: bash functions with mocked docker commands
- Integration tests: real Docker Desktop with sandbox feature enabled
- Platform tests: WSL2, macOS (Intel + Apple Silicon if supported)
- Security tests: verify no host socket/credential leakage in default runs

## References

- PRD: `.flow/specs/sysbox.md`
- Existing implementation: `agent-sandbox/aliases.sh` (ECI detection at lines 91-126, sandbox checks at lines 129-228)
- Docker Sandboxes: https://docs.docker.com/ai/sandboxes/
- Docker ECI: https://docs.docker.com/enterprise/security/hardened-desktop/enhanced-container-isolation/
- Sysbox: https://github.com/nestybox/sysbox
- Sysbox WSL2 issue: https://github.com/nestybox/sysbox/issues/32
- Lima: https://github.com/lima-vm/lima
