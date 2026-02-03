# DevContainer Integration for ContainAI

## Executive Summary

Enable VS Code devcontainers to run securely in sysbox with minimal friction. Users install `cai` on their host (WSL/Mac), add our feature to any devcontainer, and a VS Code extension + smart docker wrapper routes the container through sysbox.

**Key insight**: The devcontainer runs **directly** in sysbox - no outer container, no nesting overhead. Our feature overlays onto whatever base image the user wants.

**Security invariant**: Hard-block if not running in sysbox. The wrapper enforces `--runtime=sysbox-runc` at launch time, and the container performs kernel-level verification on startup.

**Credential opt-in**: Credentials (GitHub tokens, Claude API keys) are NOT exposed by default. When `enableCredentials=false`:
1. The wrapper mounts a credential-sanitized volume (requires `cai import --no-secrets` or validation)
2. The init.sh skips symlinks to credential files
This defense-in-depth ensures untrusted code cannot access credentials even by reading the volume directly.

**Scope**: V1 supports Docker CLI only (not docker-compose). Compose support is explicitly out of scope.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│ User's Host (WSL/Mac)                                                   │
│                                                                         │
│   Prerequisites (via cai setup):                                        │
│   ├─ sysbox runtime installed                                           │
│   ├─ containai-docker context (platform-specific, reuse existing)       │
│   ├─ cai-docker wrapper at ~/.local/bin/cai-docker                      │
│   ├─ VS Code ContainAI extension                                        │
│   └─ Data volume (default: sandbox-agent-data, configurable)            │
│                                                                         │
│   ~/.ssh/containai.d/devcontainer-<workspace> (managed via Include):    │
│   ├─ Host containai-devcontainer-<workspace>                            │
│   │     HostName localhost                                              │
│   │     Port <allocated>     # Dynamically allocated, not fixed         │
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
│   │   ├─ /mnt/agent-data ← sandbox-agent-data volume (default)      │   │
│   │   └─ /workspaces/<project> ← host workspace (standard)          │   │
│   │                                                                 │   │
│   │   postCreateCommand (init.sh):                                  │   │
│   │   ├─ Verify sysbox (kernel checks)                              │   │
│   │   └─ Create symlinks: ~/.claude → /mnt/agent-data/claude, etc.  │   │
│   │                                                                 │   │
│   │   postStartCommand (start.sh):                                  │   │
│   │   ├─ Start sshd on $CONTAINAI_SSH_PORT (dynamic, not systemd)   │   │
│   │   └─ Re-verify sysbox                                           │   │
│   │                                                                 │   │
│   │   Services:                                                     │   │
│   │   ├─ sshd (dynamic port) - for non-VS Code access               │   │
│   │   └─ dockerd (DinD via postStart) - works without --privileged  │   │
│   │                                                                 │   │
│   │   Labels (for cai ps/stop/gc integration):                      │   │
│   │   ├─ containai.managed=true          # Required for CLI cmds    │   │
│   │   ├─ containai.type=devcontainer                                │   │
│   │   ├─ containai.devcontainer.workspace=<project-name>            │   │
│   │   └─ containai.created=<ISO8601-UTC>  # Portable timestamp      │   │
│   └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key points**:
- Devcontainer runs **directly** in sysbox (no outer container overhead)
- Data volume provides non-credential configs by default (credentials opt-in)
- SSH works via devcontainer port forwarding (not systemd), with dynamically allocated ports
- Labels enable `cai ps`, `cai stop`, GC integration (requires `containai.managed=true`)
- Reuses existing platform-specific context logic (WSL2 SSH bridge, macOS/Lima, etc.)

---

## What ContainAI Feature Provides

The feature replicates the full `cai` experience on any base image:

### 1. Sysbox Verification
- Kernel-enforced checks that cannot be faked
- Hard-fail if not running in sysbox

### 2. Data Volume Integration
- Mounts existing cai data volume (default: `sandbox-agent-data`, configurable via `dataVolume` option)
- Creates symlinks using existing `link-spec.json` and `link-repair.sh` (no duplicate manifest)
- **Credentials disabled by default** (defense-in-depth):
  1. **Wrapper level**: When `enableCredentials=false`, wrapper validates that the volume was created with `--no-secrets` flag (checks `.containai-no-secrets` marker file). If the marker is missing, refuses to mount and prompts user to run `cai import --no-secrets`.
  2. **Init level**: Skips symlinks to credential files as secondary protection.
- When `enableCredentials: true`: Full sync including tokens (requires explicit opt-in, no volume validation)

**Prerequisite**: `cai import --no-secrets` must create the `.containai-no-secrets` marker file in the volume root. This is a separate change to `src/lib/import.sh` that must be implemented before this epic.

### 3. Docker-in-Docker
- Works without `--privileged` (sysbox provides this)
- Nested containers work properly

### 4. SSH Access
- sshd runs as devcontainer service (not systemd)
- Port dynamically allocated per workspace (uses ContainAI port allocation with file locking)
- Port forwarded via devcontainer's `forwardPorts`
- Host SSH config managed via `~/.ssh/containai.d/<workspace>` with `Include` directive (reuses existing `_cai_setup_ssh_config` pattern)

### 5. Container Lifecycle
- Labels for cai GC integration
- Consistent naming for `cai ps` / `cai stop`

```json
{
    "image": "mcr.microsoft.com/devcontainers/python:3.11",
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {
            "dataVolume": "sandbox-agent-data",
            "enableCredentials": false,
            "enableSsh": true
        }
    }
}
```

**Security note**: Setting `enableCredentials: true` exposes GitHub tokens, Claude API keys, and other credentials to any code in the workspace. Only enable for trusted repositories.

---

## Component Design

### 1. Smart Docker Wrapper (`cai-docker`)

**Location**: `~/.local/bin/cai-docker`

**Purpose**:
- Detect ContainAI devcontainers via VS Code labels (not `--workspace-folder`)
- Enforce sysbox runtime at launch time (`--runtime=sysbox-runc`)
- Mount data volume automatically
- Add labels for GC integration
- Update host SSH config via `~/.ssh/containai.d/`

**Detection mechanism**: VS Code Dev Containers extension passes labels like:
- `--label devcontainer.local_folder=/path/to/workspace`
- `--label devcontainer.config_file=/path/to/.devcontainer/devcontainer.json`

The wrapper parses these labels to locate and read the devcontainer.json.

**JSONC parsing**: Uses a proper state-machine JSONC stripper (string/escape aware) via python3 or a bundled parser, NOT sed-based comment stripping (which fails on comment-like sequences in strings).

```bash
#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════════
# cai-docker: Smart docker wrapper for ContainAI devcontainers
# ══════════════════════════════════════════════════════════════════════

# Detect devcontainer via VS Code labels (docker create/run args)
# VS Code passes: --label devcontainer.config_file=... and devcontainer.local_folder=...
extract_devcontainer_labels() {
    local config_file="" local_folder=""
    local prev=""
    for arg in "$@"; do
        if [[ "$prev" == "--label" ]]; then
            case "$arg" in
                devcontainer.config_file=*) config_file="${arg#*=}" ;;
                devcontainer.local_folder=*) local_folder="${arg#*=}" ;;
            esac
        fi
        prev="$arg"
    done
    printf '%s\n%s\n' "$config_file" "$local_folder"
}

# Parse JSONC safely using python3 (handles strings, multiline comments correctly)
strip_jsonc_comments() {
    python3 -c "
import sys, re, json
content = sys.stdin.read()
# Remove // comments (not inside strings)
result = []
in_string = False
escape = False
i = 0
while i < len(content):
    c = content[i]
    if escape:
        result.append(c)
        escape = False
    elif c == '\\\\' and in_string:
        result.append(c)
        escape = True
    elif c == '\"' and not escape:
        in_string = not in_string
        result.append(c)
    elif not in_string and c == '/' and i+1 < len(content):
        if content[i+1] == '/':
            # Skip to end of line
            while i < len(content) and content[i] != '\n':
                i += 1
            continue
        elif content[i+1] == '*':
            # Skip to */
            i += 2
            while i+1 < len(content) and not (content[i] == '*' and content[i+1] == '/'):
                i += 1
            i += 2
            continue
        else:
            result.append(c)
    else:
        result.append(c)
    i += 1
print(''.join(result))
"
}

# Check for containai feature in devcontainer.json
has_containai_feature() {
    local config_file="$1"
    [[ -f "$config_file" ]] || return 1
    strip_jsonc_comments < "$config_file" | grep -qE '"containai"'
}

# Get data volume from devcontainer.json or default
get_data_volume() {
    local config_file="$1"
    local vol
    if [[ -f "$config_file" ]]; then
        vol=$(strip_jsonc_comments < "$config_file" | \
              python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('features',{}).get('ghcr.io/novotnyllc/containai/feature:latest',{}).get('dataVolume',''))" 2>/dev/null || echo "")
        [[ -n "$vol" ]] && echo "$vol" && return
    fi
    # Default: sandbox-agent-data (matches existing cai volume naming)
    echo "sandbox-agent-data"
}

# Allocate SSH port using ContainAI port allocation (reuse existing logic)
# This coordinates with _cai_allocate_ssh_port from src/lib/ssh.sh
# Uses SAME lock file to prevent races with concurrent cai commands
allocate_ssh_port() {
    local workspace_name="$1"

    # Use SAME paths as cai for coordination
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/containai"
    local port_dir="$config_dir/ports"
    local port_file="$port_dir/devcontainer-${workspace_name}"
    local lock_file="$config_dir/.ssh-port.lock"  # SAME as cai uses
    mkdir -p "$port_dir"

    # Check if we already have a port for this workspace (no lock needed for read)
    if [[ -f "$port_file" ]]; then
        cat "$port_file"
        return
    fi

    # Port allocation - lock is already held by caller (main)
    # This function just does the allocation logic

    # Check if already allocated for this workspace
    if [[ -f "$port_file" ]]; then
        cat "$port_file"
        return
    fi

    # Get reserved ports from docker labels
    local reserved_ports
    reserved_ports=$(docker --context containai-docker ps -a \
        --filter "label=containai.ssh-port" \
        --format '{{.Label "containai.ssh-port"}}' 2>/dev/null | sort -u || true)

    # Also check port files from cai (shared directory)
    for f in "$port_dir"/*; do
        [[ -f "$f" ]] && reserved_ports="$reserved_ports"$'\n'"$(cat "$f")"
    done

    # Cross-platform port-in-use check
    is_port_in_use() {
        local port="$1"
        if command -v ss &>/dev/null; then
            ss -tln 2>/dev/null | grep -q ":$port " && return 0
        elif command -v lsof &>/dev/null; then
            lsof -iTCP:"$port" -sTCP:LISTEN &>/dev/null && return 0
        fi
        return 1
    }

    # Find next available port in range 2400-2499 (devcontainer range)
    local port
    for port in $(seq 2400 2499); do
        if ! echo "$reserved_ports" | grep -qw "$port" && ! is_port_in_use "$port"; then
            printf '%s' "$port" > "$port_file"
            printf '%s' "$port"
            return
        fi
    done

    # Fallback (should not happen with 100 ports available)
    printf '2322'
}

# Update SSH config via ~/.ssh/containai.d/ (reuses existing pattern)
update_ssh_config() {
    local workspace_name="$1"
    local ssh_port="$2"
    local host_alias="containai-devcontainer-${workspace_name}"
    local ssh_dir="$HOME/.ssh/containai.d"
    local config_file="$ssh_dir/devcontainer-${workspace_name}"

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Ensure Include directive exists in main config
    local main_config="$HOME/.ssh/config"
    if ! grep -q 'Include containai.d/\*' "$main_config" 2>/dev/null; then
        printf 'Include containai.d/*\n\n%s' "$(cat "$main_config" 2>/dev/null || true)" > "$main_config"
        chmod 600 "$main_config"
    fi

    # Write workspace-specific config
    cat > "$config_file" << EOF
# ContainAI devcontainer: $workspace_name
Host $host_alias
    HostName localhost
    Port $ssh_port
    User vscode
EOF
    chmod 600 "$config_file"
    printf 'SSH: ssh %s\n' "$host_alias" >&2
}

# Check if this is a docker create/run command
is_container_create_command() {
    for arg in "$@"; do
        case "$arg" in
            create|run) return 0 ;;
            container) continue ;;  # docker container create/run
            -*)  continue ;;
            *) return 1 ;;
        esac
    done
    return 1
}

main() {
    # Only intercept docker create/run commands
    if ! is_container_create_command "$@"; then
        exec docker "$@"
    fi

    # Extract VS Code devcontainer labels
    local labels
    labels=$(extract_devcontainer_labels "$@")
    local config_file local_folder
    config_file=$(echo "$labels" | head -1)
    local_folder=$(echo "$labels" | tail -1)

    # Check if this is a ContainAI devcontainer
    if [[ -z "$config_file" ]] || ! has_containai_feature "$config_file"; then
        exec docker "$@"
    fi

    # Verify containai-docker context exists
    if ! docker context inspect containai-docker &>/dev/null; then
        cat >&2 <<'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║  ContainAI: Not set up. Run: cai setup                            ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
        exit 1
    fi

    local workspace_name
    workspace_name=$(basename "$local_folder")

    local data_volume
    data_volume=$(get_data_volume "$config_file")

    # IMPORTANT: Acquire port lock and HOLD IT across allocation + docker exec
    # This prevents races with concurrent cai commands
    # The lock is released when docker exec replaces this process (or on error exit)
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/containai"
    local lock_file="$config_dir/.ssh-port.lock"
    mkdir -p "$config_dir"

    # Acquire lock (held until exec or exit)
    # Linux: flock coordinates with cai
    # macOS: flock not available - V1 LIMITATION (see below)
    if command -v flock &>/dev/null; then
        exec 200>"$lock_file"
        flock -w 10 200 || {
            printf 'Warning: Could not acquire port lock\n' >&2
        }
    fi
    # V1 LIMITATION (macOS): Without flock, concurrent cai + cai-docker
    # operations may race on port allocation. Mitigation: port files provide
    # best-effort coordination. Full fix requires V2 enhancement to cai.

    local ssh_port
    ssh_port=$(allocate_ssh_port "$workspace_name")

    # Check enableCredentials from devcontainer.json
    local enable_credentials
    enable_credentials=$(strip_jsonc_comments < "$config_file" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('features',{}).get('ghcr.io/novotnyllc/containai/feature:latest',{}).get('enableCredentials','false'))" 2>/dev/null || echo "false")

    # Validate volume for credentials (defense-in-depth)
    local mount_volume=true
    if [[ "$enable_credentials" != "true" ]]; then
        # Check for no-secrets marker in volume
        if ! docker --context containai-docker run --rm -v "${data_volume}:/vol:ro" alpine test -f /vol/.containai-no-secrets 2>/dev/null; then
            printf 'Warning: Volume %s may contain credentials.\n' "$data_volume" >&2
            printf 'Either set enableCredentials: true, or recreate with: cai import --no-secrets\n' >&2
            mount_volume=false
        fi
    fi

    # Build modified args with injected options
    local -a args=()
    local found_create=false

    for arg in "$@"; do
        args+=("$arg")

        # Inject after run/create command
        if [[ "$arg" == "run" || "$arg" == "create" ]]; then
            found_create=true

            # Enforce sysbox runtime at launch time
            args+=("--runtime=sysbox-runc")

            # Mount data volume if validated
            if [[ "$mount_volume" == "true" ]] && docker --context containai-docker volume inspect "$data_volume" &>/dev/null; then
                args+=("-v" "${data_volume}:/mnt/agent-data:rw")
            fi

            # Pass SSH port to container via env var
            args+=("-e" "CONTAINAI_SSH_PORT=${ssh_port}")

            # Labels for cai ps/stop/gc integration (complete set)
            args+=("--label" "containai.managed=true")
            args+=("--label" "containai.type=devcontainer")
            args+=("--label" "containai.devcontainer.workspace=${workspace_name}")
            args+=("--label" "containai.data-volume=${data_volume}")
            args+=("--label" "containai.ssh-port=${ssh_port}")
            args+=("--label" "containai.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)")
        fi
    done

    # Update SSH config
    update_ssh_config "$workspace_name" "$ssh_port"

    # Execute with containai-docker context
    exec docker --context containai-docker "${args[@]}"
}

main "$@"
```

**Portability notes**:
- Uses `date -u +%Y-%m-%dT%H:%M:%SZ` (POSIX portable) instead of `date -Iseconds` (GNU only)
- SSH config via `~/.ssh/containai.d/` with Include (avoids brittle sed block edits)
- JSONC parsing via python3 state machine (not sed which breaks on strings)

**V1 Limitations**:
- Docker CLI only (not docker-compose)
- No compose-aware injection

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
import { parse as parseJSONC } from 'jsonc-parser';  // Proper JSONC parser (npm package)

export function activate(context: vscode.ExtensionContext) {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) return;

    const devcontainerPath = findDevcontainerJson(workspaceFolder.uri.fsPath);
    if (!devcontainerPath) return;

    if (hasContainAIFeature(devcontainerPath)) {
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

// Use proper JSONC parser - DO NOT use regex-based comment stripping
// which fails on comment-like sequences in strings
function hasContainAIFeature(devcontainerPath: string): boolean {
    const content = fs.readFileSync(devcontainerPath, 'utf8');
    const parsed = parseJSONC(content);
    const features = parsed?.features || {};
    return Object.keys(features).some(key => key.includes('containai'));
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
    "description": "ContainAI experience: sysbox verification, data sync (no creds by default), SSH, DinD",
    "documentationURL": "https://github.com/novotnyllc/containai",
    "options": {
        "dataVolume": {
            "type": "string",
            "default": "sandbox-agent-data",
            "description": "Name of cai data volume to mount"
        },
        "enableCredentials": {
            "type": "boolean",
            "default": false,
            "description": "SECURITY: Sync credential files (GH tokens, Claude API keys). Only enable for trusted repos."
        },
        "enableSsh": {
            "type": "boolean",
            "default": true,
            "description": "Run sshd for non-VS Code access"
        },
        "installDocker": {
            "type": "boolean",
            "default": true,
            "description": "Install Docker for DinD (starts in postStartCommand)"
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

**Platform support**: Debian/Ubuntu only in V1. Clear error on other distros.

```bash
#!/usr/bin/env bash
set -euo pipefail

DATA_VOLUME="${DATAVOLUME:-sandbox-agent-data}"
ENABLE_CREDENTIALS="${ENABLECREDENTIALS:-false}"
ENABLE_SSH="${ENABLESSH:-true}"
INSTALL_DOCKER="${INSTALLDOCKER:-true}"
REMOTE_USER="${REMOTEUSER:-auto}"

# ══════════════════════════════════════════════════════════════════════
# PLATFORM CHECK (Debian/Ubuntu only in V1)
# ══════════════════════════════════════════════════════════════════════
if ! command -v apt-get &>/dev/null; then
    cat >&2 <<'ERROR'
╔═══════════════════════════════════════════════════════════════════╗
║  ContainAI feature requires Debian/Ubuntu base image              ║
║  Alpine, Fedora, and other distros not yet supported              ║
╚═══════════════════════════════════════════════════════════════════╝
ERROR
    exit 1
fi

mkdir -p /usr/local/share/containai

# Store config for runtime scripts
cat > /usr/local/share/containai/config << EOF
DATA_VOLUME="$DATA_VOLUME"
ENABLE_CREDENTIALS="$ENABLE_CREDENTIALS"
ENABLE_SSH="$ENABLE_SSH"
REMOTE_USER="$REMOTE_USER"
EOF

# ══════════════════════════════════════════════════════════════════════
# SYSBOX VERIFICATION
# Threat model: Defense-in-depth. The wrapper enforces --runtime=sysbox-runc
# at launch, and this script verifies kernel-level sysbox indicators.
# The sysboxfs check is MANDATORY (sysbox-unique, cannot be faked).
# ══════════════════════════════════════════════════════════════════════

cat > /usr/local/share/containai/verify-sysbox.sh << 'VERIFY_EOF'
#!/usr/bin/env bash
set -euo pipefail

verify_sysbox() {
    local passed=0
    local sysboxfs_found=false

    printf 'ContainAI Sysbox Verification\n'
    printf '═══════════════════════════════\n'

    # MANDATORY CHECK: Sysbox-fs mounts (sysbox-unique, cannot be faked)
    # This check MUST pass - it's the definitive sysbox indicator
    if grep -qE 'sysboxfs|fuse\.sysbox' /proc/mounts 2>/dev/null; then
        sysboxfs_found=true
        ((passed++))
        printf '  ✓ Sysboxfs: mounted (REQUIRED)\n'
    else
        printf '  ✗ Sysboxfs: not found (REQUIRED)\n'
    fi

    # Check 2: UID mapping (sysbox maps 0 → high UID)
    if [[ -f /proc/self/uid_map ]]; then
        if ! grep -qE '^[[:space:]]*0[[:space:]]+0[[:space:]]' /proc/self/uid_map; then
            ((passed++))
            printf '  ✓ UID mapping: sysbox user namespace\n'
        else
            printf '  ✗ UID mapping: 0→0 (not sysbox)\n'
        fi
    fi

    # Check 3: Nested user namespace (sysbox allows, docker blocks)
    if unshare --user --map-root-user true 2>/dev/null; then
        ((passed++))
        printf '  ✓ Nested userns: allowed\n'
    else
        printf '  ✗ Nested userns: blocked\n'
    fi

    # Check 4: CAP_SYS_ADMIN works (sysbox userns)
    local testdir
    testdir=$(mktemp -d)
    if mount -t tmpfs none "$testdir" 2>/dev/null; then
        umount "$testdir" 2>/dev/null
        ((passed++))
        printf '  ✓ Capabilities: CAP_SYS_ADMIN works\n'
    else
        printf '  ✗ Capabilities: mount denied\n'
    fi
    rmdir "$testdir" 2>/dev/null || true

    printf '\nPassed: %d checks\n' "$passed"

    # HARD REQUIREMENT: sysboxfs MUST be present
    # This is the sysbox-unique predicate that cannot be faked
    if [[ "$sysboxfs_found" != "true" ]]; then
        printf 'FAIL: sysboxfs not detected (mandatory for sysbox)\n' >&2
        return 1
    fi

    # Also require at least 2 other checks for defense-in-depth
    [[ $passed -ge 3 ]]
}

if ! verify_sysbox; then
    cat >&2 <<'ERROR'

╔═══════════════════════════════════════════════════════════════════╗
║  🛑 ContainAI: NOT running in sysbox                              ║
║                                                                   ║
║  The wrapper should enforce --runtime=sysbox-runc at launch.      ║
║  If you see this, the devcontainer was started incorrectly.       ║
║                                                                   ║
║  To fix:                                                          ║
║    1. Install ContainAI: curl -fsSL https://containai.dev | sh    ║
║    2. Run: cai setup                                              ║
║    3. Ensure VS Code uses cai-docker wrapper                      ║
║    4. Reopen this devcontainer                                    ║
╚═══════════════════════════════════════════════════════════════════╝
ERROR
    exit 1
fi
printf '✓ Running in sysbox sandbox\n'
VERIFY_EOF
chmod +x /usr/local/share/containai/verify-sysbox.sh

# ══════════════════════════════════════════════════════════════════════
# INIT SCRIPT (postCreateCommand - runs once after container created)
# Uses existing link-spec.json and link-repair.sh from ContainAI
# NO DUPLICATE SYMLINK LISTS - reads from canonical source
# ══════════════════════════════════════════════════════════════════════

cat > /usr/local/share/containai/init.sh << 'INIT_EOF'
#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source /usr/local/share/containai/config

# Verify sysbox first
/usr/local/share/containai/verify-sysbox.sh || exit 1

DATA_DIR="/mnt/agent-data"
LINK_SPEC="/usr/local/lib/containai/link-spec.json"

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

printf 'ContainAI init: Setting up symlinks in %s\n' "$USER_HOME"

# Only set up symlinks if data volume is mounted
if [[ ! -d "$DATA_DIR" ]]; then
    printf 'Warning: Data volume not mounted at %s\n' "$DATA_DIR"
    printf 'Run "cai import" on host, then rebuild container with dataVolume option\n'
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────
# Use existing link-repair.sh from ContainAI (no duplicate manifest)
# The feature install copies link-spec.json to /usr/local/lib/containai/
# ─────────────────────────────────────────────────────────────────────

# List of credential-bearing files to SKIP unless enableCredentials=true
# These contain tokens/API keys that should not be exposed to untrusted code
CREDENTIAL_TARGETS=(
    "/mnt/agent-data/config/gh/hosts.yml"        # GitHub token
    "/mnt/agent-data/claude/credentials.json"    # Claude API key
    "/mnt/agent-data/codex/config.toml"          # May contain keys
    "/mnt/agent-data/gemini/settings.json"       # May contain keys
)

is_credential_file() {
    local target="$1"
    for cred in "${CREDENTIAL_TARGETS[@]}"; do
        [[ "$target" == "$cred" ]] && return 0
    done
    return 1
}

# Check if link-spec.json exists
if [[ ! -f "$LINK_SPEC" ]]; then
    printf 'Warning: link-spec.json not found at %s\n' "$LINK_SPEC"
    printf 'Feature may not be fully installed\n'
    exit 0
fi

# Get home_dir from link-spec.json (usually /home/agent in container images)
SPEC_HOME=$(jq -r '.home_dir // "/home/agent"' "$LINK_SPEC")

# Process links from link-spec.json using jq
links_count=$(jq -r '.links | length' "$LINK_SPEC")

for i in $(seq 0 $((links_count - 1))); do
    link=$(jq -r ".links[$i].link" "$LINK_SPEC")
    target=$(jq -r ".links[$i].target" "$LINK_SPEC")
    remove_first=$(jq -r ".links[$i].remove_first // false" "$LINK_SPEC")

    # Skip credential files unless explicitly enabled
    if [[ "$ENABLE_CREDENTIALS" != "true" ]] && is_credential_file "$target"; then
        printf '  ⊘ %s (credentials disabled)\n' "$link"
        continue
    fi

    # Rewrite link path from spec's home_dir to detected USER_HOME
    # e.g., /home/agent/.config -> /home/vscode/.config
    link="${link/$SPEC_HOME/$USER_HOME}"

    # Skip if target doesn't exist
    [[ -e "$target" ]] || continue

    # Create parent directory
    mkdir -p "$(dirname "$link")"

    # Handle remove_first for directories (ln -sfn can't replace directories)
    if [[ -d "$link" && ! -L "$link" ]]; then
        if [[ "$remove_first" == "true" || "$remove_first" == "1" ]]; then
            rm -rf "$link"
        else
            printf '  ✗ %s (directory exists, remove_first not set)\n' "$link" >&2
            continue
        fi
    fi

    # Create symlink (ln -sfn handles existing files/symlinks)
    if ln -sfn "$target" "$link" 2>/dev/null; then
        printf '  ✓ %s → %s\n' "$link" "$target"
    else
        printf '  ✗ %s (failed)\n' "$link" >&2
    fi
done

printf 'ContainAI init complete\n'
INIT_EOF
chmod +x /usr/local/share/containai/init.sh

# ══════════════════════════════════════════════════════════════════════
# START SCRIPT (postStartCommand - runs every container start)
# Handles: sysbox verification, sshd, dockerd (DinD)
# ══════════════════════════════════════════════════════════════════════

cat > /usr/local/share/containai/start.sh << 'START_EOF'
#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source /usr/local/share/containai/config

# Re-verify sysbox first (in case container was restarted on different host)
/usr/local/share/containai/verify-sysbox.sh || exit 1

# ─────────────────────────────────────────────────────────────────────
# Start sshd if enabled (devcontainer-style, not systemd)
# Port is dynamically allocated by the wrapper, check container labels
# ─────────────────────────────────────────────────────────────────────
if [[ "$ENABLE_SSH" == "true" ]]; then
    if command -v sshd &>/dev/null; then
        # Generate host keys if missing
        [[ -f /etc/ssh/ssh_host_rsa_key ]] || ssh-keygen -A

        # Get SSH port from container label or default
        SSH_PORT="${CONTAINAI_SSH_PORT:-2322}"

        # Check if already running
        if [[ -f /tmp/sshd.pid ]] && kill -0 "$(cat /tmp/sshd.pid)" 2>/dev/null; then
            printf '✓ sshd already running on port %s\n' "$SSH_PORT"
        else
            /usr/sbin/sshd -p "$SSH_PORT" -o "PidFile=/tmp/sshd.pid"
            printf '✓ sshd started on port %s\n' "$SSH_PORT"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────
# Start dockerd for DinD (if Docker installed and not already running)
# Sysbox provides the isolation, no --privileged needed
# ─────────────────────────────────────────────────────────────────────
start_dockerd() {
    local pidfile="/var/run/docker.pid"
    local logfile="/var/log/containai-dockerd.log"
    local retries=30

    # Already running?
    if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        printf '✓ dockerd already running\n'
        return 0
    fi

    # Start dockerd in background
    printf 'Starting dockerd...\n'
    nohup dockerd --pidfile="$pidfile" > "$logfile" 2>&1 &

    # Wait for socket
    local i=0
    while [[ $i -lt $retries ]]; do
        if docker info &>/dev/null; then
            printf '✓ dockerd started (DinD ready)\n'
            return 0
        fi
        sleep 1
        ((i++))
    done

    printf '✗ dockerd failed to start (see %s)\n' "$logfile" >&2
    return 1
}

if command -v dockerd &>/dev/null; then
    start_dockerd || printf 'Warning: DinD not available\n' >&2
fi

printf '✓ ContainAI devcontainer ready\n'
START_EOF
chmod +x /usr/local/share/containai/start.sh

# ══════════════════════════════════════════════════════════════════════
# INSTALL DEPENDENCIES
# ══════════════════════════════════════════════════════════════════════

# Install jq for JSON parsing (required for link-spec.json)
apt-get update && apt-get install -y jq

# SSH server (if enabled)
if [[ "$ENABLE_SSH" == "true" ]]; then
    apt-get install -y openssh-server
    mkdir -p /var/run/sshd
fi

# Docker for DinD (sysbox provides isolation)
# Note: dockerd startup happens in postStartCommand, not here
if [[ "$INSTALL_DOCKER" == "true" ]]; then
    curl -fsSL https://get.docker.com | sh
    # Add devcontainer user to docker group (vscode/node/root)
    if id -u vscode &>/dev/null; then
        usermod -aG docker vscode
    elif id -u node &>/dev/null; then
        usermod -aG docker node
    fi
    printf 'Docker installed. DinD starts via postStartCommand.\n'
fi

# Copy link-spec.json from ContainAI (if available in image or fetch)
# This allows symlink creation without hardcoded paths
mkdir -p /usr/local/lib/containai
if [[ -f /usr/local/lib/containai/link-spec.json ]]; then
    printf 'link-spec.json already present\n'
else
    # Fetch from release or use bundled version
    printf 'Note: link-spec.json should be bundled with feature\n'
fi

printf 'ContainAI feature installed.\n'
```

---

## Detection Matrix

| Scenario              | Sysboxfs | UID Map | unshare | Cap Probe | Total | Result |
|-----------------------|----------|---------|---------|-----------|-------|--------|
| Sysbox (correct)      | ✓ (REQ)  | ✓       | ✓       | ✓         | 4     | PASS   |
| Regular docker        | ✗        | ✗       | ✗       | ✗         | 0     | FAIL   |
| Docker --privileged   | ✗        | ✗       | ✓       | ✓         | 2     | FAIL   |
| userns-remap + --priv | ✗        | ✓       | ✓       | ✓         | 3     | FAIL   |

**Verification requirements**:
1. **Sysboxfs MANDATORY**: The sysboxfs mount check MUST pass (sysbox-unique indicator)
2. **Defense-in-depth**: At least 3 total checks must pass

**Why sysboxfs is unforgeable**:
- Sysbox-fs is a FUSE filesystem implemented by sysbox-fs daemon
- It intercepts specific procfs/sysfs reads to provide VM-like behavior
- Only sysbox-runc can set up these mounts - no userspace bypass possible
- Even with userns-remap + --privileged, you cannot fake sysboxfs mounts

**Defense-in-depth**: The wrapper ALSO enforces `--runtime=sysbox-runc` at launch time, so even if verification could somehow be bypassed, the container cannot start without sysbox.

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

**Important**: Reuse existing platform-specific context logic from `cai setup`. Do NOT hardcode Unix socket.

The `containai-docker` context is already set up by `cai setup` with platform-specific endpoints:
- **WSL2**: SSH bridge to WSL2 Docker daemon
- **macOS/Lima**: Socket to Lima VM
- **Native Linux**: Unix socket to local Docker daemon

The wrapper uses `--runtime=sysbox-runc` to enforce sysbox at launch time, regardless of context endpoint:

```bash
# Wrapper enforces runtime, context handles connection
exec docker --context containai-docker --runtime=sysbox-runc "${args[@]}"
```

**daemon.json** (configured by `cai setup`, not by devcontainer wrapper):
```json
{
    "runtimes": {
        "sysbox-runc": {
            "path": "/usr/bin/sysbox-runc"
        }
    }
}
```

The context creation is handled by existing functions:
- `_cai_setup_containai_docker_context()`
- `_cai_auto_repair_containai_context()`
- `_cai_expected_docker_host()`

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
- [ ] cai-docker detects ContainAI devcontainers via VS Code labels (not --workspace-folder)
- [ ] cai-docker enforces `--runtime=sysbox-runc` at launch time
- [ ] cai-docker routes to existing containai-docker context (platform-specific)
- [ ] ContainAI feature installs on Debian/Ubuntu base images (clear error on others)
- [ ] Verification requires sysboxfs mount (mandatory) + 2 other checks
- [ ] Hard-fail with clear message when not in sysbox

### Security
- [ ] Credentials NOT synced by default (`enableCredentials: false`)
- [ ] Sysbox devcontainers pass verification (sysboxfs + 3 total)
- [ ] Regular docker fails verification (no sysboxfs)
- [ ] userns-remap + --privileged fails (no sysboxfs)
- [ ] No env var or userspace bypass possible

### VS Code Extension
- [ ] Detects ContainAI feature via proper JSONC parsing
- [ ] Sets dockerPath automatically
- [ ] Published to VS Code Marketplace and Open VSX

### Integration
- [ ] Labels include complete set: `containai.managed`, `containai.data-volume`, `containai.ssh-port`
- [ ] SSH ports dynamically allocated (checks existing ports, not fixed 2322)
- [ ] SSH port passed to container via `-e CONTAINAI_SSH_PORT=<port>`
- [ ] SSH config via `~/.ssh/containai.d/` with Include directive
- [ ] Uses portable timestamps (`date -u +%Y-%m-%dT%H:%M:%SZ`)
- [ ] DinD starts via postStartCommand with retry/idempotency
- [ ] link-spec.json paths rewritten from `/home/agent` to detected user home
- [ ] `remove_first` handled for directory symlinks

### V1 Scope
- [ ] Docker CLI only (not docker-compose)
- [ ] Debian/Ubuntu only (clear error on other distros)
- [ ] Task 8 (Docker context sync) DEFERRED - no clear V1 use case
- [ ] Task 9 (VS Code server-env-setup) DEFERRED - depends on task 8

### V1 Known Limitations
- **macOS port allocation race**: On macOS, `flock` is not available. Concurrent `cai` and `cai-docker` operations may race on SSH port allocation. Mitigation: port reservation files provide best-effort coordination. Full fix requires V2 enhancement where `cai` reads shared port files.

### Task Dependencies
- [ ] Task 10 (Add no-secrets marker to cai import) - must complete before task 1 can validate credentials
- Task 1 depends on: Task 10
- Tasks 1, 2 can run in parallel after Task 10
- Task 3 can run independently

---

## Docker Context Sync Architecture

**STATUS: DEFERRED (V2)**

The original rationale for syncing Docker contexts between host and container is unclear for the devcontainer use case:

- **DinD in devcontainer**: The container runs its own dockerd, so it doesn't need host contexts
- **Host Docker access**: Devcontainers typically don't need to talk to the host Docker daemon
- **Context complexity**: Syncing contexts adds complexity without clear benefit

**Recommendation**: Cut this from V1. If a concrete use case emerges (e.g., "I need to manage host containers from within devcontainer"), implement it then with clear requirements.

If needed in V2, the approach would be:
- One-time sync during setup (not continuous watcher)
- Explicit user opt-in via feature option
- Clear documentation of the use case

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
