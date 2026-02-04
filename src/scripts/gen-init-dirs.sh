#!/usr/bin/env bash
# Generate init script for creating volume directory structure from manifest
# Usage: gen-init-dirs.sh <manifest_path> <output_path>
# Reads sync-manifest.toml and outputs shell script fragment for containai-init.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_FILE="${1:-}"
OUTPUT_FILE="${2:-}"

if [[ -z "$MANIFEST_FILE" || ! -f "$MANIFEST_FILE" ]]; then
    printf 'ERROR: manifest file required as first argument\n' >&2
    exit 1
fi
if [[ -z "$OUTPUT_FILE" ]]; then
    printf 'ERROR: output file required as second argument\n' >&2
    exit 1
fi

# Parse manifest
PARSE_SCRIPT="${SCRIPT_DIR}/parse-manifest.sh"
if [[ ! -x "$PARSE_SCRIPT" ]]; then
    printf 'ERROR: parse-manifest.sh not found or not executable\n' >&2
    exit 1
fi

# Constants
DATA_DIR="\${DATA_DIR}"

# Collect directories and files
declare -a dir_cmds=()
declare -a file_cmds=()
declare -a secret_file_cmds=()
declare -a secret_dir_cmds=()

while IFS='|' read -r source target container_link flags disabled entry_type optional; do
    # Skip entries without target
    [[ -z "$target" ]] && continue
    # Skip dynamic pattern entries (G flag)
    [[ "$flags" == *G* ]] && continue
    # Optional entries are still initialized so data lives in the volume
    # Skip entries that only have container_link (container_symlinks section)
    # We still process them for volume initialization
    [[ "$entry_type" == "symlink" ]] && continue
    # Skip file entries with empty container_link - these are imported but not symlinked
    # (e.g., .gitconfig is copied at runtime, not init-created)
    if [[ "$flags" == *f* && -z "$container_link" ]]; then
        continue
    fi

    is_dir=0
    is_file=0
    is_json=0
    is_secret=0
    [[ "$flags" == *d* ]] && is_dir=1
    [[ "$flags" == *f* ]] && is_file=1
    [[ "$flags" == *j* ]] && is_json=1
    [[ "$flags" == *s* ]] && is_secret=1

    volume_path="${DATA_DIR}/${target}"

    if [[ $is_dir -eq 1 ]]; then
        if [[ $is_secret -eq 1 ]]; then
            secret_dir_cmds+=("ensure_dir \"$volume_path\"")
            secret_dir_cmds+=("safe_chmod 700 \"$volume_path\"")
        else
            dir_cmds+=("ensure_dir \"$volume_path\"")
        fi
    elif [[ $is_file -eq 1 ]]; then
        if [[ $is_json -eq 1 ]]; then
            if [[ $is_secret -eq 1 ]]; then
                secret_file_cmds+=("ensure_file \"$volume_path\" true")
                secret_file_cmds+=("safe_chmod 600 \"$volume_path\"")
            else
                file_cmds+=("ensure_file \"$volume_path\" true")
            fi
        else
            if [[ $is_secret -eq 1 ]]; then
                secret_file_cmds+=("ensure_file \"$volume_path\"")
                secret_file_cmds+=("safe_chmod 600 \"$volume_path\"")
            else
                file_cmds+=("ensure_file \"$volume_path\"")
            fi
        fi
    fi
# Include disabled entries - they document optional paths that may be imported via additional_paths
done < <("$PARSE_SCRIPT" --include-disabled "$MANIFEST_FILE")

# Also process container_symlinks section for volume-only entries
while IFS='|' read -r source target container_link flags disabled entry_type optional; do
    [[ "$entry_type" != "symlink" ]] && continue
    [[ -z "$target" ]] && continue
    # Optional entries are still initialized so data lives in the volume

    is_file=0
    is_json=0
    [[ "$flags" == *f* ]] && is_file=1
    [[ "$flags" == *j* ]] && is_json=1

    volume_path="${DATA_DIR}/${target}"

    if [[ $is_file -eq 1 ]]; then
        if [[ $is_json -eq 1 ]]; then
            file_cmds+=("ensure_file \"$volume_path\" true")
        else
            file_cmds+=("ensure_file \"$volume_path\"")
        fi
    fi
# Include disabled entries - they document optional paths that may be imported via additional_paths
done < <("$PARSE_SCRIPT" --include-disabled "$MANIFEST_FILE")

# Write output
{
    printf '#!/usr/bin/env bash\n'
    printf '# Generated from %s - DO NOT EDIT\n' "$(basename "$MANIFEST_FILE")"
    printf '# Regenerate with: src/scripts/gen-init-dirs.sh\n'
    printf '#\n'
    printf '# This script is sourced by containai-init.sh to create volume structure.\n'
    printf '# It uses helper functions defined in the parent script:\n'
    printf '#   ensure_dir <path>          - create directory with validation\n'
    printf '#   ensure_file <path> [json]  - create file (json=true for {} init)\n'
    printf '#   safe_chmod <mode> <path>   - chmod with symlink/path validation\n'
    printf '\n'

    printf '# Regular directories\n'
    for cmd in "${dir_cmds[@]}"; do
        printf '%s\n' "$cmd"
    done
    printf '\n'

    printf '# Regular files\n'
    for cmd in "${file_cmds[@]}"; do
        printf '%s\n' "$cmd"
    done
    printf '\n'

    printf '# Secret files (600 permissions)\n'
    for cmd in "${secret_file_cmds[@]}"; do
        printf '%s\n' "$cmd"
    done
    printf '\n'

    printf '# Secret directories (700 permissions)\n'
    for cmd in "${secret_dir_cmds[@]}"; do
        printf '%s\n' "$cmd"
    done
} > "$OUTPUT_FILE"

chmod +x "$OUTPUT_FILE"
printf 'Generated: %s\n' "$OUTPUT_FILE" >&2
