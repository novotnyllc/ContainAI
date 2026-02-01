#!/usr/bin/env bash
# ContainAI initialization script for systemd containers
# Runs as a oneshot systemd service to prepare volume structure and workspace
set -euo pipefail

# Ensure HOME is set (systemd services may not have it even with User=)
: "${HOME:=/home/agent}"

# Canonical location
AGENT_WORKSPACE="${HOME}/workspace"

log() { printf '%s\n' "$*" >&2; }

# Helper: run command as root (using sudo -n for non-interactive fail-fast)
run_as_root() {
    if [[ $(id -u) -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo -n "$@" || {
            log "ERROR: sudo -n failed. Ensure agent user has passwordless sudo or run as root."
            return 1
        }
    else
        log "ERROR: Not root and sudo not available."
        return 1
    fi
}

# Data directory constant for path validation
readonly DATA_DIR="/mnt/agent-data"

# Helper: verify path resolves under DATA_DIR (prevents symlink traversal)
verify_path_under_data_dir() {
    local path="$1"
    local resolved

    resolved="$(realpath -m "$path" 2>/dev/null)" || {
        log "ERROR: Cannot resolve path: $path"
        return 1
    }

    if [[ "$resolved" != "${DATA_DIR}" && "$resolved" != "${DATA_DIR}/"* ]]; then
        log "ERROR: Path escapes data directory: $path -> $resolved"
        return 1
    fi
    return 0
}

# Helper: reject symlinks at any path (for security-sensitive operations)
reject_symlink() {
    local path="$1"
    if [[ -L "$path" ]]; then
        log "ERROR: Symlink detected where regular file/dir expected: $path"
        return 1
    fi
    return 0
}

# Helper: ensure a directory exists with type and symlink validation
ensure_dir() {
    local path="$1"

    reject_symlink "$path" || return 1
    verify_path_under_data_dir "$path" || return 1

    if [[ -e "$path" && ! -d "$path" ]]; then
        log "ERROR: Expected directory but found file: $path"
        return 1
    fi
    mkdir -p "$path"
}

# Helper: ensure a file exists with type and symlink validation, optionally init JSON
ensure_file() {
    local path="$1"
    local init_json="${2:-false}"

    reject_symlink "$path" || return 1
    verify_path_under_data_dir "$path" || return 1

    local parent
    parent="$(dirname "$path")"
    ensure_dir "$parent" || return 1

    if [[ -e "$path" && ! -f "$path" ]]; then
        log "ERROR: Expected file but found directory: $path"
        return 1
    fi

    if [[ "$init_json" == "true" ]]; then
        [[ -s "$path" ]] || echo '{}' >"$path"
    else
        touch "$path"
    fi
}

# Helper: apply chmod with symlink and path validation
safe_chmod() {
    local mode="$1"
    local path="$2"

    reject_symlink "$path" || return 1
    verify_path_under_data_dir "$path" || return 1

    chmod "$mode" "$path"
}

# Generated init-dirs script location
readonly INIT_DIRS_SCRIPT="/usr/local/lib/containai/init-dirs.sh"

# Ensure all volume structure exists for symlinks to work
# Sources the generated init-dirs.sh script from sync-manifest.toml
ensure_volume_structure() {
    run_as_root mkdir -p "${DATA_DIR}"
    run_as_root chown -R --no-dereference 1000:1000 "${DATA_DIR}"

    # Source generated init script if available
    # The script uses ensure_dir, ensure_file, and safe_chmod helpers defined above
    if [[ -f "$INIT_DIRS_SCRIPT" ]]; then
        log "[INFO] Sourcing generated init-dirs.sh"
        # shellcheck source=/dev/null
        source "$INIT_DIRS_SCRIPT"
    else
        log "[WARN] Generated init-dirs.sh not found, using fallback"
        # Minimal fallback for essential directories
        ensure_dir "${DATA_DIR}/claude"
        ensure_dir "${DATA_DIR}/config/gh"
        ensure_dir "${DATA_DIR}/git"
        ensure_dir "${DATA_DIR}/shell"
        ensure_dir "${DATA_DIR}/editors"
        ensure_dir "${DATA_DIR}/config"
    fi

    run_as_root chown -R --no-dereference 1000:1000 "${DATA_DIR}"
}

# Load environment variables from .env file safely
_load_env_file() {
    local env_file="${DATA_DIR}/.env"

    if [[ -L "$env_file" ]]; then
        log "[WARN] .env is symlink - skipping"
        return 0
    fi
    if [[ ! -f "$env_file" ]]; then
        return 0
    fi
    if [[ ! -r "$env_file" ]]; then
        log "[WARN] .env unreadable - skipping"
        return 0
    fi

    log "[INFO] Loading environment from .env"
    local line_num=0
    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
        if [[ -z "${line//[[:space:]]/}" ]]; then continue; fi
        if [[ "$line" =~ ^export[[:space:]]+ ]]; then
            line="${line#export}"
            line="${line#"${line%%[![:space:]]*}"}"
        fi
        if [[ "$line" != *=* ]]; then
            local key_token="${line#"${line%%[![:space:]]*}"}"
            key_token="${key_token%%[[:space:]]*}"
            [[ -z "$key_token" ]] && key_token="<unknown>"
            log "[WARN] line $line_num: no = found for '$key_token' - skipping"
            continue
        fi
        key="${line%%=*}"
        value="${line#*=}"
        if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            log "[WARN] line $line_num: invalid key '$key' - skipping"
            continue
        fi
        if [[ -z "${!key+x}" ]]; then
            export "$key=$value" || {
                log "[WARN] line $line_num: export failed for '$key'"
                continue
            }
        fi
    done <"$env_file"
}

# Setup git config from data volume
# New containers: ~/.gitconfig is symlinked to /mnt/agent-data/git/gitconfig (no copy needed)
# Legacy containers: copy from /mnt/agent-data/.gitconfig to ~/.gitconfig
_setup_git_config() {
    local dst="${HOME}/.gitconfig"

    # New containers have ~/.gitconfig as symlink - nothing to do
    if [[ -L "$dst" ]]; then
        return 0
    fi

    # Legacy container: find source file (old path, then new path)
    # Must be non-empty (-s) to avoid clobbering with empty placeholder file
    local src=""
    if [[ -s "${DATA_DIR}/.gitconfig" && ! -L "${DATA_DIR}/.gitconfig" ]]; then
        src="${DATA_DIR}/.gitconfig"
    elif [[ -s "${DATA_DIR}/git/gitconfig" && ! -L "${DATA_DIR}/git/gitconfig" ]]; then
        src="${DATA_DIR}/git/gitconfig"
    fi

    if [[ -z "$src" ]]; then
        return 0
    fi
    if [[ ! -r "$src" ]]; then
        log "[WARN] Source git config unreadable - skipping"
        return 0
    fi

    if [[ -e "$dst" && ! -f "$dst" ]]; then
        log "[WARN] Destination $dst exists but is not a regular file - skipping"
        return 0
    fi

    local tmp_dst="${dst}.tmp.$$"
    if cp "$src" "$tmp_dst" 2>/dev/null && mv "$tmp_dst" "$dst" 2>/dev/null; then
        log "[INFO] Git config loaded from data volume"
    else
        rm -f "$tmp_dst" 2>/dev/null || true
        log "[WARN] Failed to copy git config to $HOME"
    fi
}

update_agent_pw() {
    local agent_pw
    # Generate random password; suppress broken pipe error from tr when head exits early
    # (SIGPIPE is expected and benign, but causes script exit with set -eo pipefail)
    agent_pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 32)" || true
    # Use chpasswd which handles password hashing automatically
    # usermod -p expects an already-encrypted password, not plaintext
    printf '%s:%s\n' agent "${agent_pw}" | run_as_root chpasswd
}

# Setup workspace symlink from original host path to mount point
setup_workspace_symlink() {
    local host_path="${CAI_HOST_WORKSPACE:-}"
    local mount_path="/home/agent/workspace"

    if [[ -z "$host_path" ]]; then
        return 0
    fi

    if [[ "$host_path" == "$mount_path" ]]; then
        return 0
    fi

    # Validate host_path is absolute and under allowed prefixes
    if [[ "$host_path" != /* ]]; then
        log "[WARN] CAI_HOST_WORKSPACE must be absolute path: $host_path"
        return 0
    fi

    # Only allow paths under safe prefixes (blocks /etc, /usr, /bin, etc.)
    # Allowed: /home/, /tmp/, /mnt/ (WSL), /workspaces/ (devcontainers), /Users/ (macOS)
    case "$host_path" in
        /home/* | /tmp/* | /mnt/* | /workspaces/* | /Users/*) ;;
        *)
            log "[WARN] CAI_HOST_WORKSPACE must be under /home/, /tmp/, /mnt/, /workspaces/, or /Users/: $host_path"
            return 0
            ;;
    esac

    if ! run_as_root mkdir -p "$(dirname "$host_path")"; then
        log "[WARN] Failed to create parent directory for workspace symlink: $host_path"
        return 0
    fi

    if ! run_as_root ln -sfn "$mount_path" "$host_path"; then
        log "[WARN] Failed to create workspace symlink: $host_path -> $mount_path"
        return 0
    fi

    log "[INFO] Workspace symlink created: $host_path -> $mount_path"
}

# Main initialization
main() {
    log "[INFO] ContainAI initialization starting..."

    update_agent_pw
    ensure_volume_structure
    _load_env_file
    _setup_git_config
    setup_workspace_symlink

    log "[INFO] ContainAI initialization complete"
}

main "$@"
