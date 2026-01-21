# fn-10-vep Docker-in-Docker, Sysbox Integration & Distribution Overhaul

## Overview

Comprehensive enhancement of ContainAI to:
1. Enable Docker-in-Docker (DinD) capability inside containers with proper dockerd startup
2. Improve user-friendly distribution beyond git clone
3. Overhaul documentation (agent-sandbox README and main README)
4. Fix mermaid chart contrast issues
5. Update SECURITY.md to use GitHub's recommended vulnerability reporting patterns

## Problem Statement

**Docker-in-Docker Support:**
- Agents running inside the container currently cannot use Docker
- `dockerd` needs to be installed and auto-startable without systemd
- We're already in a sysbox container - just need to start dockerd (no --privileged needed)

**Distribution:**
- Currently requires git clone - not user-friendly
- Need installer script, brew formula, or similar

**Documentation:**
- agent-sandbox/README.md needs major updates
- Main README needs to explain value proposition better
- Mermaid charts have poor contrast (hard to read)
- SECURITY.md uses email - should use GitHub patterns

**Sync Map Gaps:**
- The sync map is defined in `_IMPORT_SYNC_MAP` in `agent-sandbox/lib/import.sh` and volumes in `agent-sandbox/entrypoint.sh`
- Potentially missing directories (templates, Cursor configs, etc.)
- Audit criteria: all template dirs referenced by installer/CLI must be included in `_IMPORT_SYNC_MAP`

## Scope

### In Scope

**Phase 0: Repository Restructure (DO FIRST)**

Target directory structure:
```
ContainAI/
├── VERSION                    # Single source of truth for version
├── src/                       # Renamed from agent-sandbox/
│   ├── Dockerfile            # Main Dockerfile (kept at src/ root for build context)
│   ├── Dockerfile.test       # Test Dockerfile
│   ├── containai.sh          # Main CLI entry point
│   ├── parse-toml.py         # TOML parsing helper (used by lib/config.sh)
│   ├── lib/                  # Shell library modules
│   │   ├── container.sh
│   │   ├── config.sh
│   │   ├── import.sh
│   │   └── ...
│   ├── scripts/              # Extracted helper scripts
│   │   ├── entrypoint.sh     # Main container entrypoint (dockerd + gosu)
│   │   └── test-dind.sh      # DinD verification script
│   ├── configs/              # Extracted config files
│   │   └── daemon.json       # Docker daemon configuration
│   └── README.md             # Includes deprecation banner for agent-sandbox users
├── tests/                     # Test suites
│   ├── unit/                 # Portable tests (run on GH Actions)
│   └── integration/          # Sysbox-required tests (self-hosted/manual)
├── install/                   # Distribution scripts
│   └── install.sh
├── .github/workflows/         # CI/CD
└── agent-sandbox -> src      # Symlink to src/ (deprecated)
```

- Create compatibility shim: `agent-sandbox/` as **symlink to `src/`**
  - Preserves exact historical commands: `docker build -f agent-sandbox/Dockerfile agent-sandbox/`
  - Preserves sourcing paths: `source agent-sandbox/containai.sh`
  - Preserves lib imports: `source agent-sandbox/lib/import.sh`
  - Build context works because symlink resolves to full `src/` directory
- Deprecation notice added to `src/README.md` for users arriving via old paths
- Deprecation timeline: `agent-sandbox/` symlink removed in v2.0
- **Scripts referencing `agent-sandbox/` MAY be updated** (exception to "don't touch scripts" rule for path updates only)
- Add VERSION file at repo root as single source of truth
- VERSION propagates to: git tags, image tags, `cai --version` output

**Phase 1: Dockerfile Cleanup & DinD Infrastructure**
- Clean up Dockerfiles: remove printf/heredoc hacks, use COPY
- Extract embedded configs/scripts to separate files
- Simplify Dockerfile.test (remove sysbox installation - we're already in sysbox)
- Configure dockerd startup for sysbox with proper lifecycle management (see Technical Details)

**Phase 2: Main Image DinD Support**
- Install Docker dependencies in Dockerfile:
  - `docker-ce`, `docker-ce-cli`, `containerd.io` (from Docker official repo)
  - `iptables`, `iproute2` (for full networking support)
  - `gosu` for privilege dropping
- Add entrypoint hook to auto-start dockerd when in sysbox container
- **Privilege model**: entrypoint runs as root, starts dockerd, then drops to `agent` user
  - Create `docker` group at build time, add `agent` user to it
  - Start dockerd with `--group docker` for socket access
  - Drop privileges with `exec gosu agent "$@"` after dockerd is ready
  - Validate `docker info` works as `agent` user before proceeding
- Sysbox detection strategy (precedence order):
  1. Explicit env override: `CAI_ENABLE_DIND=1` forces enable, `CAI_ENABLE_DIND=0` forces disable
  2. Check sysbox-specific indicators: `/proc/self/uid_map` shows user namespace remapping (sysbox/ECI signature)
  3. Attempt dockerd start with 10s timeout; on failure, log warning and continue without DinD
  - Note: May produce false positives in non-sysbox userns containers; worst case is a 10s delay + warning message. Acceptable tradeoff for simplicity.
- Configure inner containers to use runc via `/etc/docker/daemon.json`:
  ```json
  {"default-runtime": "runc", "runtimes": {"runc": {"path": "runc"}}}
  ```

**Phase 3: Distribution & Updates**
- Set up GitHub Container Registry (GHCR) publishing via GitHub Actions
- Pre-built multi-arch images (amd64, arm64) using `docker buildx`
- **Image visibility**: PUBLIC for v1.0 (no authentication required for pulls)
- Tag structure: `ghcr.io/${GITHUB_REPOSITORY}:VERSION` (parameterized in CI)
- **Update `_CONTAINAI_DEFAULT_REPO`** in `lib/container.sh` to `ghcr.io/clairernovotny/containai` (or use `${GITHUB_REPOSITORY}` at build time)
- Add `CAI_IMAGE_REPO` env override for custom registries
- Add `_containai_repo()` helper function to centralize repo resolution, used by all image resolution and validation checks (ancestor checks, image prefix validation)
- **Backward compatibility for container ownership checks**:
  - Add `_CONTAINAI_LEGACY_REPOS` array containing old repo prefixes (`docker/sandbox-templates`)
  - Update `_containai_is_our_image()` to check both current repo AND legacy repos
  - This ensures containers created with the old repo prefix are still recognized as "ours" (for --restart, stop-all, etc.)
  - Legacy repo list is checked in addition to current repo, not instead of
- **Packaging model**:
  - Install artifact is a standalone shell wrapper script (`cai`) installed on the host
  - Installer extracts CLI library files preserving directory structure:
    ```
    ~/.cai/
    ├── bin/cai              # Wrapper script
    ├── lib/
    │   ├── containai.sh     # Main CLI entry point
    │   ├── parse-toml.py    # TOML parsing helper
    │   └── lib/             # Library modules (matches src/lib/)
    │       ├── container.sh
    │       ├── config.sh
    │       ├── import.sh
    │       └── ...
    └── versions/            # Rollback storage
    ```
  - Wrapper script sources local `~/.cai/lib/containai.sh` for host-side commands
  - Host-side commands: `doctor`, `setup`, `import`, `export`, `update`, `--version`
  - Container-side commands: `cai run` (launches container with sourced functions)
  - Script includes embedded version and image reference
  - `cai --version` reads version from embedded variable in script
  - This is the **primary CLI** going forward; the sourced script in `src/` is for development/in-container use
- Installer script requirements:
  - Checksum verification (SHA256 in release artifacts)
  - Version pinning support: `install.sh --version 1.2.3`
  - Idempotent execution
  - Flags: `--version`, `--prefix /custom/path`, `--uninstall`
  - **PATH handling**: installer prints `export PATH="$HOME/.cai/bin:$PATH"` instructions and validates `cai` is on PATH after install; optionally appends to shell rc file with user confirmation
  - Future: artifact signing with cosign (out of scope for v1.0)
- `cai update` command:
  - Pulls latest container image tag (public, no login required)
  - Downloads updated wrapper script and lib files from release artifacts
  - Separate subcommands: `cai update check` (no changes) vs `cai update apply` (performs update)
  - Rollback: previous version stored at `~/.cai/versions/`

**Phase 4: Documentation Overhaul**
- Rewrite src/README.md (formerly agent-sandbox/README.md)
- Enhance main README.md with value proposition
- **Update usage/help strings** in `containai.sh` to reference `cai` command instead of `source agent-sandbox/containai.sh`
- Mermaid contrast fix strategy:
  - Use Mermaid `%%{init: {'theme': 'base', 'themeVariables': {...}}}%%` directive
  - Define reusable palette: dark backgrounds (#1a1a2e, #0f3460), light text (#ffffff, #e0e0e0)
  - Test on both GitHub light and dark mode rendering
- Add architecture diagrams

**Phase 5: Security Updates**
- Update SECURITY.md content for GitHub security advisory pattern (code change)
- Manual step (documented): Enable "Private vulnerability reporting" in repo Settings > Security
- Note: GitHub security advisory enablement is a repo setting, not a code change

**Phase 6: Comprehensive Testing**

Test tiers:
1. **Tier 1 (Portable)**: Unit tests, linting, config validation - run on GitHub-hosted runners
2. **Tier 2 (Sysbox-required)**: DinD integration tests - require self-hosted runner OR documented manual verification

- Create test suite for clean start w/o import, clean start with import
- Test AI agent doctor commands
- Audit sync map for missing directories
- Networking tests for DinD: image pull, DNS resolution, container with outbound network

### Out of Scope
- Windows native support (WSL2 only)
- Podman support
- GUI tools
- Homebrew formula (future, after v1.0)
- Artifact signing with cosign (future, after v1.0)

## Technical Details

### Runtime Model (Simplified)

```
Host with sysbox-runc installed (Docker Desktop ECI or standalone sysbox)
  └── Sysbox container (us - ContainAI)
        └── dockerd (can start natively, no --privileged needed)
              └── Inner containers (use runc, NOT nested sysbox)
```

**Key points:**
- We're ALREADY in a sysbox container (provided by Docker Desktop ECI or sysbox runtime)
- dockerd can start natively inside sysbox containers
- No --privileged flag needed
- Inner containers use regular runc (no deeper sysbox nesting) - enforced via daemon.json
- Network: inner containers use Docker bridge networking; iptables/NAT enabled by default

### dockerd Lifecycle Management

**IMPORTANT**: The new entrypoint must MERGE with existing entrypoint logic, not replace it. The current `entrypoint.sh` provides critical functionality:

1. **Volume structure initialization** (`ensure_volume_structure`) - creates required directories/files in `/mnt/agent-data` with proper permissions
2. **Security validations** - symlink traversal prevention (`verify_path_under_data_dir`, `reject_symlink`), secret file permissions (`safe_chmod`)
3. **Workspace symlink setup** - discovers mirrored workspace mount and creates `~/workspace` symlink
4. **Environment loading** - loads `.env` from data volume safely (no shell eval)

**Architecture**: The entrypoint will be structured as:
1. Run existing volume/workspace initialization (as agent user with sudo for ownership fixes)
2. **NEW**: If in sysbox/ECI, start dockerd (requires root, then drops back to agent)
3. Execute user's command

The dockerd lifecycle functions will be added to the existing entrypoint, not replace it:

```bash
#!/usr/bin/env bash
# src/scripts/entrypoint.sh
# MERGED entrypoint: existing volume/workspace logic + DinD support
set -euo pipefail

# ============================================================================
# EXISTING LOGIC PRESERVED (from current entrypoint.sh)
# ============================================================================
# - ensure_volume_structure() with security checks
# - _load_env_file() for safe .env loading
# - discover_mirrored_workspace() and workspace symlink setup
# - All helper functions: verify_path_under_data_dir, reject_symlink, etc.
# [This section is NOT replaced - the full existing entrypoint logic remains]

# ============================================================================
# NEW: DinD Support Functions
# ============================================================================

DOCKERD_PIDFILE=/var/run/dockerd.pid
DOCKERD_LOGFILE=/var/log/dockerd.log
DOCKERD_TIMEOUT=30

# Detection: check env override first, then sysbox-specific indicators
should_start_dind() {
    [[ "${CAI_ENABLE_DIND}" == "1" ]] && return 0
    [[ "${CAI_ENABLE_DIND}" == "0" ]] && return 1
    # Sysbox/ECI detection: check for user namespace remapping
    if [[ -f /proc/self/uid_map ]]; then
        local uid_map_lines=$(wc -l < /proc/self/uid_map)
        [[ $uid_map_lines -gt 1 ]] && return 0
        grep -qv "^[[:space:]]*0[[:space:]]*0" /proc/self/uid_map && return 0
    fi
    return 1
}

start_dockerd() {
    # Must run as root - will be called via run_as_root
    dockerd \
        --host=unix:///var/run/docker.sock \
        --pidfile="$DOCKERD_PIDFILE" \
        --group=docker \
        >> "$DOCKERD_LOGFILE" 2>&1 &

    local elapsed=0
    while [[ $elapsed -lt $DOCKERD_TIMEOUT ]]; do
        if docker info >/dev/null 2>&1; then
            log "dockerd started successfully (pid=$(cat $DOCKERD_PIDFILE))"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    # Fallback: minimal mode
    log "Warning: dockerd failed with full config, trying minimal mode..."
    [[ -f "$DOCKERD_PIDFILE" ]] && { kill "$(cat $DOCKERD_PIDFILE)" 2>/dev/null || true; rm -f "$DOCKERD_PIDFILE"; sleep 2; }

    dockerd \
        --host=unix:///var/run/docker.sock \
        --pidfile="$DOCKERD_PIDFILE" \
        --group=docker \
        --iptables=false \
        --ip-masq=false \
        >> "$DOCKERD_LOGFILE" 2>&1 &

    elapsed=0
    while [[ $elapsed -lt $DOCKERD_TIMEOUT ]]; do
        if docker info >/dev/null 2>&1; then
            log "Warning: dockerd started in minimal mode (networking limited)"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    log "Error: Failed to start dockerd. Check $DOCKERD_LOGFILE"
    return 1
}

# ============================================================================
# MODIFIED main() function
# ============================================================================
main() {
    # EXISTING: Volume structure and workspace setup (unchanged)
    ensure_volume_structure
    _load_env_file

    # EXISTING: Workspace discovery and symlink (unchanged)
    MIRRORED="$(discover_mirrored_workspace || true)"
    # ... [existing workspace validation and symlink logic] ...

    # NEW: Start dockerd if in sysbox environment (before exec)
    if should_start_dind; then
        run_as_root start_dockerd || log "Warning: DinD unavailable, continuing without Docker"
    fi

    # EXISTING: Continue with user's command (unchanged)
    exec "$@"
}

main "$@"
```

**Note**: The actual implementation will integrate DinD functions into the existing entrypoint.sh structure, preserving all existing code paths. The `run_as_root` helper already exists in the current entrypoint for sudo operations. The `docker` group membership and `gosu` are handled at Dockerfile build time (see Phase 2).

### daemon.json Configuration

Placed at `/etc/docker/daemon.json` to enforce runc for inner containers.
Note: `storage-driver` omitted to allow auto-detection based on environment:

```json
{
  "default-runtime": "runc",
  "runtimes": {
    "runc": {
      "path": "runc"
    }
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### Mermaid Contrast Fix

Use Mermaid init directive with themeVariables for maintainable styling:

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {
  'primaryColor': '#1a1a2e',
  'primaryTextColor': '#ffffff',
  'primaryBorderColor': '#16213e',
  'secondaryColor': '#0f3460',
  'tertiaryColor': '#1a1a2e',
  'lineColor': '#a0a0a0',
  'textColor': '#ffffff',
  'background': '#0d1117'
}}}%%
graph LR
    A[Step 1] --> B[Step 2]
    style A fill:#1a1a2e,stroke:#16213e,color:#fff
    style B fill:#0f3460,stroke:#16213e,color:#fff
```

Palette (tested on GitHub light/dark):
- Dark backgrounds: #1a1a2e (primary), #0f3460 (secondary)
- Light text: #ffffff (on dark bg)
- Accent: #e94560 (highlights)
- Lines: #a0a0a0 (neutral)

## Quick commands

```bash
# Start dockerd in current sysbox container (full networking)
sudo dockerd &
sleep 5

# Verify dockerd works with networking
docker info
docker run --rm alpine echo "Hello from nested container"
docker run --rm alpine ping -c 1 google.com  # Verify DNS + outbound

# Build test image (simplified - no --privileged needed)
docker build -t containai-test -f src/Dockerfile.test src/
docker run containai-test /opt/containai/scripts/test-dind.sh

# Build main image
docker build -t containai -f src/Dockerfile src/

# Run doctor checks (development mode - source from repo)
source src/containai.sh && cai doctor

# Run doctor checks (installed mode)
cai doctor

# Run agent doctor commands
claude doctor

# Verify inner container uses runc (not sysbox)
docker info --format '{{.DefaultRuntime}}'  # Should output "runc"
```

Note: Scripts installed to `/opt/containai/scripts/` in container correspond to `src/scripts/` in repo.

## Acceptance

### Phase 0: Repository Restructure
- [ ] `agent-sandbox/` renamed to `src/`
- [ ] `agent-sandbox/` symlink to `src/` created for backward compatibility
- [ ] `src/README.md` contains deprecation notice for users arriving via `agent-sandbox/`
- [ ] Historical commands work: `docker build -f agent-sandbox/Dockerfile agent-sandbox/`
- [ ] Dockerfiles at `src/Dockerfile` and `src/Dockerfile.test` (root of src for build context)
- [ ] `tests/unit/` and `tests/integration/` directories created
- [ ] VERSION file added at repo root
- [ ] All path references updated (including scripts)

### Phase 1: Dockerfile Cleanup & DinD Infrastructure
- [ ] printf/heredoc hacks removed from Dockerfiles
- [ ] Scripts extracted to separate files with COPY
- [ ] Dockerfile.test simplified (no sysbox installation)
- [ ] dockerd starts with proper lifecycle management (pidfile, logs, timeout)

### Phase 2: Main Image DinD Support
- [ ] Main Dockerfile includes docker-ce, docker-ce-cli, containerd.io, iptables, iproute2, gosu
- [ ] docker group created at build time with agent user as member
- [ ] **Entrypoint MERGES DinD logic with existing functionality** (volume init, security checks, workspace symlink preserved)
- [ ] Entrypoint detects sysbox runtime via uid_map check (with env override)
- [ ] dockerd auto-starts when in sysbox container with --group docker
- [ ] Existing entrypoint security checks preserved (verify_path_under_data_dir, reject_symlink, safe_chmod)
- [ ] Existing volume structure initialization preserved (ensure_volume_structure)
- [ ] Existing workspace discovery and symlink setup preserved
- [ ] `agent` user can run `docker info` without sudo
- [ ] DinD works when running `cai` with sysbox
- [ ] Inner containers verified to use runc (via daemon.json)
- [ ] Networking tests pass: image pull, DNS, outbound connectivity

### Phase 3: Distribution
- [ ] GHCR publishing workflow created (GitHub Actions with parameterized registry)
- [ ] GHCR image visibility set to PUBLIC
- [ ] Multi-arch images (amd64, arm64) via docker buildx
- [ ] `_CONTAINAI_DEFAULT_REPO` updated to GHCR path in `lib/container.sh`
- [ ] `_CONTAINAI_LEGACY_REPOS` array added with old repo prefixes for backward compatibility
- [ ] `_containai_is_our_image()` updated to check both current and legacy repos
- [ ] Existing containers created with old repo prefix recognized as "ours" (tested)
- [ ] `_containai_repo()` helper centralized repo resolution across all checks
- [ ] `CAI_IMAGE_REPO` env override supported for custom registries
- [ ] Standalone `cai` wrapper script with embedded version
- [ ] CLI library files installed to `~/.cai/lib/` preserving directory structure
- [ ] `parse-toml.py` included in install package
- [ ] Wrapper script sources local `~/.cai/lib/containai.sh` for host commands
- [ ] `cai --version` outputs version from embedded variable
- [ ] install.sh works on macOS and Linux with checksum verification
- [ ] install.sh supports `--version`, `--prefix`, `--uninstall` flags
- [ ] install.sh prints PATH instructions and validates `cai` accessibility
- [ ] One-liner install documented in README
- [ ] VERSION file is single source of truth (propagates to tags, CLI)
- [ ] `cai update check` and `cai update apply` commands work

### Phase 4: Documentation Overhaul
- [ ] src/README.md comprehensively rewritten
- [ ] Main README.md explains value proposition clearly
- [ ] Usage/help strings in `containai.sh` updated to reference `cai` command
- [ ] All mermaid diagrams use themeVariables for contrast
- [ ] Diagrams tested on GitHub light and dark mode
- [ ] Architecture diagrams present

### Phase 5: Security Updates
- [ ] SECURITY.md uses GitHub security advisory pattern (code change)
- [ ] No email-based vulnerability reporting
- [ ] Manual step documented: enable private vulnerability reporting in repo settings

### Phase 6: Comprehensive Testing
- [ ] Tier 1 tests (portable) pass on GitHub-hosted runners
- [ ] Tier 2 tests (sysbox) documented for manual/self-hosted execution
- [ ] Test suite for clean start without import
- [ ] Test suite for clean start with import
- [ ] AI agent doctor commands verified
- [ ] Sync map audit complete (all template dirs in `_IMPORT_SYNC_MAP` in `lib/import.sh`)

## References

- [Sysbox documentation](https://github.com/nestybox/sysbox)
- [Sysbox DinD user guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md)
- [GitHub security advisories](https://docs.github.com/en/code-security/security-advisories)
- [WCAG contrast requirements](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html)
- [Mermaid theming](https://mermaid.js.org/config/theming.html)

## Tasks

### Phase 0: Repository Restructure
| ID | Title | Status |
|----|-------|--------|
| fn-10-vep.20 | Reorganize repo structure to match CLI tool conventions | todo |

### Phase 1: Dockerfile Cleanup & DinD Infrastructure
| ID | Title | Status |
|----|-------|--------|
| fn-10-vep.21 | Clean up Dockerfiles: remove printf heredoc hacks | todo |
| fn-10-vep.16 | Simplify Dockerfile.test (remove sysbox install) | todo |
| fn-10-vep.15 | Start dockerd and verify DinD works in sysbox | todo |

Note: 21 (cleanup) before 16 (simplify test) before 15 (verify DinD) - cleanup must precede verification.

### Phase 2: Main Image DinD Support
| ID | Title | Status |
|----|-------|--------|
| fn-10-vep.22 | Add Docker CLI and dockerd to main Dockerfile | todo |
| fn-10-vep.23 | Create entrypoint hook for dockerd auto-start in sysbox | todo |

### Phase 3: Distribution & Updates
| ID | Title | Status |
|----|-------|--------|
| fn-10-vep.24 | Set up GitHub Container Registry publishing | todo |
| fn-10-vep.25 | Create install.sh distribution script | todo |
| fn-10-vep.26 | Add version management and update mechanism | todo |

### Phase 4: Documentation Overhaul
| ID | Title | Status |
|----|-------|--------|
| fn-10-vep.27 | Rewrite agent-sandbox/README.md comprehensively | todo |
| fn-10-vep.28 | Enhance main README.md with value proposition | todo |
| fn-10-vep.29 | Fix mermaid chart contrast in all docs | todo |

### Phase 5: Security Updates
| ID | Title | Status |
|----|-------|--------|
| fn-10-vep.30 | Update SECURITY.md for GitHub advisory pattern | todo |

### Phase 6: Comprehensive Testing
| ID | Title | Status |
|----|-------|--------|
| fn-10-vep.17 | Audit sync map for missing directories | todo |
| fn-10-vep.18 | Create comprehensive test suite | todo |
| fn-10-vep.19 | Test AI agent doctor commands | todo |

**Execution Order:**
- Phase 0: 20
- Phase 1: 21 → 16 → 15 (cleanup before simplify before verify)
- Phase 2: 22 → 23
- Phase 3: 24 → 25 → 26
- Phase 4: 27 → 28 → 29
- Phase 5: 30
- Phase 6: 17 → 18 → 19
