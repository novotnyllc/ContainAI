# fn-35-e0x Pi Agent Support

## Overview

Add support for the Pi agent (Inflection AI) to ContainAI. This includes installation in the Docker image and config sync via sync-manifest.toml.

**Priority:** SECOND - After fn-36-rb7 (CLI UX Consistency).

**Pi Agent:** Inflection AI's Pi is a conversational AI assistant. This epic adds support for its CLI tool and configuration.

## Scope

### In Scope
- Research Pi agent (CLI, config files, auth model)
- Add Pi to sync-manifest.toml
- Add Pi to Dockerfile.agents
- E2E tests for Pi installation verification

### Out of Scope
- Documentation for adding new agents (separate epic)
- Custom agent creation by users (they can use templates)
- Agent marketplace/registry
- Dynamic agent loading

## Approach

### Pi Agent Research

**Questions to Answer:**
1. What is the Pi CLI installation method?
2. Where does Pi store configuration? (`~/.pi/`, `~/.config/pi/`?)
3. What credentials does Pi need? (API key, OAuth?)
4. What files should be synced vs generated?
5. Is there a headless/non-interactive mode?

**Research Tasks:**
- Check Inflection AI documentation
- Install Pi CLI locally
- Document file locations
- Test in container environment

### Sync Manifest Entries

Expected pattern (to be validated):
```toml
# =============================================================================
# PI (Inflection AI)
# =============================================================================

[[entries]]
source = ".pi/config.json"
target = "pi/config.json"
container_link = ".pi/config.json"
flags = "fjo"  # file, json-init, optional (only sync if exists)

[[entries]]
source = ".pi/credentials.json"
target = "pi/credentials.json"
container_link = ".pi/credentials.json"
flags = "fso"  # file, secret, optional

[[entries]]
source = ".pi/settings.json"
target = "pi/settings.json"
container_link = ".pi/settings.json"
flags = "fjo"  # file, json-init, optional
```

**Note:** Use the `o` (optional) flag so we don't create empty `.pi/` directories for users who don't use Pi.

### Dockerfile.agents Addition

```dockerfile
# =============================================================================
# Pi (Inflection AI)
# =============================================================================
RUN curl -fsSL https://pi.ai/install.sh | bash \
    || echo "[WARN] Pi installation failed, continuing..."
```

(Actual installation method TBD from research)

## Tasks

### fn-35-e0x.1: Research Pi agent
Install Pi locally, document config files, auth model, and CLI behavior.

### fn-35-e0x.2: Add Pi to sync-manifest.toml
Add entries for Pi config files based on research. Use `o` flag for optional sync.

### fn-35-e0x.3: Add Pi to Dockerfile.agents
Add installation commands, verify with version check.

### fn-35-e0x.4: Run generators and rebuild
Regenerate symlinks.sh, init-dirs.sh, link-spec.json. Rebuild image.

### fn-35-e0x.5: Create E2E test for Pi
Test that Pi is installed and configs sync correctly.

## Quick commands

```bash
# Research: install Pi locally
# (TBD based on research)

# Build with new agent
./src/build.sh

# Test Pi in container
cai shell
pi --version

# Verify sync (only if you have Pi config)
cai import --dry-run | grep pi

# Verify no pollution (if you DON'T have Pi)
ls -la ~ | grep pi  # Should show nothing
```

## Acceptance

- [ ] Pi agent researched (config location, auth, CLI)
- [ ] Pi entries added to sync-manifest.toml with `o` flag
- [ ] Pi installation added to Dockerfile.agents
- [ ] Generated files updated (symlinks.sh, init-dirs.sh, link-spec.json)
- [ ] Pi works in container (installation verified)
- [ ] Import syncs Pi configs correctly when they exist on host
- [ ] Import does NOT create empty .pi/ when user has no Pi config
- [ ] E2E test verifies Pi installation

## Dependencies

- **fn-36-rb7**: CLI UX Consistency (workspace state, container naming for testing)

## References

- Inflection AI: https://inflection.ai/
- Pi: https://pi.ai/
- Existing agents in sync-manifest.toml
- Dockerfile.agents: `src/container/Dockerfile.agents`
