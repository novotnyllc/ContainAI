# DevContainer Integration for ContainAI

## Executive Summary

Enable VS Code devcontainers to run securely in sysbox with minimal friction. Users install `cai` on their host (WSL/Mac), add our feature to any devcontainer, and a VS Code extension + smart docker wrapper routes the container through sysbox.

**Key insight**: The devcontainer runs **directly** in sysbox - no outer container, no nesting overhead. Our feature overlays onto whatever base image the user wants.

**Security invariant**: Hard-block if not running in sysbox. Kernel-enforced checks cannot be faked.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│ User's Host (WSL/Mac)                                                   │
│                                                                         │
│   Prerequisites (via cai setup):                                        │
│   ├─ sysbox runtime installed                                           │
│   ├─ containai-docker context (uses sysbox as default runtime)          │
│   ├─ cai-docker wrapper at ~/.local/bin/cai-docker                      │
│   ├─ VS Code ContainAI extension                                        │
│   └─ Data volume created by 'cai import' (containai-data-<name>)        │
│                                                                         │
│   ~/.ssh/config (managed by cai-docker):                                │
│   ├─ Host containai-devcontainer-<workspace>                            │
│   │     HostName localhost                                              │
│   │     Port 2322                                                       │
│   │     User vscode                                                     │
│   └─ (enables: ssh containai-devcontainer-myproject)                    │
│                                                                         │
│   ┌───────────────────────┐                                             │
│   │ VS Code               │                                             │
│   │ ├─ Dev Containers ext │                                             │
│   │ │   dockerPath ──────────> cai-docker wrapper                       │
│   │ └─ ContainAI ext      │        │                                    │
│   │    (sets dockerPath)  │        ├─ Detects ContainAI markers         │
│   └───────────────────────┘        ├─ Routes to sysbox context          │
│                                    ├─ Mounts data volume                │
│                                    ├─ Adds labels for GC                │
│                                    └─ Updates ~/.ssh/config             │
│                                    │                                    │
│                                    ▼                                    │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ User's Devcontainer (DIRECTLY in sysbox)                        │   │
│   │                                                                 │   │
│   │   Base image: ANY + ContainAI feature                           │   │
│   │                                                                 │   │
│   │   Mounts:                                                       │   │
│   │   ├─ /mnt/agent-data ← containai-data-<name> volume             │   │
│   │   └─ /workspaces/<project> ← host workspace (standard)          │   │
│   │                                                                 │   │
│   │   postCreateCommand (init.sh):                                  │   │
│   │   ├─ Verify sysbox (kernel checks)                              │   │
│   │   └─ Create symlinks: ~/.claude → /mnt/agent-data/claude, etc.  │   │
│   │                                                                 │   │
│   │   postStartCommand (start.sh):                                  │   │
│   │   ├─ Start sshd on port 2322 (not systemd)                      │   │
│   │   └─ Re-verify sysbox                                           │   │
│   │                                                                 │   │
│   │   Services:                                                     │   │
│   │   ├─ sshd (port 2322) - for non-VS Code access                  │   │
│   │   └─ dockerd (DinD) - works without --privileged                │   │
│   │                                                                 │   │
│   │   Labels:                                                       │   │
│   │   ├─ containai.type=devcontainer                                │   │
│   │   ├─ containai.workspace=<project-name>                         │   │
│   │   └─ containai.created=<timestamp>                              │   │
│   └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key points**:
- Devcontainer runs **directly** in sysbox (no outer container overhead)
- Data volume provides all synced configs (run `cai import` first)
- SSH works via devcontainer port forwarding (not systemd)
- Labels enable `cai ps`, `cai stop`, GC integration

---

## What ContainAI Feature Provides

The feature replicates the full `cai` experience on any base image:

### 1. Sysbox Verification
- Kernel-enforced checks that cannot be faked
- Hard-fail if not running in sysbox

### 2. Data Volume Integration
- Mounts existing cai data volume (`containai-data-<name>`)
- Creates symlinks from standard paths to volume (like `containai-init.sh`)
- Synced configs: Claude, Git, GitHub CLI, shell, editors, agents, etc.

### 3. Docker-in-Docker
- Works without `--privileged` (sysbox provides this)
- Nested containers work properly

### 4. SSH Access
- sshd runs as devcontainer service (not systemd)
- Port forwarded via devcontainer's `forwardPorts`
- Host SSH config entry added by cai-docker wrapper

### 5. Container Lifecycle
- Labels for cai GC integration
- Consistent naming for `cai ps` / `cai stop`

```json
{
    "image": "mcr.microsoft.com/devcontainers/python:3.11",
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {
            "dataVolume": "containai-data-myproject",
            "enableSsh": true,
            "sshPort": 2322
        }
    }
}
```

---

## Component Design

### 1. Smart Docker Wrapper (`cai-docker`)

**Location**: `~/.local/bin/cai-docker`

**Purpose**:
- Detect ContainAI devcontainers
- Route to sysbox context
- Mount data volume automatically
- Add labels for GC integration
- Update host SSH config

```bash
#!/usr/bin/env bash
set -euo pipefail

CAI_SSH_CONFIG_MARKER="# ContainAI devcontainer managed"

find_devcontainer_json() {
    local workspace_dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace-folder=*) workspace_dir="${1#*=}" ;;
            --workspace-folder) workspace_dir="$2"; shift ;;
            *) ;;
        esac
        shift
    done
    [[ -z "$workspace_dir" ]] && return 1

    for path in \
        "$workspace_dir/.devcontainer/devcontainer.json" \
        "$workspace_dir/.devcontainer.json" \
        "$workspace_dir/.devcontainer/"*/devcontainer.json
    do
        [[ -f "$path" ]] && echo "$path" && return 0
    done
    return 1
}

get_workspace_name() {
    local workspace_dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace-folder=*) workspace_dir="${1#*=}" ;;
            --workspace-folder) workspace_dir="$2"; shift ;;
            *) ;;
        esac
        shift
    done
    basename "$workspace_dir"
}

is_containai_devcontainer() {
    local config
    config=$(find_devcontainer_json "$@") || return 1
    sed 's|//.*$||; s|/\*.*\*/||g' "$config" | grep -qE 'containai'
}

get_data_volume_name() {
    local workspace_name="$1"
    local config
    config=$(find_devcontainer_json "$@") || echo ""

    # Check if dataVolume is specified in feature options
    if [[ -n "$config" ]]; then
        local vol
        vol=$(sed 's|//.*$||; s|/\*.*\*/||g' "$config" | \
              grep -oE '"dataVolume"\s*:\s*"[^"]+"' | \
              sed 's/.*"\([^"]*\)"$/\1/' | head -1)
        [[ -n "$vol" ]] && echo "$vol" && return
    fi

    # Default: containai-data-<workspace>
    echo "containai-data-${workspace_name}"
}

check_containai_ready() {
    if ! docker context inspect containai-docker &>/dev/null; then
        cat >&2 <<'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║  ContainAI: Not set up. Run: cai setup                            ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
        return 1
    fi
    return 0
}

# Add SSH config entry for this devcontainer
update_ssh_config() {
    local workspace_name="$1"
    local ssh_port="${2:-2322}"
    local host_alias="containai-devcontainer-${workspace_name}"
    local ssh_config="$HOME/.ssh/config"

    mkdir -p "$HOME/.ssh"
    touch "$ssh_config"
    chmod 600 "$ssh_config"

    # Remove existing entry for this workspace
    if grep -q "Host $host_alias" "$ssh_config" 2>/dev/null; then
        # Remove the block (Host line through next Host or EOF)
        sed -i.bak "/Host $host_alias/,/^Host /{ /^Host $host_alias/d; /^Host /!d; }" "$ssh_config"
    fi

    # Add new entry
    cat >> "$ssh_config" << EOF

$CAI_SSH_CONFIG_MARKER
Host $host_alias
    HostName localhost
    Port $ssh_port
    User vscode
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
    echo "SSH: ssh $host_alias" >&2
}

# Check if image is a ContainAI image
is_containai_image() {
    local image="$1"
    [[ "$image" == *"containai"* ]] || [[ "$image" == "ghcr.io/novotnyllc/containai"* ]]
}

# Get user from devcontainer.json (remoteUser or containerUser)
get_devcontainer_user() {
    local config="$1"
    sed 's|//.*$||; s|/\*.*\*/||g' "$config" | \
        grep -oE '"(remoteUser|containerUser)"\s*:\s*"[^"]+"' | \
        head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

# Inject volume mount, labels, and user into docker run/create commands
inject_containai_args() {
    local workspace_name="$1"
    local data_volume="$2"
    local config="$3"
    local image="$4"
    shift 4

    local args=()
    local found_run_or_create=false

    for arg in "$@"; do
        args+=("$arg")

        if [[ "$arg" == "run" || "$arg" == "create" ]]; then
            found_run_or_create=true

            # Inject data volume mount (if volume exists)
            if docker --context containai-docker volume inspect "$data_volume" &>/dev/null; then
                args+=("-v" "${data_volume}:/mnt/agent-data:rw")
            fi

            # Inject labels for cai integration
            args+=("--label" "containai.type=devcontainer")
            args+=("--label" "containai.workspace=${workspace_name}")
            args+=("--label" "containai.created=$(date -Iseconds)")

            # Inject -u agent for ContainAI images (unless user specified in devcontainer.json)
            if is_containai_image "$image"; then
                local specified_user
                specified_user=$(get_devcontainer_user "$config")
                if [[ -z "$specified_user" ]]; then
                    args+=("-u" "agent")
                fi
            fi
        fi
    done

    printf '%s\0' "${args[@]}"
}

main() {
    if is_containai_devcontainer "$@"; then
        check_containai_ready || exit 1

        local workspace_name
        workspace_name=$(get_workspace_name "$@")

        local data_volume
        data_volume=$(get_data_volume_name "$workspace_name" "$@")

        local config
        config=$(find_devcontainer_json "$@")

        local image
        image=$(get_image_from_args "$@")

        # Update SSH config
        update_ssh_config "$workspace_name" 2322

        # Inject mounts, labels, and user, then exec
        local -a modified_args
        while IFS= read -r -d '' arg; do
            modified_args+=("$arg")
        done < <(inject_containai_args "$workspace_name" "$data_volume" "$config" "$image" "$@")

        exec docker --context containai-docker "${modified_args[@]}"
    else
        exec docker "$@"
    fi
}

main "$@"
```

---

### 2. VS Code Extension (`vscode-containai`)

**Distribution**:
- VS Code Marketplace
- Open VSX
- Installed by `cai setup`

**Purpose**: Set `dev.containers.dockerPath` when ContainAI feature detected.

```typescript
import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';

export function activate(context: vscode.ExtensionContext) {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) return;

    const devcontainerPath = findDevcontainerJson(workspaceFolder.uri.fsPath);
    if (!devcontainerPath) return;

    if (hasContainAIMarkers(devcontainerPath)) {
        const caiDockerPath = findCaiDocker();
        if (caiDockerPath) {
            vscode.workspace.getConfiguration('dev.containers').update(
                'dockerPath',
                caiDockerPath,
                vscode.ConfigurationTarget.Workspace
            );
            vscode.window.showInformationMessage(
                'ContainAI: Devcontainer will run in sysbox sandbox.'
            );
        } else {
            vscode.window.showWarningMessage(
                'ContainAI feature detected but cai not installed. ' +
                'Run: curl -fsSL https://containai.dev/install | sh'
            );
        }
    }
}

function hasContainAIMarkers(devcontainerPath: string): boolean {
    const content = fs.readFileSync(devcontainerPath, 'utf8')
        .replace(/\/\/.*$/gm, '')
        .replace(/\/\*[\s\S]*?\*\//g, '');
    return content.includes('containai');
}

function findCaiDocker(): string | null {
    const candidates = [
        path.join(process.env.HOME || '', '.local/bin/cai-docker'),
        '/usr/local/bin/cai-docker'
    ];
    return candidates.find(p => fs.existsSync(p)) || null;
}
```

---

### 3. ContainAI Feature

**Distribution**: `ghcr.io/novotnyllc/containai/feature:latest`

**devcontainer-feature.json**:
```json
{
    "id": "containai",
    "version": "1.0.0",
    "name": "ContainAI Sysbox Sandbox",
    "description": "Full ContainAI experience: sysbox, data sync, SSH, DinD",
    "documentationURL": "https://github.com/novotnyllc/containai",
    "options": {
        "dataVolume": {
            "type": "string",
            "default": "",
            "description": "Name of cai data volume to mount (e.g., containai-data-myproject)"
        },
        "enableSsh": {
            "type": "boolean",
            "default": true,
            "description": "Run sshd for non-VS Code access"
        },
        "sshPort": {
            "type": "string",
            "default": "2322",
            "description": "SSH port to expose (will be forwarded)"
        },
        "installDocker": {
            "type": "boolean",
            "default": true,
            "description": "Install Docker for DinD"
        },
        "remoteUser": {
            "type": "string",
            "default": "auto",
            "description": "User for symlinks (auto-detects vscode/node/root)"
        }
    },
    "mounts": [],
    "postCreateCommand": "/usr/local/share/containai/init.sh",
    "postStartCommand": "/usr/local/share/containai/start.sh"
}
```

**install.sh** (runs at build time):
```bash
#!/usr/bin/env bash
set -euo pipefail

DATA_VOLUME="${DATAVOLUME:-}"
ENABLE_SSH="${ENABLESSH:-true}"
SSH_PORT="${SSHPORT:-2322}"
INSTALL_DOCKER="${INSTALLDOCKER:-true}"
REMOTE_USER="${REMOTEUSER:-auto}"

mkdir -p /usr/local/share/containai

# Store config for runtime scripts
cat > /usr/local/share/containai/config << EOF
DATA_VOLUME="$DATA_VOLUME"
ENABLE_SSH="$ENABLE_SSH"
SSH_PORT="$SSH_PORT"
REMOTE_USER="$REMOTE_USER"
EOF

# ══════════════════════════════════════════════════════════════════════
# SYSBOX VERIFICATION (kernel-enforced, cannot be faked)
# ══════════════════════════════════════════════════════════════════════

cat > /usr/local/share/containai/verify-sysbox.sh << 'VERIFY_EOF'
#!/usr/bin/env bash
set -euo pipefail

CHECKS_REQUIRED=3

verify_sysbox() {
    local passed=0

    echo "ContainAI Sysbox Verification"
    echo "═══════════════════════════════"

    # Check 1: UID mapping (sysbox maps 0 → high UID)
    if [[ -f /proc/self/uid_map ]]; then
        if ! grep -qE '^[[:space:]]*0[[:space:]]+0[[:space:]]' /proc/self/uid_map; then
            ((passed++))
            echo "  ✓ UID mapping: sysbox user namespace"
        else
            echo "  ✗ UID mapping: 0→0 (not sysbox)"
        fi
    fi

    # Check 2: Nested user namespace (sysbox allows, docker blocks)
    if unshare --user --map-root-user true 2>/dev/null; then
        ((passed++))
        echo "  ✓ Nested userns: allowed"
    else
        echo "  ✗ Nested userns: blocked"
    fi

    # Check 3: Sysbox-fs mounts
    if grep -qE "sysboxfs|fuse\.sysbox" /proc/mounts 2>/dev/null; then
        ((passed++))
        echo "  ✓ Sysboxfs: mounted"
    else
        echo "  ✗ Sysboxfs: not found"
    fi

    # Check 4: CAP_SYS_ADMIN works (sysbox userns)
    local testdir=$(mktemp -d)
    if mount -t tmpfs none "$testdir" 2>/dev/null; then
        umount "$testdir" 2>/dev/null
        ((passed++))
        echo "  ✓ Capabilities: CAP_SYS_ADMIN works"
    else
        echo "  ✗ Capabilities: mount denied"
    fi
    rmdir "$testdir" 2>/dev/null || true

    echo ""
    echo "Passed: $passed / $CHECKS_REQUIRED required"
    [[ $passed -ge $CHECKS_REQUIRED ]]
}

if ! verify_sysbox; then
    cat >&2 <<'ERROR'

╔═══════════════════════════════════════════════════════════════════╗
║  🛑 ContainAI: NOT running in sysbox                              ║
║                                                                   ║
║  To fix:                                                          ║
║    1. Install ContainAI: curl -fsSL https://containai.dev | sh    ║
║    2. Run: cai setup && cai import                                ║
║    3. Reopen this devcontainer                                    ║
╚═══════════════════════════════════════════════════════════════════╝
ERROR
    exit 1
fi
echo "✓ Running in sysbox sandbox"
VERIFY_EOF
chmod +x /usr/local/share/containai/verify-sysbox.sh

# ══════════════════════════════════════════════════════════════════════
# INIT SCRIPT (postCreateCommand - runs once after container created)
# Mirrors containai-init.sh: creates symlinks from ~ to data volume
# ══════════════════════════════════════════════════════════════════════

cat > /usr/local/share/containai/init.sh << 'INIT_EOF'
#!/usr/bin/env bash
set -euo pipefail

source /usr/local/share/containai/config

# Verify sysbox first
/usr/local/share/containai/verify-sysbox.sh || exit 1

DATA_DIR="/mnt/agent-data"

# Detect user home
if [[ "$REMOTE_USER" == "auto" ]]; then
    if [[ -d /home/vscode ]]; then
        USER_HOME="/home/vscode"
    elif [[ -d /home/node ]]; then
        USER_HOME="/home/node"
    else
        USER_HOME="$HOME"
    fi
else
    USER_HOME="/home/$REMOTE_USER"
fi

echo "ContainAI init: Setting up symlinks in $USER_HOME"

# Only set up symlinks if data volume is mounted
if [[ ! -d "$DATA_DIR" ]]; then
    echo "Warning: Data volume not mounted at $DATA_DIR"
    echo "Run 'cai import' on host, then rebuild container with dataVolume option"
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────
# Symlink creation (mirrors sync-manifest.toml structure)
# ─────────────────────────────────────────────────────────────────────

create_symlink() {
    local target="$1"  # Path in data volume (relative to $DATA_DIR)
    local link="$2"    # Path in user home (relative to $USER_HOME)

    local full_target="$DATA_DIR/$target"
    local full_link="$USER_HOME/$link"

    # Skip if target doesn't exist in volume
    [[ -e "$full_target" ]] || return 0

    # Create parent directory
    mkdir -p "$(dirname "$full_link")"

    # Remove existing (file or dir) and create symlink
    rm -rf "$full_link"
    ln -sfn "$full_target" "$full_link"
    echo "  ✓ $link → $target"
}

# Claude Code
create_symlink "claude/claude.json" ".claude.json"
create_symlink "claude/credentials.json" ".claude/.credentials.json"
create_symlink "claude/settings.json" ".claude/settings.json"
create_symlink "claude/settings.local.json" ".claude/settings.local.json"
create_symlink "claude/plugins" ".claude/plugins"
create_symlink "claude/skills" ".claude/skills"
create_symlink "claude/commands" ".claude/commands"
create_symlink "claude/agents" ".claude/agents"
create_symlink "claude/hooks" ".claude/hooks"
create_symlink "claude/CLAUDE.md" ".claude/CLAUDE.md"

# GitHub CLI
create_symlink "config/gh/hosts.yml" ".config/gh/hosts.yml"
create_symlink "config/gh/config.yml" ".config/gh/config.yml"

# Git
create_symlink "git/gitconfig" ".gitconfig"
create_symlink "git/gitignore_global" ".gitignore_global"

# Shell
create_symlink "shell/bash_aliases" ".bash_aliases_imported"
create_symlink "shell/zshrc" ".zshrc"
create_symlink "shell/inputrc" ".inputrc"
create_symlink "shell/oh-my-zsh-custom" ".oh-my-zsh/custom"

# Editors
create_symlink "editors/vimrc" ".vimrc"
create_symlink "editors/vim" ".vim"
create_symlink "config/nvim" ".config/nvim"

# Prompt
create_symlink "config/starship.toml" ".config/starship.toml"

# tmux
create_symlink "config/tmux" ".config/tmux"

# Other agents (optional - only if present in volume)
create_symlink "gemini/settings.json" ".gemini/settings.json"
create_symlink "codex/config.toml" ".codex/config.toml"

echo "ContainAI init complete"
INIT_EOF
chmod +x /usr/local/share/containai/init.sh

# ══════════════════════════════════════════════════════════════════════
# START SCRIPT (postStartCommand - runs every container start)
# ══════════════════════════════════════════════════════════════════════

cat > /usr/local/share/containai/start.sh << 'START_EOF'
#!/usr/bin/env bash
set -euo pipefail

source /usr/local/share/containai/config

# Start sshd if enabled (devcontainer-style, not systemd)
if [[ "$ENABLE_SSH" == "true" ]]; then
    if command -v sshd &>/dev/null; then
        # Generate host keys if missing
        [[ -f /etc/ssh/ssh_host_rsa_key ]] || ssh-keygen -A

        # Start sshd on configured port (non-privileged port for non-root)
        /usr/sbin/sshd -p "$SSH_PORT" -o "PidFile=/tmp/sshd.pid"
        echo "✓ sshd started on port $SSH_PORT"
    fi
fi

# Re-verify sysbox (in case container was restarted on different host)
/usr/local/share/containai/verify-sysbox.sh
START_EOF
chmod +x /usr/local/share/containai/start.sh

# ══════════════════════════════════════════════════════════════════════
# INSTALL DEPENDENCIES
# ══════════════════════════════════════════════════════════════════════

# SSH server (if enabled)
if [[ "$ENABLE_SSH" == "true" ]]; then
    apt-get update && apt-get install -y openssh-server
    mkdir -p /var/run/sshd
fi

# Docker for DinD (sysbox provides isolation)
if [[ "$INSTALL_DOCKER" == "true" ]]; then
    curl -fsSL https://get.docker.com | sh
    echo "Docker installed. DinD works without --privileged in sysbox."
fi

echo "ContainAI feature installed."
```

---

## Detection Matrix

| Scenario            | UID Map | unshare | Sysboxfs | Cap Probe | Total | Result |
|---------------------|---------|---------|----------|-----------|-------|--------|
| Sysbox (correct)    | ✓       | ✓       | ✓        | ✓         | 4     | PASS   |
| Regular docker      | ✗       | ✗      | ✗        | ✗         | 0     | FAIL   |
| Docker --privileged | ✗       | ✓       | ✗        | ✓         | 2     | FAIL   |

**Minimum required: 3 checks**

**Why these can't be faked**:
- UID mapping is kernel-enforced (you can't change /proc/self/uid_map)
- unshare capability requires kernel permission
- Sysboxfs mounts are kernel-level
- CAP_SYS_ADMIN in userns is kernel-enforced

---

## User Flows

### Flow A: New devcontainer with ContainAI

1. User has `cai setup` done (one-time)
2. User adds ContainAI feature to devcontainer.json:
   ```json
   {
       "image": "mcr.microsoft.com/devcontainers/python:3.11",
       "features": {
           "ghcr.io/novotnyllc/containai/feature:latest": {}
       }
   }
   ```
3. VS Code extension detects feature, sets dockerPath to cai-docker
4. User clicks "Reopen in Container"
5. cai-docker routes to containai-docker context (sysbox runtime)
6. Container starts **directly in sysbox**
7. postStartCommand verifies sysbox, passes
8. User works in secure sandbox

### Flow B: User without cai tries to open ContainAI devcontainer

1. User opens repo with ContainAI feature
2. VS Code extension warns: "cai not installed"
3. User clicks "Reopen in Container" anyway
4. Regular docker runs container (not sysbox)
5. postStartCommand runs verify-sandbox.sh
6. Kernel checks fail (UID map 0→0, unshare blocked, no sysboxfs)
7. **Hard-fail with clear error message**
8. User installs cai, reopens

### Flow C: Attacker tries to bypass

```bash
# None of these work:
docker run --env FAKE_SYSBOX=1 ...           # We don't check env vars
docker run --privileged ...                   # Only 2/4 checks pass
docker run --cap-add=ALL ...                  # Still not sysbox
```

The checks are kernel-enforced. No userspace bypass possible.

---

## containai-docker Context Setup

The context is configured by `cai setup`:

```bash
# Create context that uses sysbox runtime
docker context create containai-docker \
    --docker "host=unix:///var/run/docker.sock"

# Configure daemon to use sysbox for this context
# (actual implementation depends on platform)
```

**daemon.json for containai context**:
```json
{
    "default-runtime": "sysbox-runc",
    "runtimes": {
        "sysbox-runc": {
            "path": "/usr/bin/sysbox-runc"
        }
    }
}
```

---

## Implementation Phases

**1.1 cai-docker wrapper**
- [ ] Marker detection in devcontainer.json
- [ ] Context routing logic
- [ ] Install via `cai setup`

**1.2 ContainAI feature**
- [ ] Feature structure (devcontainer-feature.json, install.sh)
- [ ] Sysbox verification script (kernel checks)
- [ ] Optional Docker installation
- [ ] Publish to ghcr.io

**1.3 VS Code extension**
- [ ] Activate on devcontainer.json presence
- [ ] Detect ContainAI markers
- [ ] Set dockerPath to cai-docker
- [ ] Publish to VS Code Marketplace + Open VSX

### Phase 2: Testing
- [ ] Test: Sysbox → verification passes
- [ ] Test: Regular docker → verification fails
- [ ] Test: --privileged → verification fails (only 2 checks)
- [ ] Test: VS Code extension sets dockerPath
- [ ] Test: DinD works inside sysbox devcontainer

### Phase 3: Polish

- [ ] Documentation: "Adding ContainAI to your devcontainer"
- [ ] Template examples
- [ ] `cai doctor` checks for devcontainer compatibility

---

## Resolved Design Decisions

1. **No outer container**: Devcontainer runs directly in sysbox
2. **No env vars**: Kernel checks only (can't be faked)
3. **No cryptographic verification**: Not needed when running directly in sysbox
4. **Hard-block on failure**: No "reduced isolation" mode
5. **Extension distribution**: cai setup + marketplaces

---

## Acceptance Criteria

### Core
- [ ] cai-docker routes ContainAI devcontainers to sysbox context
- [ ] ContainAI feature installs on any base image
- [ ] Verification uses kernel-enforced checks only
- [ ] Hard-fail with clear message when not in sysbox

### VS Code Extension
- [ ] Detects ContainAI feature
- [ ] Sets dockerPath automatically
- [ ] Published to VS Code Marketplace and Open VSX

### Security
- [ ] Sysbox devcontainers pass verification (4 checks)
- [ ] Regular docker fails verification (0 checks)
- [ ] --privileged fails verification (2 checks, need 3)
- [ ] No env var or userspace bypass possible

---

## Docker Context Sync Architecture

The devcontainer needs access to the host's Docker contexts (for tools like Docker CLI), but with different socket paths. The host uses SSH-based context for `containai-docker`, while the container uses a local Unix socket.

### Context Directory Structure

```
~/.docker/contexts/           # Host's contexts (SSH sockets)
~/.docker-cai/contexts/       # ContainAI contexts (Unix sockets for container)
```

### Sync Rules

1. **Host → Container direction** (`~/.docker/contexts` → `~/.docker-cai/contexts`):
   - All contexts EXCEPT `containai-docker` are copied verbatim
   - The `containai-docker` context gets a modified socket path (Unix instead of SSH)

2. **Container → Host direction** (`~/.docker-cai/contexts` → `~/.docker/contexts`):
   - New contexts created in the container are synced back
   - `containai-docker` is excluded (different socket paths intentional)

3. **containai-docker special handling**:
   - Host version: SSH socket (`ssh://user@host`)
   - Container version: Unix socket (`unix:///var/run/docker.sock`)

### Sync Daemon

A lightweight watcher process monitors both directories for changes:
- Uses inotifywait (Linux) or fswatch (macOS) for efficiency
- Handles creates, deletes, and modifications
- Excludes `containai-docker` from bidirectional sync

### Implementation

Location: `src/lib/docker-context-sync.sh`

Key functions:
- `_cai_sync_docker_contexts()` - one-time sync
- `_cai_watch_docker_contexts()` - continuous watcher
- `_cai_is_containai_docker_context()` - check if context is the special one

---

## VS Code Server Environment Setup

VS Code Remote (Server) needs `DOCKER_CONFIG` set to use the ContainAI Docker configuration. This is done via server-env-setup scripts.

### Scripts

**Location**: Both scripts go in the user's home directory and must be executable.

**`~/.vscode-server/server-env-setup`**:
```bash
#!/bin/bash
export DOCKER_CONFIG="$HOME/.docker-cai"
```

**`~/.vscode-insiders/server-env-setup`** (for VS Code Insiders):
```bash
#!/bin/bash
export DOCKER_CONFIG="$HOME/.docker-cai"
```

### Script Requirements

- Scripts must be `chmod +x`
- Created by `cai setup` and/or the devcontainer feature
- VS Code Server sources these before launching

### Integration

These scripts ensure that when VS Code Server runs Docker commands (via Dev Containers extension), they use the ContainAI configuration which:
- Points to `~/.docker-cai/contexts` for context resolution
- Uses the Unix socket version of `containai-docker` context
- Maintains proper isolation from host Docker contexts

---

## References

- [Sysbox User Guide](https://github.com/nestybox/sysbox/tree/master/docs/user-guide)
- [Dev Container Features](https://containers.dev/implementors/features/)
- [fn-13-1c7 Research](../research/fn-13-1c7/RECOMMENDATIONS.md)
