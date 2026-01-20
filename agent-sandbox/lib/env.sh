#!/usr/bin/env bash
# ==============================================================================
# ContainAI Env Import - Allowlist-based environment variable import
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _containai_import_env  - Import env vars to data volume via stdin streaming
#
# Usage:
#   source lib/env.sh
#   _containai_import_env "$context" "$volume" "$workspace" "$explicit_config" "$dry_run"
#
# Arguments:
#   $1 = Docker context ("" for default, "containai-secure" for Sysbox)
#   $2 = Data volume name (required)
#   $3 = Workspace path (for config resolution)
#   $4 = Explicit config path (optional)
#   $5 = Dry-run flag ("true" or "false", default: "false")
#
# Dependencies:
#   - docker (for alpine helper container)
#   - lib/config.sh (_containai_resolve_env_config)
#   - printenv (for host env reading)
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    printf '%s\n' "[ERROR] lib/env.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s\n' "[ERROR] lib/env.sh must be sourced, not executed directly" >&2
    printf '%s\n' "Usage: source lib/env.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_ENV_LOADED:-}" ]]; then
    return 0
fi
_CAI_ENV_LOADED=1

# ==============================================================================
# Logging helpers - use core.sh functions if available, fallback to ASCII markers
# ==============================================================================
_env_info() {
    if declare -f _cai_info >/dev/null 2>&1; then
        _cai_info "$@"
    else
        printf '%s\n' "[INFO] $*"
    fi
}
_env_success() {
    if declare -f _cai_ok >/dev/null 2>&1; then
        _cai_ok "$@"
    else
        printf '%s\n' "[OK] $*"
    fi
}
_env_error() {
    if declare -f _cai_error >/dev/null 2>&1; then
        _cai_error "$@"
    else
        printf '%s\n' "[ERROR] $*" >&2
    fi
}
_env_warn() {
    if declare -f _cai_warn >/dev/null 2>&1; then
        _cai_warn "$@"
    else
        printf '%s\n' "[WARN] $*" >&2
    fi
}
_env_step() {
    if declare -f _cai_step >/dev/null 2>&1; then
        _cai_step "$@"
    else
        printf '%s\n' "-> $*"
    fi
}

# ==============================================================================
# Variable name validation
# ==============================================================================

# Validate env var name against POSIX pattern
# Pattern: ^[A-Za-z_][A-Za-z0-9_]*$
# Arguments: $1 = var name
# Returns: 0=valid, 1=invalid
_env_validate_var_name() {
    local name="$1"
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

# ==============================================================================
# Allowlist deduplication
# ==============================================================================

# Deduplicate allowlist preserving first occurrence order
# Arguments: stdin = newline-separated var names
# Outputs: deduplicated names (newline-separated)
_env_dedupe_allowlist() {
    local line
    local -A seen=()
    while IFS= read -r line; do
        if [[ -n "$line" && -z "${seen[$line]+x}" ]]; then
            seen["$line"]=1
            printf '%s\n' "$line"
        fi
    done
}

# ==============================================================================
# .env file parser
# ==============================================================================

# Parse a .env file with explicit rules
# - Accept KEY=VALUE lines (optionally prefixed with 'export ')
# - Ignore full-line # comments and blank lines
# - Split on FIRST = only, preserve remainder as value
# - Validate KEY against POSIX pattern
# - Skip lines without = with warning
# - Strip CRLF (\r) from line endings
# - No quote stripping (literal values only)
# - Whitespace handling is strict (no trimming)
#
# Arguments:
#   $1 = file path
#   $2 = prefix for declare output (var name)
# Outputs: declare -A statements to stdout
# Logs: warnings to stderr (line number + key only, never values)
# Returns: 0 on success, 1 on file error
_env_parse_file() {
    local file="$1"
    local output_var="$2"
    local line_num=0
    local line key value

    # Guard: file must exist and be readable
    if [[ ! -f "$file" ]]; then
        _env_error "env_file not found: $file"
        return 1
    fi
    if [[ -L "$file" ]]; then
        _env_error "env_file is a symlink (rejected for security): $file"
        return 1
    fi
    if [[ ! -r "$file" ]]; then
        _env_error "env_file is not readable: $file"
        return 1
    fi

    # Output associative array declaration
    printf 'declare -A %s\n' "$output_var"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # set -e safe increment (NOT ((line_num++)) which fails on 0)
        line_num=$((line_num + 1))

        # Strip CRLF
        line="${line%$'\r'}"

        # Skip comments (full-line only, no leading whitespace tolerance per spec)
        if [[ "$line" =~ ^# ]]; then
            continue
        fi

        # Skip blank/whitespace-only lines
        if [[ -z "${line//[[:space:]]/}" ]]; then
            continue
        fi

        # Strip optional 'export ' prefix (must be at line start)
        if [[ "$line" =~ ^export[[:space:]]+ ]]; then
            line="${line#export}"
            # Trim leading whitespace after 'export'
            line="${line#"${line%%[![:space:]]*}"}"
        fi

        # Require = in line
        if [[ "$line" != *=* ]]; then
            _env_warn "line $line_num: no = found - skipping"
            continue
        fi

        # Extract key and value (split on first =)
        key="${line%%=*}"
        value="${line#*=}"

        # Validate key
        if ! _env_validate_var_name "$key"; then
            _env_warn "line $line_num: key '$key' invalid format - skipping"
            continue
        fi

        # Detect multiline values (unclosed quotes indicate continuation)
        # Count unescaped double quotes - odd count means unclosed
        # Also check for single quotes similarly
        # This detects values like: FOO="line1  (where line2" is on next line)
        local dq_count=0 sq_count=0 i char prev_char=""
        for ((i=0; i<${#value}; i++)); do
            char="${value:i:1}"
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                dq_count=$((dq_count + 1))
            elif [[ "$char" == "'" && "$prev_char" != '\' ]]; then
                sq_count=$((sq_count + 1))
            fi
            prev_char="$char"
        done
        # Odd quote count means unclosed quote (multiline value)
        if [[ $((dq_count % 2)) -ne 0 ]] || [[ $((sq_count % 2)) -ne 0 ]]; then
            _env_warn "line $line_num: key '$key' skipped (multiline value)"
            continue
        fi

        # Output assignment (escape single quotes in value for safety)
        # Use printf %q for bash-safe quoting
        printf '%s[%s]=%q\n' "$output_var" "$key" "$value"
    done < "$file"

    return 0
}

# ==============================================================================
# Host environment reading
# ==============================================================================

# Read host environment variables filtered by allowlist
# Uses printenv to read only exported env vars (not shell-local variables)
# Checks for multiline values and skips with warning
# Arguments:
#   stdin = allowlist (newline-separated var names)
#   $1 = output var name prefix
# Outputs: declare -A statements to stdout
# Logs: warnings for multiline values (key only, never values)
_env_read_host() {
    local output_var="$1"
    local var_name var_value

    printf 'declare -A %s\n' "$output_var"

    while IFS= read -r var_name; do
        [[ -z "$var_name" ]] && continue

        # Use printenv to read only exported env vars (not shell-local variables)
        # printenv returns non-zero if var is not set, which we handle with || true
        if ! var_value=$(printenv "$var_name" 2>/dev/null); then
            # Var not set in environment - skip silently
            continue
        fi

        # Check for multiline value
        if [[ "$var_value" == *$'\n'* ]]; then
            _env_warn "source=host: key '$var_name' skipped (multiline value)"
            continue
        fi

        # Output assignment
        printf '%s[%s]=%q\n' "$output_var" "$var_name" "$var_value"
    done

    return 0
}

# ==============================================================================
# Main import function
# ==============================================================================

# Import env vars to data volume via stdin streaming
# Arguments:
#   $1 = Docker context ("" for default, "containai-secure" for Sysbox)
#   $2 = Data volume name (required)
#   $3 = Workspace path (for config resolution)
#   $4 = Explicit config path (optional)
#   $5 = Dry-run flag ("true" or "false", default: "false")
# Returns: 0 on success, 1 on failure
_containai_import_env() {
    local ctx="${1:-}"
    local volume="${2:-}"
    local workspace="${3:-$PWD}"
    local explicit_config="${4:-}"
    local dry_run="${5:-false}"

    local env_config import_list from_host env_file
    local var_name line
    local -a allowlist=()
    local -a validated_allowlist=()
    local -A file_vars=()
    local -A host_vars=()
    local -A merged_vars=()
    local env_content=""
    local imported_keys=""
    local skipped_keys=""
    local imported_count=0
    local skipped_count=0

    # Validate required arguments
    if [[ -z "$volume" ]]; then
        _env_error "Volume name is required"
        return 1
    fi

    # Resolve workspace to absolute path
    local workspace_input="$workspace"
    if ! workspace=$(cd -- "$workspace" 2>/dev/null && pwd); then
        _env_warn "Invalid workspace path, using \$PWD: $workspace_input"
        workspace="$PWD"
    fi

    # Check if _containai_resolve_env_config is available
    if ! declare -f _containai_resolve_env_config >/dev/null 2>&1; then
        _env_warn "Config resolution unavailable, skipping env import"
        return 0
    fi

    # Resolve env config
    if ! env_config=$(_containai_resolve_env_config "$workspace" "$explicit_config"); then
        # Parse error - propagate failure
        return 1
    fi

    # Parse env config JSON
    if ! command -v python3 >/dev/null 2>&1; then
        _env_warn "Python not found, skipping env import"
        return 0
    fi

    # Extract _section_present, import list, from_host, env_file from config
    local section_present
    section_present=$(printf '%s' "$env_config" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if data.get('_section_present', False) else 'false')
")

    # If [env] section is missing, skip silently (per spec)
    if [[ "$section_present" != "true" ]]; then
        return 0
    fi

    import_list=$(printf '%s' "$env_config" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('import', []):
    if isinstance(item, str):
        print(item)
")

    from_host=$(printf '%s' "$env_config" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if data.get('from_host', False) else 'false')
")

    env_file=$(printf '%s' "$env_config" | python3 -c "
import json, sys
data = json.load(sys.stdin)
ef = data.get('env_file')
if ef is not None:
    print(ef)
")

    # Parse import list into array
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            allowlist+=("$line")
        fi
    done <<< "$import_list"

    # Empty allowlist: skip with [INFO] per spec
    # This logs only when [env] section exists but import is empty/invalid
    if [[ ${#allowlist[@]} -eq 0 ]]; then
        _env_info "Empty env import allowlist, skipping env import"
        return 0
    fi

    # Validate and deduplicate allowlist
    for var_name in "${allowlist[@]}"; do
        if ! _env_validate_var_name "$var_name"; then
            _env_warn "Invalid var name in allowlist: '$var_name' - skipping"
            continue
        fi
        # Check for duplicates
        local found=0
        local existing
        for existing in "${validated_allowlist[@]}"; do
            if [[ "$existing" == "$var_name" ]]; then
                found=1
                break
            fi
        done
        if [[ $found -eq 0 ]]; then
            validated_allowlist+=("$var_name")
        fi
    done

    # If no valid vars remain after validation
    if [[ ${#validated_allowlist[@]} -eq 0 ]]; then
        _env_info "No valid env vars in allowlist after validation, skipping env import"
        return 0
    fi

    _env_step "Importing env vars to volume: $volume"

    # Validate env_file path if set
    if [[ -n "$env_file" ]]; then
        # Reject absolute paths
        if [[ "$env_file" == /* ]]; then
            _env_error "env_file must be workspace-relative, absolute path rejected: $env_file"
            return 1
        fi

        # Resolve to absolute path within workspace
        local resolved_env_file="$workspace/$env_file"

        # Normalize path and check it's still within workspace
        if ! resolved_env_file=$(cd -- "$(dirname "$resolved_env_file")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename "$env_file")"); then
            _env_error "env_file path invalid: $env_file"
            return 1
        fi

        # Security check: ensure resolved path is under workspace
        if [[ "$resolved_env_file" != "$workspace"/* ]]; then
            _env_error "env_file escapes workspace: $env_file"
            return 1
        fi

        # Parse env file (hard error if missing/unreadable per spec)
        local file_parse_output
        if ! file_parse_output=$(_env_parse_file "$resolved_env_file" "_env_file_vars"); then
            return 1
        fi

        # Clear any stale values from previous calls, then evaluate the parsed declarations
        unset _env_file_vars
        eval "$file_parse_output"

        # Copy to file_vars (filter by allowlist)
        for var_name in "${validated_allowlist[@]}"; do
            if [[ -n "${_env_file_vars[$var_name]+x}" ]]; then
                file_vars["$var_name"]="${_env_file_vars[$var_name]}"
            fi
        done
    fi

    # Read from host environment if enabled
    if [[ "$from_host" == "true" ]]; then
        local host_parse_output
        host_parse_output=$(printf '%s\n' "${validated_allowlist[@]}" | _env_read_host "_env_host_vars")
        # Clear any stale values from previous calls, then evaluate the parsed declarations
        unset _env_host_vars
        eval "$host_parse_output"

        # Copy to host_vars
        for var_name in "${validated_allowlist[@]}"; do
            if [[ -n "${_env_host_vars[$var_name]+x}" ]]; then
                host_vars["$var_name"]="${_env_host_vars[$var_name]}"
            fi
        done
    fi

    # Merge sources (host takes precedence over file)
    for var_name in "${validated_allowlist[@]}"; do
        if [[ -n "${host_vars[$var_name]+x}" ]]; then
            merged_vars["$var_name"]="${host_vars[$var_name]}"
        elif [[ -n "${file_vars[$var_name]+x}" ]]; then
            merged_vars["$var_name"]="${file_vars[$var_name]}"
        fi
    done

    # Build .env content and track imported/skipped
    for var_name in "${validated_allowlist[@]}"; do
        if [[ -n "${merged_vars[$var_name]+x}" ]]; then
            env_content+="$var_name=${merged_vars[$var_name]}"$'\n'
            if [[ -n "$imported_keys" ]]; then
                imported_keys+=", "
            fi
            imported_keys+="$var_name"
            imported_count=$((imported_count + 1))
        else
            if [[ -n "$skipped_keys" ]]; then
                skipped_keys+=", "
            fi
            skipped_keys+="$var_name"
            skipped_count=$((skipped_count + 1))
            _env_warn "Var not found in host or file: '$var_name'"
        fi
    done

    # Handle dry-run mode
    if [[ "$dry_run" == "true" ]]; then
        _env_info "Docker context: ${ctx:-default}"
        _env_info "[dry-run] Would import $imported_count env vars: $imported_keys"
        if [[ $skipped_count -gt 0 ]]; then
            _env_info "[dry-run] Would skip $skipped_count vars (not found): $skipped_keys"
        fi
        return 0
    fi

    # If nothing to import, skip write
    if [[ $imported_count -eq 0 ]]; then
        _env_warn "No env vars found to import"
        return 0
    fi

    # Build docker command with context
    local -a docker_cmd=(docker)
    if [[ -n "$ctx" ]]; then
        docker_cmd+=(--context "$ctx")
    fi

    # Write atomically via helper container
    # - Write as root (volume root is typically root:root)
    # - chown 1000:1000 and chmod 600
    # - TOCTOU-safe: verify mount point + target not symlinks
    # - Stream content via stdin (no values in -e args)
    if ! printf '%s' "$env_content" | DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm -i \
        --network=none \
        -v "$volume:/data" \
        alpine sh -c '
            # Verify mount point not symlink and is directory
            [ ! -L /data ] || { echo "[ERROR] Mount point is symlink" >&2; exit 1; }
            [ -d /data ] || { echo "[ERROR] Mount point is not directory" >&2; exit 1; }
            # Create temp file (busybox mktemp)
            tmp=$(mktemp -p /data)
            [ ! -L "$tmp" ] || { rm -f "$tmp"; echo "[ERROR] Temp file is symlink" >&2; exit 1; }
            # Write content from stdin
            cat > "$tmp"
            # Set ownership and permissions
            chown 1000:1000 "$tmp"
            chmod 600 "$tmp"
            # Verify target not symlink before rename (if exists)
            [ ! -L /data/.env ] || { rm -f "$tmp"; echo "[ERROR] Target .env is symlink" >&2; exit 1; }
            # Atomic move
            mv "$tmp" /data/.env
        '; then
        _env_error "Failed to write .env to volume"
        return 1
    fi

    _env_success "Imported $imported_count env vars: $imported_keys"
    if [[ $skipped_count -gt 0 ]]; then
        _env_info "Skipped $skipped_count vars (not found): $skipped_keys"
    fi

    return 0
}

return 0
