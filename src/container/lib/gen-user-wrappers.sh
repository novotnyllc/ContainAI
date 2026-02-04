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

# Parse [agent] section from a single manifest file
# Outputs: name|binary|default_args|aliases|optional
# where default_args and aliases are comma-separated
parse_agent_section() {
    local manifest_file="$1"
    local in_agent=0
    local name="" binary="" default_args="" aliases="" optional="false"
    local line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip comments and empty lines
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Check for [agent] section start
        if [[ "$line" == "[agent]" ]]; then
            in_agent=1
            continue
        fi

        # Exit [agent] section on any other section header
        if [[ "$line" == "["*"]" || "$line" == "[["*"]]" ]]; then
            if [[ $in_agent -eq 1 ]]; then
                # Emit the agent if name and binary are set
                if [[ -n "$name" && -n "$binary" ]]; then
                    printf '%s|%s|%s|%s|%s\n' "$name" "$binary" "$default_args" "$aliases" "$optional"
                fi
                return
            fi
            continue
        fi

        # Skip lines if not in [agent] section
        [[ $in_agent -eq 0 ]] && continue

        # Parse key = "value" (quoted string)
        if [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*(#.*)?$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            case "$key" in
                name) name="$value" ;;
                binary) binary="$value" ;;
            esac
        # Parse key = [...] (array)
        elif [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\[(.*)\][[:space:]]*(#.*)?$ ]]; then
            key="${BASH_REMATCH[1]}"
            local array_content="${BASH_REMATCH[2]}"
            # Extract quoted strings from array, join with comma
            local items=""
            local item
            # Use grep to extract quoted strings
            while read -r item; do
                [[ -z "$item" ]] && continue
                if [[ -n "$items" ]]; then
                    items="${items},${item}"
                else
                    items="$item"
                fi
            done < <(printf '%s' "$array_content" | grep -oE '"[^"]*"' | tr -d '"')
            case "$key" in
                default_args) default_args="$items" ;;
                aliases) aliases="$items" ;;
            esac
        # Parse key = true/false (boolean)
        elif [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*(#.*)?$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            case "$key" in
                optional) optional="$value" ;;
            esac
        fi
    done < "$manifest_file"

    # Emit if we reached EOF while in [agent] section
    if [[ $in_agent -eq 1 && -n "$name" && -n "$binary" ]]; then
        printf '%s|%s|%s|%s|%s\n' "$name" "$binary" "$default_args" "$aliases" "$optional"
    fi
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
    if ! agent_info=$(parse_agent_section "$manifest" 2>&1); then
        log "[WARN] Failed to parse [agent] from $(basename "$manifest") - skipping"
        continue
    fi
    if [[ -n "$agent_info" ]]; then
        agents+=("$agent_info")
    fi
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
