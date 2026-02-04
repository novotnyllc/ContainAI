#!/usr/bin/env bash
# Generate user agent launch wrapper functions from user manifests at runtime
# Usage: gen-user-wrappers.sh <user-manifests-dir>
#
# Reads [agent] sections from user TOML manifests and generates shell functions
# that prepend default_args to agent commands.
#
# Output: /home/agent/.bash_env.d/containai-user-agents.sh
#
# Security constraints:
#   - Binary must exist in PATH to generate wrapper
#   - Invalid TOML files are logged and skipped
#   - Invalid entries are logged and skipped (don't block startup)
set -euo pipefail

: "${HOME:=/home/agent}"
readonly BASH_ENV_DIR="${HOME}/.bash_env.d"
readonly OUTPUT_FILE="${BASH_ENV_DIR}/containai-user-agents.sh"

log() { printf '%s\n' "$*" >&2; }

# Validate identifier for use as function/command name
# Allows: letters, digits, underscore, hyphen (for names like kimi-cli)
# Must start with letter or underscore
validate_identifier() {
    local id="$1"
    local context="$2"

    if [[ -z "$id" ]]; then
        log "[WARN] Empty $context - skipping"
        return 1
    fi

    # Safe pattern: starts with letter/underscore, contains only alnum/underscore/hyphen
    if [[ ! "$id" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
        log "[WARN] Invalid $context (unsafe characters): $id - skipping"
        return 1
    fi

    # Reject shell metacharacters and control characters
    if [[ "$id" == *[$'\t\n\r !\"#$%&'\''()*+,/:;<=>?@[\\]^`{|}~']* ]]; then
        log "[WARN] Invalid $context (contains metacharacters): $id - skipping"
        return 1
    fi

    return 0
}

# Parse [agent] section from a single manifest file
# Outputs: name|binary|default_args|aliases|optional
# where default_args and aliases are comma-separated
# Returns 0 if valid agent found, 1 if [agent] section found but invalid, 2 if no [agent]
parse_agent_section() {
    local manifest_file="$1"
    local in_agent=0
    local found_agent_section=0
    local name="" binary="" default_args="" aliases="" optional="false"
    local line key value
    local unparsed_lines=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip comments and empty lines
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Check for [agent] section start
        if [[ "$line" == "[agent]" ]]; then
            in_agent=1
            found_agent_section=1
            continue
        fi

        # Exit [agent] section on any other section header
        if [[ "$line" == "["*"]" || "$line" == "[["*"]]" ]]; then
            if [[ $in_agent -eq 1 ]]; then
                # Check if we got required fields
                if [[ -n "$name" && -n "$binary" ]]; then
                    printf '%s|%s|%s|%s|%s\n' "$name" "$binary" "$default_args" "$aliases" "$optional"
                    return 0
                elif [[ $found_agent_section -eq 1 ]]; then
                    # Found [agent] but missing required fields
                    return 1
                fi
                return 2
            fi
            continue
        fi

        # Skip lines if not in [agent] section
        [[ $in_agent -eq 0 ]] && continue

        # Track if line looks like a key-value but doesn't parse
        local parsed=0

        # Parse key = "value" (quoted string)
        if [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*(#.*)?$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            parsed=1
            case "$key" in
                name) name="$value" ;;
                binary) binary="$value" ;;
            esac
        # Parse key = [...] (array on single line)
        elif [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\[(.*)\][[:space:]]*(#.*)?$ ]]; then
            key="${BASH_REMATCH[1]}"
            local array_content="${BASH_REMATCH[2]}"
            parsed=1
            # Extract quoted strings from array, join with comma
            local items=""
            local item
            # Use grep to extract quoted strings (|| true to handle empty arrays)
            while read -r item; do
                [[ -z "$item" ]] && continue
                if [[ -n "$items" ]]; then
                    items="${items},${item}"
                else
                    items="$item"
                fi
            done < <(printf '%s' "$array_content" | grep -oE '"[^"]*"' | tr -d '"' || true)
            case "$key" in
                default_args) default_args="$items" ;;
                aliases) aliases="$items" ;;
            esac
        # Parse key = true/false (boolean)
        elif [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*(#.*)?$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            parsed=1
            case "$key" in
                optional) optional="$value" ;;
            esac
        fi

        # Track unparsed lines that look like key=value (potential TOML errors)
        if [[ $parsed -eq 0 && "$line" == *"="* ]]; then
            unparsed_lines=$((unparsed_lines + 1))
        fi
    done < "$manifest_file"

    # Emit if we reached EOF while in [agent] section
    if [[ $in_agent -eq 1 && -n "$name" && -n "$binary" ]]; then
        printf '%s|%s|%s|%s|%s\n' "$name" "$binary" "$default_args" "$aliases" "$optional"
        return 0
    elif [[ $found_agent_section -eq 1 ]]; then
        # Found [agent] but missing required fields - treat as invalid
        return 1
    fi

    # No [agent] section found
    return 2
}

# Main
USER_MANIFESTS_DIR="${1:-}"

if [[ -z "$USER_MANIFESTS_DIR" ]]; then
    log "[ERROR] Usage: gen-user-wrappers.sh <user-manifests-dir>"
    exit 1
fi

if [[ ! -d "$USER_MANIFESTS_DIR" ]]; then
    log "[INFO] User manifests directory does not exist: $USER_MANIFESTS_DIR"
    exit 0
fi

# Build list of manifest files
shopt -s nullglob
MANIFEST_FILES=("$USER_MANIFESTS_DIR"/*.toml)
shopt -u nullglob

if [[ ${#MANIFEST_FILES[@]} -eq 0 ]]; then
    log "[INFO] No user manifests found in: $USER_MANIFESTS_DIR"
    exit 0
fi

# Sort for deterministic order
sorted_files=$(printf '%s\n' "${MANIFEST_FILES[@]}" | LC_ALL=C sort) || {
    log "[ERROR] Failed to sort manifest files"
    exit 1
}
mapfile -t MANIFEST_FILES <<< "$sorted_files"

# Collect agent info from all manifests
declare -a agents=()
for manifest in "${MANIFEST_FILES[@]}"; do
    agent_info=""
    parse_rc=0
    agent_info=$(parse_agent_section "$manifest") || parse_rc=$?

    case $parse_rc in
        0)
            # Valid agent found
            if [[ -n "$agent_info" ]]; then
                agents+=("$agent_info")
            fi
            ;;
        1)
            # [agent] section found but invalid (missing required fields)
            log "[WARN] Invalid [agent] section in $(basename "$manifest") (missing name or binary) - skipping"
            ;;
        2)
            # No [agent] section - that's fine, not all manifests have agents
            ;;
        *)
            # Parse error
            log "[WARN] Failed to parse $(basename "$manifest") - skipping"
            ;;
    esac
done

if [[ ${#agents[@]} -eq 0 ]]; then
    log "[INFO] No agents found in user manifests"
    # Still create empty file so sourcing doesn't fail
    mkdir -p "$BASH_ENV_DIR"
    printf '# No user agents configured\n' > "$OUTPUT_FILE"
    exit 0
fi

# Ensure output directory exists
mkdir -p "$BASH_ENV_DIR"

# Generate output
generate_output() {
    printf '# Generated user agent launch wrappers from user manifests\n'
    printf '# Generated at container startup from %s\n' "$USER_MANIFESTS_DIR"
    printf '#\n'
    printf '# These functions prepend default autonomous flags to agent commands.\n'
    printf '# Use `command` builtin to invoke real binary (avoids recursion).\n'
    printf '\n'

    local agent_info name binary default_args aliases optional
    local IFS_orig="$IFS"
    local wrappers_count=0
    local skipped_count=0

    for agent_info in "${agents[@]}"; do
        IFS='|' read -r name binary default_args aliases optional <<< "$agent_info"

        # Validate name is a safe function identifier
        if ! validate_identifier "$name" "agent name"; then
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Validate binary is a safe command token
        if ! validate_identifier "$binary" "binary"; then
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Check if binary exists (required for wrapper)
        if ! command -v "$binary" >/dev/null 2>&1; then
            log "[INFO] Binary not found, skipping wrapper: $binary"
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Convert comma-separated args to shell-quoted format
        local args_array=()
        IFS=',' read -ra args_array <<< "$default_args"

        # Build the args string with robust shell escaping (single-quote each arg)
        local args_str=""
        for arg in "${args_array[@]}"; do
            # Shell-escape using single quotes (escape any embedded single quotes)
            local escaped_arg="'${arg//\'/\'\\\'\'}'"
            if [[ -n "$args_str" ]]; then
                args_str="${args_str} ${escaped_arg}"
            else
                args_str="${escaped_arg}"
            fi
        done

        # Generate wrapper function
        printf '# %s (user-defined)\n' "$name"
        # Primary wrapper uses name, calls binary
        printf '%s() {\n' "$name"
        printf '    command %s %s "$@"\n' "$binary" "$args_str"
        printf '}\n'
        # If name != binary, also create wrapper for binary
        if [[ "$name" != "$binary" ]]; then
            printf '%s() {\n' "$binary"
            printf '    command %s %s "$@"\n' "$binary" "$args_str"
            printf '}\n'
        fi
        # Generate alias functions if any
        if [[ -n "$aliases" ]]; then
            local alias_array=()
            IFS=',' read -ra alias_array <<< "$aliases"
            for alias_name in "${alias_array[@]}"; do
                # Validate alias is a safe function identifier
                if ! validate_identifier "$alias_name" "alias"; then
                    continue
                fi
                printf '%s() {\n' "$alias_name"
                printf '    command %s %s "$@"\n' "$binary" "$args_str"
                printf '}\n'
            done
        fi
        printf '\n'

        wrappers_count=$((wrappers_count + 1))
        IFS="$IFS_orig"
    done

    log "[INFO] Generated $wrappers_count user agent wrappers ($skipped_count skipped - binary not found)"
}

# Write output atomically
tmp_output="${OUTPUT_FILE}.tmp.$$"
generate_output > "$tmp_output"

if mv "$tmp_output" "$OUTPUT_FILE" 2>/dev/null; then
    chmod +x "$OUTPUT_FILE"
    log "[INFO] Generated: $OUTPUT_FILE"
else
    rm -f "$tmp_output" 2>/dev/null || true
    log "[ERROR] Failed to write user agent wrappers"
    exit 1
fi

exit 0
