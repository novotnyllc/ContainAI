# ContainAI Sync Operations

Use this skill when: syncing host configs to containers, exporting data for backup, restoring from archives, understanding data persistence.

## Data Model

ContainAI uses Docker volumes for persistent data, mounted at `/mnt/agent-data`:

```
Container filesystem:
/home/agent/
├── workspace/             # Your project (bind mount from host)
├── .gitconfig             # Symlink -> /mnt/agent-data/git/gitconfig
├── .claude.json           # Symlink -> /mnt/agent-data/claude/claude.json
└── ...                    # Other symlinked configs

/mnt/agent-data/           # Docker volume mount (persistent)
├── git/
│   └── gitconfig          # Actual git config
├── claude/
│   └── claude.json        # Actual credentials
└── ...                    # Other imported configs
```

The `cai sync` command (run automatically on container init) creates symlinks
from user-facing paths to the volume, so you can edit `~/.gitconfig` normally
while data persists in the volume.

## Import Command

Sync host configs to container data volume.

```bash
cai import [path] [options]
```

### Modes

**Volume-Only Mode** (no workspace/container):
```bash
cai import                 # Sync to auto-resolved volume
cai import --data-volume v # Sync to specific volume
```

**Hot-Reload Mode** (with workspace or container):
```bash
cai import /path/to/workspace    # Sync AND reload into running container
cai import --container my-proj   # Sync to specific container
```

### Options

```bash
--workspace <path>        # Workspace path (enables hot-reload)
--container <name>        # Target container (must exist)
--data-volume <vol>       # Override data volume name
--from <path>             # Import source directory or archive
--config <path>           # Config file path
--dry-run                 # Preview changes
--no-excludes             # Skip exclude patterns
--no-secrets              # Skip secret files (tokens, keys)
--verbose                 # Show skipped files
```

### What Gets Synced

Default sync items (from src/manifests/):
- Git config (user.name, user.email)
- GitHub CLI config and OAuth tokens
- Agent configs and secrets (Claude, Gemini, Codex, etc.)
- Shell configs (.bashrc.d additions)

**Secrets are synced by default.** Use `--no-secrets` to skip them.

NOT synced by default:
- SSH keys (use agent forwarding instead; add via `[import].additional_paths` if needed)
- `~/.claude/.credentials.json`, `~/.codex/auth.json` (skipped from home profile;
  use `--from` or `[import].additional_paths` to include)

### Examples

```bash
cai import                       # Sync to auto-resolved volume
cai import /path/to/workspace    # Hot-reload into running container
cai import --container my-proj   # Hot-reload into named container
cai import --dry-run             # Preview what would be synced
cai import --no-secrets          # Skip credential files
cai import --from ~/other/       # Import from different directory
cai import --from backup.tgz     # Restore from archive
```

### Secrets Handling

Secret files skipped with `--no-secrets`:
- `~/.claude.json` (Claude OAuth)
- `~/.gemini/google_accounts.json`, `oauth_creds.json`
- `~/.local/share/opencode/auth.json`
- `~/.config/gh/hosts.yml` (GitHub CLI tokens)
- `~/.aider.conf.yml` (may contain API keys)
- `~/.continue/config.yaml`, `config.json`

## Export Command

Export data volume to archive.

```bash
cai export [options]
```

### Options

```bash
-o, --output <path>       # Output file or directory
--container <name>        # Export from specific container
--data-volume <vol>       # Export specific volume
--workspace <path>        # Workspace for config resolution
--config <path>           # Config file path
--no-excludes             # Skip exclude patterns
--verbose                 # Verbose output
```

### Output Path

- Not specified: `containai-export-YYYYMMDD-HHMMSS.tgz` in current dir
- Directory: appends default filename
- File: uses exact path

### Examples

```bash
cai export                       # Export to current directory
cai export -o ~/backup.tgz       # Export to specific file
cai export -o ~/backups/         # Export to directory
cai export --container my-proj   # Export from specific container
cai export --data-volume vol     # Export specific volume
```

## Sync Command (In-Container)

Move local configs to data volume with symlinks. Run this inside the container.

```bash
cai sync
```

This is typically run automatically during container initialization.

## Common Patterns

### Initial Setup

```bash
# 1. Check what would be synced
cai import --dry-run

# 2. Sync configs
cai import

# 3. Start container
cai run
```

### Update Running Container

```bash
# Hot-reload configs into running container
cai import /path/to/workspace
```

### Backup Before Major Changes

```bash
# Export current state
cai export -o ~/backup-$(date +%Y%m%d).tgz

# Make changes...
cai run --fresh

# If needed, restore
cai import --from ~/backup-20240115.tgz
```

### Transfer Between Machines

```bash
# On source machine
cai export -o ~/containai-data.tgz

# Transfer file to new machine
scp ~/containai-data.tgz newmachine:~/

# On new machine
cai import --from ~/containai-data.tgz
cai run
```

### Clean Sync (No Secrets)

```bash
# Sync without credentials (container will prompt for login)
cai import --no-secrets
```

## Archive Format

Export archives are `.tgz` (gzipped tar) containing:
- Directory structure from data volume
- Preserves permissions and symlinks
- Excludes paths matching config excludes

Restore is idempotent - re-importing an archive updates existing files.

## Gotchas

### Hot-Reload Requires Running Container

Hot-reload mode (`cai import /path`) requires the container to be running. For stopped containers, use volume-only mode:

```bash
cai import --data-volume <name>
cai run
```

### Credentials and Secrets

**Secrets are synced by default.** This includes OAuth tokens in `~/.claude.json`,
`~/.config/gh/hosts.yml`, etc. Use `--no-secrets` to skip these files.

Some credential files are skipped when importing from the home profile:
- `~/.claude/.credentials.json` (Claude desktop app)
- `~/.codex/auth.json` (Codex CLI)

To import these files, use `--from` or add to config:
```toml
# containai.toml
[import]
additional_paths = ["~/.claude/.credentials.json"]
```

### SSH Keys

SSH keys are NOT synced by default. Use SSH agent forwarding instead:

```bash
# On host
eval "$(ssh-agent)"
ssh-add ~/.ssh/id_ed25519

# Agent is automatically forwarded to container
cai shell
```

If you must sync keys:
```toml
# containai.toml
[import]
additional_paths = ["~/.ssh"]
```

### Excludes

Default excludes skip cache directories, build artifacts, etc. View with:

```bash
cai import --dry-run --verbose
```

Override with `--no-excludes` (not recommended).

### Volume Names

Volume resolution precedence:
1. `--data-volume` flag (highest)
2. `CONTAINAI_DATA_VOLUME` environment variable
3. Workspace state (from previous `--reset` or config)
4. Repo-local config (`.containai/config.toml`)
5. User global config
6. Default: `containai-data`

Use `--reset` to generate a new unique volume name for the workspace.
Multiple workspaces share the default volume unless configured otherwise.

## Related Skills

- `containai-quickstart` - Basic workflow
- `containai-lifecycle` - Container management
- `containai-troubleshooting` - Error handling
