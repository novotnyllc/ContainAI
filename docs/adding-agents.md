# Adding a New Agent to ContainAI

This guide explains how to add support for a new AI coding agent to ContainAI.

## Overview

Adding an agent involves six steps:

1. **Research** - Understand the agent's installation and configuration
2. **Dockerfile** - Add installation to `Dockerfile.agents`
3. **Manifest** - Add config entries to `sync-manifest.toml`
4. **Import map** - Update `_IMPORT_SYNC_MAP` in `import.sh`
5. **Generators** - Run generators and consistency check
6. **Test** - Verify in container

## Step 1: Research the Agent

Before adding a new agent, understand:

- **Installation method**: npm/bun, pip/uv, curl installer, apt package?
- **Configuration location**: `~/.config/agent/`, `~/.agent/`, `~/.agentrc`?
- **Credential storage**: Which files contain API keys or OAuth tokens?
- **Startup requirements**: Environment variables, symlinks, services?

Example research for a hypothetical agent:

```bash
# Check where agent stores config
ls -la ~/.myagent/
# Check if there's a version command
myagent --version
# Check installation method docs
```

## Step 2: Add to Dockerfile.agents

Add installation after the SDK layers in `src/container/Dockerfile.agents`.

### Required Agents (Fail-Fast)

For agents that must be present in the image (like Claude, Codex):

```dockerfile
# =============================================================================
# AGENT NAME
# =============================================================================
RUN <installation-command> && \
    # Verify agent installed correctly
    agent --version
```

The `&& agent --version` ensures the build fails immediately if installation breaks.

### Optional Components (Soft-Fail)

For truly optional components where absence is acceptable:

```dockerfile
# Optional: Agent Name (soft-fail if unavailable)
RUN ( <installation-command> && agent --version ) \
    || echo "[WARN] Agent installation failed - continuing without it"
```

**Guidelines:**

- **Required agents**: Use fail-fast pattern with `&& agent --version`
- **Optional components**: Use explicit grouping `( cmd ) || warn` with clear justification
- Group related commands with `&&`
- Document any special requirements in comments

### Real Examples

**Claude Code** (required, fail-fast):

```dockerfile
# Install Claude Code via official installer
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    /home/agent/.local/bin/claude --version
```

**Gemini CLI** (required, installed via bun):

```dockerfile
RUN . /home/agent/.nvm/nvm.sh && \
    bun install -g --trust @google/gemini-cli && \
    gemini --version
```

**Kimi CLI** (required, installed via uv):

```dockerfile
RUN uv tool install --python 3.13 kimi-cli && \
    kimi --version
```

## Step 3: Add to sync-manifest.toml

Add entries for each config file/directory in `src/sync-manifest.toml`.

### Entry Format

```toml
# =============================================================================
# AGENT NAME
# Description of what agent does
# Docs: https://agent.example.com
# =============================================================================

[[entries]]
source = ".agent/config.json"         # Path on host (relative to $HOME)
target = "agent/config.json"          # Path in data volume (/mnt/agent-data)
container_link = ".agent/config.json" # Symlink in container home
flags = "fjos"                        # Flags (see reference below)
```

### Flags Reference

| Flag | Meaning | Example Use |
|------|---------|-------------|
| `f` | File (not directory) | Single config files |
| `d` | Directory | Config directories, plugins |
| `j` | JSON init (create `{}` if empty) | JSON config files |
| `s` | Secret (600 for files, 700 for dirs; skipped with `--no-secrets`) | API keys, OAuth tokens |
| `o` | Optional (skip if source doesn't exist; don't pre-create in Dockerfile/init) | Agents user may not have installed |
| `m` | Mirror mode (`--delete` removes extras) | Strict directory sync |
| `x` | Exclude `.system/` subdirectory | Skills directories with system-managed files |
| `R` | Remove existing path first (`rm -rf` before `ln -sfn`) | Directories that may be pre-populated |
| `g` | Git filter (strip credential.helper and signing config) | `.gitconfig` special handling |
| `G` | Glob/dynamic pattern (discovered at runtime, not synced directly) | SSH key patterns like `id_*` |

### Required vs Optional Agents

**Required/primary agents** (Claude, Codex): Omit the `o` flag. These are always synced and their directories are pre-created in the container image.

```toml
# Claude - required agent, no 'o' flag
[[entries]]
source = ".claude/settings.json"
target = "claude/settings.json"
container_link = ".claude/settings.json"
flags = "fj"  # file, json-init (no 'o')
```

**Optional agents** (Gemini, Pi, Copilot, Kimi): Use the `o` flag. These are only synced if the user has them configured on the host, preventing empty directories in the container for agents the user doesn't use.

```toml
# Gemini - optional agent, has 'o' flag
[[entries]]
source = ".gemini/settings.json"
target = "gemini/settings.json"
container_link = ".gemini/settings.json"
flags = "fjo"  # file, json-init, OPTIONAL
```

### Secret Files

Files containing API keys, OAuth tokens, or credentials should have the `s` flag:

```toml
[[entries]]
source = ".agent/auth.json"
target = "agent/auth.json"
container_link = ".agent/auth.json"
flags = "fs"  # file, SECRET
```

Secret files are:
- Created with restrictive permissions (600 for files, 700 for directories)
- Skipped when `cai import --no-secrets` is used

### Container-Only Symlinks

For entries that exist only in the container (not imported from host):

```toml
[[container_symlinks]]
target = "some/path/file.json"        # Path in volume
container_link = ".config/file.json"  # Symlink in container home
flags = "fj"                          # flags for structure
```

Use this for files that are created inside the container but should persist on the data volume.

### Disabled Entries

For entries that should generate symlinks/init but not be synced by default:

```toml
[[entries]]
source = ".agent/config"
target = "agent/config"
container_link = ".agent/config"
flags = "ds"
disabled = true  # Excluded from _IMPORT_SYNC_MAP
```

Disabled entries:
- Still generate container symlinks and init directories
- Are not synced during normal `cai import`
- Can be included via `[import].additional_paths` in `containai.toml`

SSH is a common example - disabled by default for security, but users can opt-in.

## Step 4: Update _IMPORT_SYNC_MAP

After modifying `sync-manifest.toml`, update the corresponding import map in `src/lib/import.sh`.

The `_IMPORT_SYNC_MAP` array must match the manifest exactly (excluding disabled entries and entries with `G` flag).

### Entry Format

```bash
_IMPORT_SYNC_MAP=(
    # --- Agent Name ---
    # Comment describing what this entry syncs
    "/source/.agent/config.json:/target/agent/config.json:fjs"
    "/source/.agent/auth.json:/target/agent/auth.json:fs"
    "/source/.agent/plugins:/target/agent/plugins:do"
)
```

**Format**: `/source/<host-path>:/target/<volume-path>:<flags>`

### Consistency Check

After updating both files, run the consistency check:

```bash
./scripts/check-manifest-consistency.sh
```

This script:
- Parses all entries from `sync-manifest.toml`
- Extracts all entries from `_IMPORT_SYNC_MAP`
- Reports any mismatches (missing entries, flag differences)

CI enforces this check - builds will fail if the manifest and import map diverge.

## Step 5: Run Generators

The generators create container artifacts from the manifest.

### Generator Commands

```bash
# Generate Dockerfile symlink script
./src/scripts/gen-dockerfile-symlinks.sh src/sync-manifest.toml src/container/generated/symlinks.sh

# Generate init directory script
./src/scripts/gen-init-dirs.sh src/sync-manifest.toml src/container/generated/init-dirs.sh

# Generate link spec JSON for runtime repair
./src/scripts/gen-container-link-spec.sh src/sync-manifest.toml src/container/generated/link-spec.json
```

**Note**: The build script `./src/build.sh` runs these generators automatically before building the image. Manual execution is only needed for development/testing.

### What the Generators Create

- **symlinks.sh**: Shell script run during Docker build to create symlinks from container home to data volume paths
- **init-dirs.sh**: Shell script run on container first boot to create directory structure with correct permissions
- **link-spec.json**: JSON specification for runtime link verification and repair

## Step 6: Test

Testing follows the tiered strategy documented in [docs/testing.md](testing.md).

### Tier 1: Linting (Host-Side)

```bash
# Shell script linting
shellcheck -x src/*.sh src/lib/*.sh

# Manifest consistency
./scripts/check-manifest-consistency.sh
```

### Tier 2: Integration Tests

```bash
# Run sync integration tests
./tests/integration/test-sync-integration.sh
```

### Tier 3: E2E Tests (Requires Sysbox + Container)

These tests require a Linux host with sysbox installed.

**1. Build and start container (on host):**

```bash
# Build image with new agent
./src/build.sh

# Create and start container
cai run --container test-agent
```

**2. Verify agent installed (from host, via SSH):**

```bash
# Replace 'newagent' with actual agent binary name
ssh test-agent 'newagent --version'
```

**3. Import configs (from host):**

```bash
cai import
```

**4. Verify configs synced (from host, via SSH):**

```bash
# Replace .newagent with actual agent config directory
ssh test-agent 'ls -la ~/.newagent/'
```

**5. Verify no empty dirs for optional agents (from host, via SSH):**

```bash
# Check specific optional agent directories
ssh test-agent 'for d in .copilot .gemini .pi .kimi; do [ -d ~/"$d" ] && echo "WARNING: $d exists unexpectedly"; done'
```

**6. Test fresh container behavior:**

```bash
# Remove and recreate container
cai run --container test-agent --fresh

# Verify agent configs are restored after import
cai import
ssh test-agent 'ls -la ~/.newagent/'
```

## Examples from Existing Agents

### Required Agents (no `o` flag)

**Claude Code** - Primary supported agent:

```toml
# In sync-manifest.toml
[[entries]]
source = ".claude.json"
target = "claude/claude.json"
container_link = ".claude.json"
flags = "fjs"  # file, json-init, secret

[[entries]]
source = ".claude/.credentials.json"
target = "claude/credentials.json"
container_link = ".claude/.credentials.json"
flags = "fs"  # file, secret

[[entries]]
source = ".claude/settings.json"
target = "claude/settings.json"
container_link = ".claude/settings.json"
flags = "fj"  # file, json-init
```

**Codex** - Primary supported agent:

```toml
[[entries]]
source = ".codex/config.toml"
target = "codex/config.toml"
container_link = ".codex/config.toml"
flags = "f"  # file

[[entries]]
source = ".codex/auth.json"
target = "codex/auth.json"
container_link = ".codex/auth.json"
flags = "fs"  # file, secret

[[entries]]
source = ".codex/skills"
target = "codex/skills"
container_link = ".codex/skills"
flags = "dxR"  # directory, exclude .system/, remove existing first
```

### Optional Agents (with `o` flag)

**Gemini** - Optional:

```toml
[[entries]]
source = ".gemini/google_accounts.json"
target = "gemini/google_accounts.json"
container_link = ".gemini/google_accounts.json"
flags = "fso"  # file, secret, OPTIONAL

[[entries]]
source = ".gemini/oauth_creds.json"
target = "gemini/oauth_creds.json"
container_link = ".gemini/oauth_creds.json"
flags = "fso"  # file, secret, OPTIONAL

[[entries]]
source = ".gemini/settings.json"
target = "gemini/settings.json"
container_link = ".gemini/settings.json"
flags = "fjo"  # file, json-init, OPTIONAL
```

**Pi** - Optional:

```toml
[[entries]]
source = ".pi/agent/settings.json"
target = "pi/settings.json"
container_link = ".pi/agent/settings.json"
flags = "fjo"  # file, json-init, optional

[[entries]]
source = ".pi/agent/models.json"
target = "pi/models.json"
container_link = ".pi/agent/models.json"
flags = "fjso"  # file, json-init, SECRET, optional

[[entries]]
source = ".pi/agent/skills"
target = "pi/skills"
container_link = ".pi/agent/skills"
flags = "dxRo"  # directory, exclude .system/, remove-first, optional
```

**Copilot** - Optional:

```toml
[[entries]]
source = ".copilot/config.json"
target = "copilot/config.json"
container_link = ".copilot/config.json"
flags = "fo"  # file, optional

[[entries]]
source = ".copilot/mcp-config.json"
target = "copilot/mcp-config.json"
container_link = ".copilot/mcp-config.json"
flags = "fo"  # file, optional
```

**Kimi** - Optional:

```toml
[[entries]]
source = ".kimi/config.toml"
target = "kimi/config.toml"
container_link = ".kimi/config.toml"
flags = "fso"  # file, SECRET, optional

[[entries]]
source = ".kimi/mcp.json"
target = "kimi/mcp.json"
container_link = ".kimi/mcp.json"
flags = "fjso"  # file, json-init, SECRET, optional
```

## Quick Reference

### View Existing Agent Patterns

```bash
# View agent sections in manifest
grep -A5 'CLAUDE\|CODEX\|GEMINI\|PI\b\|COPILOT\|KIMI' src/sync-manifest.toml

# View Dockerfile.agents patterns
cat src/container/Dockerfile.agents

# Check manifest/import map consistency
./scripts/check-manifest-consistency.sh
```

### File Locations

| File | Purpose |
|------|---------|
| `src/sync-manifest.toml` | Authoritative source for sync configuration |
| `src/lib/import.sh` | Contains `_IMPORT_SYNC_MAP` (must match manifest) |
| `src/container/Dockerfile.agents` | Agent installation instructions |
| `src/scripts/gen-*.sh` | Generator scripts for container artifacts |
| `scripts/check-manifest-consistency.sh` | Manifest/import map consistency check |
| `docs/testing.md` | Testing tier documentation |

## Related Documentation

- [Testing Guide](testing.md) - Test tier details and CI workflow
- [Sync Architecture](sync-architecture.md) - Deep dive into sync mechanics
- [Configuration](configuration.md) - `containai.toml` options including `additional_paths`
