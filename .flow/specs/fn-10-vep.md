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
- Potentially missing directories (templates, Cursor configs, etc.)

## Scope

### In Scope

**Phase 0: Repository Restructure (DO FIRST)**
- Reorganize repo to match CLI tool conventions (docker-compose, dagger, mise patterns)
- Rename `agent-sandbox/` to `src/`
- Move Dockerfiles to `src/docker/`
- Create `tests/` directory
- Add VERSION file
- **DO NOT touch `.flow/` or `scripts/` directories**

**Phase 1: Dockerfile Cleanup & DinD Infrastructure**
- Clean up Dockerfiles: remove printf/heredoc hacks, use COPY
- Extract embedded configs/scripts to separate files
- Simplify Dockerfile.test (remove sysbox installation - we're already in sysbox)
- Configure dockerd startup for sysbox (no --privileged needed)

**Phase 2: Main Image DinD Support**
- Add dockerd + Docker CLI installation to main Dockerfile
- Add entrypoint hook to auto-start dockerd when in sysbox container
- Proper detection of sysbox runtime at container start

**Phase 3: Distribution & Updates**
- Set up GitHub Container Registry (GHCR) publishing
- Pre-built multi-arch images (amd64, arm64)
- Installer script (curl | bash pattern)
- Version management with single source of truth
- Update mechanism (`cai update` command)

**Phase 4: Documentation Overhaul**
- Rewrite src/README.md (formerly agent-sandbox/README.md)
- Enhance main README.md with value proposition
- Fix mermaid chart contrast issues
- Add architecture diagrams

**Phase 5: Security Updates**
- Update SECURITY.md for GitHub advisory pattern
- Configure GitHub security advisories

**Phase 6: Comprehensive Testing**
- Create test suite for clean start w/o import, clean start with import
- Test AI agent doctor commands
- Audit sync map for missing directories

### Out of Scope
- Windows native support (WSL2 only)
- Podman support
- GUI tools
- Homebrew formula (future, after v1.0)

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
- Inner containers use regular runc (no deeper sysbox nesting)
- Network is shared with parent container

### dockerd Configuration for Sysbox

```bash
# Start dockerd (sysbox handles the capabilities)
dockerd \
  --host=unix:///var/run/docker.sock \
  --iptables=false \
  --ip-masq=false \
  &

# Wait for socket
timeout 30 bash -c 'until docker info >/dev/null 2>&1; do sleep 1; done'
```

### Mermaid Contrast Fix

Use explicit colors in all mermaid diagrams:
```mermaid
%% Good contrast example
graph LR
    A[Step 1] --> B[Step 2]
    style A fill:#1a1a2e,stroke:#16213e,color:#fff
    style B fill:#0f3460,stroke:#16213e,color:#fff
```

## Quick commands

```bash
# Start dockerd in current sysbox container
sudo dockerd --iptables=false --ip-masq=false &
sleep 5

# Verify dockerd works
docker info
docker run --rm alpine echo "Hello from nested container"

# Build test image (simplified - no --privileged needed)
docker build -t containai-test -f agent-sandbox/Dockerfile.test agent-sandbox/
docker run containai-test /usr/local/bin/test-dind.sh

# Build main image
./agent-sandbox/build.sh

# Run doctor checks
source agent-sandbox/containai.sh && cai doctor

# Run agent doctor commands
claude doctor
```

## Acceptance

### Phase 0: Repository Restructure
- [ ] `agent-sandbox/` renamed to `src/`
- [ ] Dockerfiles moved to `src/docker/`
- [ ] `tests/` directory created
- [ ] VERSION file added
- [ ] All path references updated

### Phase 1: Dockerfile Cleanup & DinD Infrastructure
- [ ] printf/heredoc hacks removed from Dockerfiles
- [ ] Scripts extracted to separate files with COPY
- [ ] Dockerfile.test simplified (no sysbox installation)
- [ ] dockerd starts without --privileged

### Phase 2: Main Image DinD Support
- [ ] Main Dockerfile includes dockerd + CLI
- [ ] Entrypoint detects sysbox runtime
- [ ] dockerd auto-starts when in sysbox container
- [ ] DinD works when running `cai` with sysbox

### Phase 3: Distribution
- [ ] GHCR publishing workflow created
- [ ] Multi-arch images (amd64, arm64)
- [ ] install.sh works on macOS and Linux
- [ ] One-liner install documented in README
- [ ] Version number trackable
- [ ] `cai update` command works

### Phase 4: Documentation Overhaul
- [ ] agent-sandbox/README.md comprehensively rewritten
- [ ] Main README.md explains value proposition clearly
- [ ] All mermaid diagrams have good contrast (WCAG AA)
- [ ] Architecture diagrams present

### Phase 5: Security Updates
- [ ] SECURITY.md uses GitHub security advisory pattern
- [ ] No email-based vulnerability reporting
- [ ] GitHub security advisories enabled on repo

### Phase 6: Comprehensive Testing
- [ ] Test suite for clean start without import
- [ ] Test suite for clean start with import
- [ ] AI agent doctor commands verified
- [ ] Sync map audit complete

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
| fn-10-vep.15 | Start dockerd and verify DinD works in sysbox | todo |
| fn-10-vep.16 | Simplify Dockerfile.test (remove sysbox install) | todo |

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
- Phase 1: 15 → 21 → 16
- Phase 2: 22 → 23
- Phase 3: 24 → 25 → 26
- Phase 4: 27 → 28 → 29
- Phase 5: 30
- Phase 6: 17 → 18 → 19
