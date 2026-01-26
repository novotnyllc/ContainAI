#!/usr/bin/env bash
# Generate Dockerfile RUN commands for container symlinks from manifest
# Usage: gen-dockerfile-symlinks.sh <manifest_path> <output_path>
# Reads sync-manifest.toml and outputs Dockerfile fragment with symlink commands
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
DATA_MOUNT="/mnt/agent-data"
HOME_DIR="/home/agent"

# Collect mkdir commands and symlink commands
declare -a mkdir_targets=()
declare -a symlink_cmds=()

while IFS='|' read -r source target container_link flags entry_type; do
    # Skip entries without container_link
    [[ -z "$container_link" ]] && continue
    # Skip dynamic pattern entries (G flag)
    [[ "$flags" == *G* ]] && continue

    is_dir=0
    needs_rm=0
    [[ "$flags" == *d* ]] && is_dir=1
    [[ "$flags" == *R* ]] && needs_rm=1

    # Build container_path (relative to $HOME_DIR)
    container_path="${HOME_DIR}/${container_link}"
    # Target on data volume
    volume_path="${DATA_MOUNT}/${target}"

    # Parent directory for container_path
    parent_dir="$(dirname "$container_path")"

    # Add to mkdir targets if needed (for directory symlinks, create the parent)
    if [[ "$parent_dir" != "$HOME_DIR" ]]; then
        mkdir_targets+=("$parent_dir")
    fi

    # Add mkdir for volume path if directory
    if [[ $is_dir -eq 1 ]]; then
        mkdir_targets+=("$volume_path")
    fi

    # Build symlink command - combine rm and ln into single command string
    # R flag means "remove existing path first" for any entry type (file or directory)
    if [[ $needs_rm -eq 1 ]]; then
        # Entry with R flag: rm -rf before ln -sfn
        symlink_cmds+=("rm -rf ${container_path} && ln -sfn ${volume_path} ${container_path}")
    else
        # Regular symlink (file or directory without R flag)
        symlink_cmds+=("ln -sfn ${volume_path} ${container_path}")
    fi
done < <("$PARSE_SCRIPT" "$MANIFEST_FILE")

# Deduplicate mkdir targets
declare -A seen_dirs=()
unique_mkdir_targets=()
for dir in "${mkdir_targets[@]}"; do
    if [[ -z "${seen_dirs[$dir]:-}" ]]; then
        seen_dirs[$dir]=1
        unique_mkdir_targets+=("$dir")
    fi
done

# Write output
{
    printf '# Generated from %s - DO NOT EDIT\n' "$(basename "$MANIFEST_FILE")"
    printf '# Regenerate with: src/scripts/gen-dockerfile-symlinks.sh\n\n'
    printf 'RUN \\\n'

    # mkdir commands first
    if [[ ${#unique_mkdir_targets[@]} -gt 0 ]]; then
        printf '    mkdir -p \\\n'
        for i in "${!unique_mkdir_targets[@]}"; do
            if [[ $i -eq $((${#unique_mkdir_targets[@]} - 1)) ]]; then
                printf '        %s && \\\n' "${unique_mkdir_targets[$i]}"
            else
                printf '        %s \\\n' "${unique_mkdir_targets[$i]}"
            fi
        done
    fi

    # Symlink commands
    total=${#symlink_cmds[@]}
    for i in "${!symlink_cmds[@]}"; do
        cmd="${symlink_cmds[$i]}"
        if [[ $i -eq $((total - 1)) ]]; then
            # Last command - no trailing backslash or &&
            printf '    %s\n' "$cmd"
        else
            printf '    %s && \\\n' "$cmd"
        fi
    done
} > "$OUTPUT_FILE"

printf 'Generated: %s\n' "$OUTPUT_FILE" >&2
