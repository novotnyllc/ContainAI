#!/usr/bin/env bash
# Generate agent launch wrapper functions from manifest [agent] sections
# Usage: gen-agent-wrappers.sh <manifests-dir> <output-file>
#
# Reads [agent] sections from manifests and generates shell functions
# that prepend default_args to agent commands.
#
# Output: Shell script with wrapper functions suitable for BASH_ENV sourcing
#
# The generated functions use `command` builtin to invoke the real binary
# (avoiding recursion) and work in both interactive and non-interactive shells.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${1:-}"
OUTPUT_FILE="${2:-}"

if [[ -z "$MANIFESTS_DIR" ]]; then
    printf 'ERROR: manifests directory required as first argument\n' >&2
    exit 1
fi
if [[ ! -d "$MANIFESTS_DIR" ]]; then
    printf 'ERROR: manifests directory not found: %s\n' "$MANIFESTS_DIR" >&2
    exit 1
fi
if [[ -z "$OUTPUT_FILE" ]]; then
    printf 'ERROR: output file required as second argument\n' >&2
    exit 1
fi

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
                # Emit the agent and reset
                if [[ -n "$name" && -n "$default_args" ]]; then
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
    if [[ $in_agent -eq 1 && -n "$name" && -n "$default_args" ]]; then
        printf '%s|%s|%s|%s|%s\n' "$name" "$binary" "$default_args" "$aliases" "$optional"
    fi
}

# Build list of manifest files in sorted order
MANIFEST_FILES=()
shopt -s nullglob
for file in "$MANIFESTS_DIR"/*.toml; do
    MANIFEST_FILES+=("$file")
done
shopt -u nullglob

if [[ ${#MANIFEST_FILES[@]} -eq 0 ]]; then
    printf 'ERROR: no .toml files found in directory: %s\n' "$MANIFESTS_DIR" >&2
    exit 1
fi

# Sort for deterministic order
sorted_files=$(printf '%s\n' "${MANIFEST_FILES[@]}" | LC_ALL=C sort) || {
    printf 'ERROR: failed to sort manifest files\n' >&2
    exit 1
}
mapfile -t MANIFEST_FILES <<< "$sorted_files"

# Collect agent info from all manifests
declare -a agents=()
for manifest in "${MANIFEST_FILES[@]}"; do
    agent_info=$(parse_agent_section "$manifest")
    if [[ -n "$agent_info" ]]; then
        agents+=("$agent_info")
    fi
done

if [[ ${#agents[@]} -eq 0 ]]; then
    printf 'WARNING: no agents with default_args found in manifests\n' >&2
fi

# Generate output
generate_output() {
    printf '# Generated agent launch wrappers from src/manifests/\n'
    printf '# Regenerate with: src/scripts/gen-agent-wrappers.sh src/manifests/ <output>\n'
    printf '#\n'
    printf '# These functions prepend default autonomous flags to agent commands.\n'
    printf '# Use `command` builtin to invoke real binary (avoids recursion).\n'
    printf '# Sourced via BASH_ENV for non-interactive SSH compatibility.\n'
    printf '\n'

    local agent_info name binary default_args aliases optional
    local IFS_orig="$IFS"

    for agent_info in "${agents[@]}"; do
        IFS='|' read -r name binary default_args aliases optional <<< "$agent_info"

        # Convert comma-separated args to shell-quoted format
        local args_array=()
        IFS=',' read -ra args_array <<< "$default_args"

        # Build the args string with proper quoting
        local args_str=""
        for arg in "${args_array[@]}"; do
            if [[ -n "$args_str" ]]; then
                args_str="${args_str} \"${arg}\""
            else
                args_str="\"${arg}\""
            fi
        done

        # Generate function for primary binary
        printf '# %s\n' "$name"
        if [[ "$optional" == "true" ]]; then
            printf 'if command -v %s >/dev/null 2>&1; then\n' "$binary"
            printf '%s() {\n' "$binary"
            printf '    command %s %s "$@"\n' "$binary" "$args_str"
            printf '}\n'
            # Generate alias functions if any
            if [[ -n "$aliases" ]]; then
                local alias_array=()
                IFS=',' read -ra alias_array <<< "$aliases"
                for alias_name in "${alias_array[@]}"; do
                    printf '%s() {\n' "$alias_name"
                    printf '    command %s %s "$@"\n' "$alias_name" "$args_str"
                    printf '}\n'
                done
            fi
            printf 'fi\n'
        else
            printf '%s() {\n' "$binary"
            printf '    command %s %s "$@"\n' "$binary" "$args_str"
            printf '}\n'
            # Generate alias functions if any
            if [[ -n "$aliases" ]]; then
                local alias_array=()
                IFS=',' read -ra alias_array <<< "$aliases"
                for alias_name in "${alias_array[@]}"; do
                    printf '%s() {\n' "$alias_name"
                    printf '    command %s %s "$@"\n' "$alias_name" "$args_str"
                    printf '}\n'
                done
            fi
        fi
        printf '\n'

        IFS="$IFS_orig"
    done
}

# Write output
generate_output > "$OUTPUT_FILE"
chmod +x "$OUTPUT_FILE"
printf 'Generated: %s (%d agents)\n' "$OUTPUT_FILE" "${#agents[@]}" >&2
