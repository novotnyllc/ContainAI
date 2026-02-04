#!/usr/bin/env bash
# Generate user symlinks and link-spec from user manifests at runtime
# Usage: gen-user-links.sh <user-manifests-dir>
#
# Reads [[entries]] from user TOML manifests and:
#   1. Creates symlinks in $HOME for entries with container_link
#   2. Generates /mnt/agent-data/containai/user-link-spec.json
#
# Security constraints:
#   - target paths must resolve under /mnt/agent-data
#   - container_link must be relative (no leading /), no .. segments
#   - Invalid TOML files are logged and skipped
#   - Invalid entries are logged and skipped
set -euo pipefail

: "${HOME:=/home/agent}"
readonly DATA_DIR="/mnt/agent-data"
readonly HOME_DIR="/home/agent"

log() { printf '%s\n' "$*" >&2; }

# Verify path resolves under DATA_DIR (prevents symlink traversal)
verify_path_under_data_dir() {
    local path="$1"
    local resolved

    resolved="$(realpath -m "$path" 2>/dev/null)" || {
        log "[WARN] Cannot resolve path: $path"
        return 1
    }

    # Check for .. traversal attempts in the original path
    if [[ "$path" == *"/.."* || "$path" == *"/../"* ]]; then
        log "[WARN] Path contains .. traversal: $path"
        return 1
    fi

    if [[ "$resolved" != "${DATA_DIR}" && "$resolved" != "${DATA_DIR}/"* ]]; then
        log "[WARN] Path escapes data directory: $path -> $resolved"
        return 1
    fi
    return 0
}

# Validate container_link: must be relative, no leading /, no .. segments
validate_container_link() {
    local link="$1"

    # Reject absolute paths
    if [[ "$link" == /* ]]; then
        log "[WARN] container_link must be relative (no leading /): $link"
        return 1
    fi

    # Reject .. segments
    if [[ "$link" == *".."* ]]; then
        log "[WARN] container_link contains .. segment: $link"
        return 1
    fi

    # Reject empty
    if [[ -z "$link" ]]; then
        log "[WARN] container_link is empty"
        return 1
    fi

    return 0
}

# Verify container path resolves under HOME_DIR (prevents symlink traversal)
verify_path_under_home_dir() {
    local path="$1"
    local parent resolved

    # Get parent directory for resolution check
    parent="$(dirname "$path")"

    # If parent doesn't exist yet, walk up to find existing ancestor
    while [[ ! -e "$parent" && "$parent" != "/" ]]; do
        parent="$(dirname "$parent")"
    done

    # Resolve the existing ancestor
    resolved="$(realpath -m "$parent" 2>/dev/null)" || {
        log "[WARN] Cannot resolve parent path: $parent"
        return 1
    }

    # Check that resolved path is under HOME_DIR
    if [[ "$resolved" != "${HOME_DIR}" && "$resolved" != "${HOME_DIR}/"* ]]; then
        log "[WARN] Container path escapes home directory: $path -> $resolved"
        return 1
    fi

    return 0
}

# Validate flag characters (only known flags allowed)
# Requires non-empty flags with at least f (file) or d (directory)
validate_flags() {
    local flags="$1"
    local valid_flags="fdjsmxgRo"  # Note: G (glob) excluded for user manifests

    # Require non-empty flags
    if [[ -z "$flags" ]]; then
        log "[WARN] Missing required flags field"
        return 1
    fi

    # Require at least f or d to specify type
    if [[ "$flags" != *f* && "$flags" != *d* ]]; then
        log "[WARN] Flags must include 'f' (file) or 'd' (directory): $flags"
        return 1
    fi

    local char i
    for ((i=0; i<${#flags}; i++)); do
        char="${flags:i:1}"
        if [[ "$valid_flags" != *"$char"* ]]; then
            log "[WARN] Invalid flag character: $char in flags: $flags"
            return 1
        fi
    done
    return 0
}

# Parse [[entries]] from a single manifest file
# Outputs: target|container_link|flags (one per entry with container_link)
# Returns 0 on success, 1 if TOML parsing errors detected
parse_entries() {
    local manifest_file="$1"
    local in_entries=0
    local in_agent=0
    local target="" container_link="" flags=""
    local line key value
    local unparsed_lines=0
    local found_entries=0

    emit_entry() {
        if [[ -n "$container_link" && -n "$target" ]]; then
            printf '%s|%s|%s\n' "$target" "$container_link" "$flags"
        elif [[ $found_entries -eq 1 ]]; then
            # Found [[entries]] but missing required fields - log to stderr
            # Note: log() already writes to stderr
            if [[ -z "$target" ]]; then
                log "[WARN] Entry missing required 'target' field - skipping"
            elif [[ -z "$container_link" ]]; then
                log "[WARN] Entry missing required 'container_link' field - skipping"
            fi
        fi
        target=""
        container_link=""
        flags=""
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip comments and empty lines
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Check for section headers
        if [[ "$line" == "[[entries]]" ]]; then
            if [[ $in_entries -eq 1 ]]; then
                emit_entry
            fi
            in_entries=1
            found_entries=1
            in_agent=0
            continue
        fi
        if [[ "$line" == "[agent]" ]]; then
            if [[ $in_entries -eq 1 ]]; then
                emit_entry
            fi
            in_entries=0
            in_agent=1
            continue
        fi
        if [[ "$line" == "["*"]" || "$line" == "[["*"]]" ]]; then
            if [[ $in_entries -eq 1 ]]; then
                emit_entry
            fi
            in_entries=0
            in_agent=0
            continue
        fi

        # Track if line was parsed (check ALL sections for TOML validity)
        local parsed=0

        # Parse key = "value" (quoted string)
        if [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*(#.*)?$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            parsed=1
            # Only capture values if in [[entries]] section
            if [[ $in_entries -eq 1 ]]; then
                case "$key" in
                    target) target="$value" ;;
                    container_link) container_link="$value" ;;
                    flags) flags="$value" ;;
                esac
            fi
        # Parse key = [...] (array) - valid TOML syntax
        elif [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\[.*\][[:space:]]*(#.*)?$ ]]; then
            parsed=1
        # Parse key = true/false (boolean) - valid TOML syntax
        elif [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*(#.*)?$ ]]; then
            parsed=1
        # Parse key = number - valid TOML syntax
        elif [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*[0-9]+[[:space:]]*(#.*)?$ ]]; then
            parsed=1
        fi

        # Track unparsed lines as potential TOML errors
        # Check ALL lines regardless of section to detect invalid TOML anywhere
        # Any non-comment, non-section-header line that doesn't match a valid pattern is invalid
        if [[ $parsed -eq 0 ]]; then
            unparsed_lines=$((unparsed_lines + 1))
        fi
    done < "$manifest_file"

    # Emit final entry if any
    if [[ $in_entries -eq 1 ]]; then
        emit_entry
    fi

    # Return non-zero if we detected unparseable TOML-like lines
    if [[ $unparsed_lines -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Main
USER_MANIFESTS_DIR="${1:-}"

if [[ -z "$USER_MANIFESTS_DIR" ]]; then
    log "[ERROR] Usage: gen-user-links.sh <user-manifests-dir>"
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

# Collect valid link specs
declare -a links_json=()
links_count=0
errors_count=0

for manifest in "${MANIFEST_FILES[@]}"; do
    manifest_basename=$(basename "$manifest")
    log "[INFO] Processing user manifest: $manifest_basename"

    # Parse entries from manifest
    # Capture stdout (entries) only - let warnings go to stderr
    entries_output=""
    parse_rc=0
    entries_output=$(parse_entries "$manifest") || parse_rc=$?

    if [[ $parse_rc -ne 0 ]]; then
        log "[WARN] Invalid TOML syntax in $manifest_basename - skipping file"
        errors_count=$((errors_count + 1))
        continue
    fi

    # Process each entry
    while IFS='|' read -r target container_link flags; do
        [[ -z "$target" ]] && continue

        # Validate flags
        if ! validate_flags "$flags"; then
            log "[WARN] Invalid flags in $manifest_basename: $flags - skipping entry"
            errors_count=$((errors_count + 1))
            continue
        fi

        # Validate container_link
        if ! validate_container_link "$container_link"; then
            log "[WARN] Invalid container_link in $manifest_basename: $container_link - skipping entry"
            errors_count=$((errors_count + 1))
            continue
        fi

        # Build full paths
        volume_path="${DATA_DIR}/${target}"
        container_path="${HOME_DIR}/${container_link}"

        # Validate target path stays under DATA_DIR
        if ! verify_path_under_data_dir "$volume_path"; then
            log "[WARN] Target path escapes data dir in $manifest_basename: $target - skipping entry"
            errors_count=$((errors_count + 1))
            continue
        fi

        # Validate container path stays under HOME_DIR (prevent symlink traversal)
        if ! verify_path_under_home_dir "$container_path"; then
            log "[WARN] Container path escapes home dir in $manifest_basename: $container_link - skipping entry"
            errors_count=$((errors_count + 1))
            continue
        fi

        # Determine remove_first from R flag
        remove_first=0
        [[ "$flags" == *R* ]] && remove_first=1

        # Create parent directory for symlink
        parent=$(dirname "$container_path")
        if [[ ! -d "$parent" ]]; then
            mkdir -p "$parent" 2>/dev/null || {
                log "[WARN] Failed to create parent directory: $parent"
                errors_count=$((errors_count + 1))
                continue
            }
        fi

        # Remove existing if R flag set and it's a directory
        if [[ $remove_first -eq 1 && -d "$container_path" && ! -L "$container_path" ]]; then
            rm -rf "$container_path" 2>/dev/null || {
                log "[WARN] Failed to remove existing directory: $container_path"
                errors_count=$((errors_count + 1))
                continue
            }
        fi

        # Create symlink (ln -sfn handles existing symlinks/files)
        if ! ln -sfn "$volume_path" "$container_path" 2>/dev/null; then
            log "[WARN] Failed to create symlink: $container_path -> $volume_path"
            errors_count=$((errors_count + 1))
            continue
        fi

        log "[INFO] Created symlink: $container_path -> $volume_path"

        # Escape JSON special characters
        container_path_escaped="${container_path//\\/\\\\}"
        container_path_escaped="${container_path_escaped//\"/\\\"}"
        volume_path_escaped="${volume_path//\\/\\\\}"
        volume_path_escaped="${volume_path_escaped//\"/\\\"}"

        # Add to link spec
        links_json+=("    {\"link\": \"${container_path_escaped}\", \"target\": \"${volume_path_escaped}\", \"remove_first\": ${remove_first}}")
        links_count=$((links_count + 1))

    done <<< "$entries_output"
done

# Write user link spec
USER_SPEC_DIR="${DATA_DIR}/containai"
USER_SPEC_FILE="${USER_SPEC_DIR}/user-link-spec.json"

mkdir -p "$USER_SPEC_DIR" 2>/dev/null || {
    log "[ERROR] Failed to create containai directory: $USER_SPEC_DIR"
    exit 1
}

# Write atomically
tmp_spec="${USER_SPEC_FILE}.tmp.$$"
{
    printf '{\n'
    printf '  "version": 1,\n'
    printf '  "data_mount": "%s",\n' "$DATA_DIR"
    printf '  "home_dir": "%s",\n' "$HOME_DIR"
    printf '  "links": [\n'
    for i in "${!links_json[@]}"; do
        if [[ $i -eq $((${#links_json[@]} - 1)) ]]; then
            printf '%s\n' "${links_json[$i]}"
        else
            printf '%s,\n' "${links_json[$i]}"
        fi
    done
    printf '  ]\n'
    printf '}\n'
} > "$tmp_spec"

if mv "$tmp_spec" "$USER_SPEC_FILE" 2>/dev/null; then
    log "[INFO] Generated user link spec: $USER_SPEC_FILE ($links_count links)"
else
    rm -f "$tmp_spec" 2>/dev/null || true
    log "[ERROR] Failed to write user link spec"
    exit 1
fi

if [[ $errors_count -gt 0 ]]; then
    log "[WARN] Completed with $errors_count skipped entries"
fi

exit 0
