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

readonly BUILTIN_MANIFESTS_DIR="/opt/containai/manifests"

# Ensure all volume structure exists for symlinks to work
# Uses native cai manifest apply logic from built-in manifests
ensure_volume_structure() {
    run_as_root mkdir -p "${DATA_DIR}"
    run_as_root chown -R --no-dereference 1000:1000 "${DATA_DIR}"

    if command -v cai >/dev/null 2>&1 && [[ -d "$BUILTIN_MANIFESTS_DIR" ]]; then
        log "[INFO] Applying init directory policy from manifests"
        if ! cai manifest apply init-dirs "$BUILTIN_MANIFESTS_DIR" --data-dir "$DATA_DIR"; then
            log "[WARN] Native init-dir apply failed, using fallback"
            ensure_dir "${DATA_DIR}/claude"
            ensure_dir "${DATA_DIR}/config/gh"
            ensure_dir "${DATA_DIR}/git"
            ensure_file "${DATA_DIR}/git/gitconfig"
            ensure_file "${DATA_DIR}/git/gitignore_global"
            ensure_dir "${DATA_DIR}/shell"
            ensure_dir "${DATA_DIR}/editors"
            ensure_dir "${DATA_DIR}/config"
        fi
    else
        log "[WARN] Built-in manifests or cai binary not found, using fallback"
        # Minimal fallback for essential directories
        ensure_dir "${DATA_DIR}/claude"
        ensure_dir "${DATA_DIR}/config/gh"
        ensure_dir "${DATA_DIR}/git"
        ensure_file "${DATA_DIR}/git/gitconfig"
        ensure_file "${DATA_DIR}/git/gitignore_global"
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

# Migrate git config from old volume path to new volume path
# Old: /mnt/agent-data/.gitconfig
# New: /mnt/agent-data/git/gitconfig (symlinked to ~/.gitconfig)
# This runs on every startup to handle upgrades from older container images
_migrate_git_config() {
    local old_path="${DATA_DIR}/.gitconfig"
    local new_dir="${DATA_DIR}/git"
    local new_path="${new_dir}/gitconfig"

    # Only migrate if old exists with content and new is missing/empty
    if [[ -s "$old_path" && ! -L "$old_path" ]]; then
        # Check if new path needs content
        if [[ ! -s "$new_path" ]]; then
            # Ensure git directory exists
            if [[ -L "$new_dir" ]]; then
                log "[WARN] ${new_dir} is a symlink - cannot migrate git config"
                return 1
            fi
            mkdir -p "$new_dir" 2>/dev/null || true

            # Migrate: copy old to new
            if [[ ! -L "$new_path" ]] && [[ ! -e "$new_path" || -f "$new_path" ]]; then
                local tmp_path="${new_path}.tmp.$$"
                if cp "$old_path" "$tmp_path" 2>/dev/null && mv "$tmp_path" "$new_path" 2>/dev/null; then
                    log "[INFO] Migrated git config from ${old_path} to ${new_path}"
                    # Optionally remove old file after successful migration
                    rm -f "$old_path" 2>/dev/null || true
                else
                    rm -f "$tmp_path" 2>/dev/null || true
                    log "[WARN] Failed to migrate git config to new location"
                fi
            fi
        fi
    fi
}

# Setup git config from data volume
# New containers: ~/.gitconfig is symlinked to /mnt/agent-data/git/gitconfig (no copy needed)
# Legacy containers: copy from /mnt/agent-data/git/gitconfig to ~/.gitconfig
_setup_git_config() {
    local dst="${HOME}/.gitconfig"

    # New containers have ~/.gitconfig as symlink - nothing to do for $HOME
    if [[ -L "$dst" ]]; then
        return 0
    fi

    # Legacy container without symlink: find source file
    # Must be non-empty (-s) to avoid clobbering with empty placeholder file
    local src=""
    if [[ -s "${DATA_DIR}/git/gitconfig" && ! -L "${DATA_DIR}/git/gitconfig" ]]; then
        src="${DATA_DIR}/git/gitconfig"
    elif [[ -s "${DATA_DIR}/.gitconfig" && ! -L "${DATA_DIR}/.gitconfig" ]]; then
        src="${DATA_DIR}/.gitconfig"
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

# Process user manifests (custom agent configurations)
# User drops TOML files in ~/.config/containai/manifests/, runs import, restart
# This generates runtime symlinks and wrappers from user manifests
process_user_manifests() {
    local user_manifests="${DATA_DIR}/containai/manifests"
    local gen_links="/usr/local/lib/containai/gen-user-links.sh"
    local gen_wrappers="/usr/local/lib/containai/gen-user-wrappers.sh"

    # Check if user manifests directory exists and has content
    if [[ ! -d "$user_manifests" ]]; then
        return 0
    fi

    # Check for any .toml files
    local toml_count=0
    local f
    for f in "$user_manifests"/*.toml; do
        [[ -e "$f" ]] && toml_count=$((toml_count + 1))
    done

    if [[ $toml_count -eq 0 ]]; then
        return 0
    fi

    log "[INFO] Found $toml_count user manifest(s), generating runtime configuration..."

    # Generate user symlinks (validates paths, logs errors)
    if [[ -x "$gen_links" ]]; then
        if ! "$gen_links" "$user_manifests"; then
            log "[WARN] User symlink generation had errors (see above)"
        fi
    else
        log "[WARN] gen-user-links.sh not found or not executable"
    fi

    # Generate user launch wrappers (validates binaries, logs errors)
    if [[ -x "$gen_wrappers" ]]; then
        if ! "$gen_wrappers" "$user_manifests"; then
            log "[WARN] User wrapper generation had errors (see above)"
        fi
    else
        log "[WARN] gen-user-wrappers.sh not found or not executable"
    fi
}

# Run startup hooks from a directory
# Hooks are executable .sh files, run in sorted order (LC_ALL=C sort)
# Non-executable files are skipped with warning, non-zero exit fails container start
run_hooks() {
    local hooks_dir="$1"
    [[ -d "$hooks_dir" ]] || return 0

    # Set working directory for hooks
    cd -- /home/agent/workspace || cd -- /home/agent || true

    # Discover hooks with find, capturing errors for diagnosability
    local find_output find_rc
    find_output=$(find "$hooks_dir" -maxdepth 1 -name '*.sh' -type f 2>&1) && find_rc=0 || find_rc=$?

    if [[ $find_rc -ne 0 ]]; then
        log "[WARN] Failed to discover hooks in $hooks_dir: $find_output"
        return 0
    fi

    # Deterministic ordering with LC_ALL=C
    local hook
    local hooks_found=0
    while IFS= read -r hook; do
        [[ -z "$hook" ]] && continue
        hooks_found=1
        if [[ ! -x "$hook" ]]; then
            log "[WARN] Skipping non-executable hook: $hook"
            continue
        fi
        log "[INFO] Running startup hook: $hook"
        if ! "$hook"; then
            log "[ERROR] Startup hook failed: $hook"
            exit 1
        fi
    done < <(printf '%s\n' "$find_output" | LC_ALL=C sort)

    if [[ $hooks_found -eq 1 ]]; then
        log "[INFO] Completed hooks from: $hooks_dir"
    fi
}

# Main initialization
main() {
    log "[INFO] ContainAI initialization starting..."

    update_agent_pw
    ensure_volume_structure
    _load_env_file
    _migrate_git_config
    _setup_git_config
    setup_workspace_symlink

    # Process user manifests (after built-in setup)
    process_user_manifests

    # Run startup hooks: template hooks first, then workspace hooks
    run_hooks "/etc/containai/template-hooks/startup.d"
    run_hooks "/home/agent/workspace/.containai/hooks/startup.d"

    log "[INFO] ContainAI initialization complete"
}

main "$@"
