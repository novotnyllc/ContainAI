#!/usr/bin/env bash
# Generate shell script for container symlinks from manifest
# Usage: gen-dockerfile-symlinks.sh <manifest_path> <output_path>
# Reads sync-manifest.toml and outputs executable shell script for symlink creation
# The script is COPY'd into the container and RUN during build
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

while IFS='|' read -r source target container_link flags disabled entry_type optional; do
    # Skip entries without container_link
    [[ -z "$container_link" ]] && continue
    # Skip dynamic pattern entries (G flag)
    [[ "$flags" == *G* ]] && continue
    # Optional entries are still symlinked so all agent data lives in the volume

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

    # Build symlink commands as structured entries (source|target|needs_rm)
    # R flag means "remove existing path first" for any entry type (file or directory)
    symlink_cmds+=("${volume_path}|${container_path}|${needs_rm}")
# Include disabled entries - they document optional paths that may be imported via additional_paths
done < <("$PARSE_SCRIPT" --include-disabled "$MANIFEST_FILE")

# Deduplicate mkdir targets
declare -A seen_dirs=()
unique_mkdir_targets=()
for dir in "${mkdir_targets[@]}"; do
    if [[ -z "${seen_dirs[$dir]:-}" ]]; then
        seen_dirs[$dir]=1
        unique_mkdir_targets+=("$dir")
    fi
done

# Write output as executable bash script with logging
{
    printf '#!/usr/bin/env bash\n'
    printf '# Generated from %s - DO NOT EDIT\n' "$(basename "$MANIFEST_FILE")"
    printf '# Regenerate with: src/scripts/gen-dockerfile-symlinks.sh\n'
    printf '# This script is COPY'"'"'d into the container and RUN during build\n'
    printf 'set -euo pipefail\n\n'

    # Logging helper function
    printf '# Logging helper - prints command and executes it\n'
    printf 'run_cmd() {\n'
    printf '    printf '"'"'+ %%s\\n'"'"' "$*"\n'
    printf '    if ! "$@"; then\n'
    printf '        local arg\n'
    printf '        printf '"'"'ERROR: Command failed: %%s\\n'"'"' "$*" >&2\n'
    printf '        printf '"'"'  id: %%s\\n'"'"' "$(id)" >&2\n'
    printf '        printf '"'"'  ls -ld /mnt/agent-data:\\n'"'"' >&2\n'
    printf '        # shellcheck disable=SC2012\n'
    printf '        ls -ld -- /mnt/agent-data 2>&1 | sed '"'"'s/^/    /'"'"' >&2 || printf '"'"'    (not found)\\n'"'"' >&2\n'
    printf '        # Show ls -ld for any absolute path arguments\n'
    printf '        for arg in "$@"; do\n'
    printf '            case "$arg" in\n'
    printf '                /home/*|/mnt/*)\n'
    printf '                    printf '"'"'  ls -ld %%s:\\n'"'"' "$arg" >&2\n'
    printf '                    # shellcheck disable=SC2012\n'
    printf '                    ls -ld -- "$arg" 2>&1 | sed '"'"'s/^/    /'"'"' >&2 || printf '"'"'    (not found)\\n'"'"' >&2\n'
    printf '                    ;;\n'
    printf '            esac\n'
    printf '        done\n'
    printf '        exit 1\n'
    printf '    fi\n'
    printf '}\n\n'

    # Verify /mnt/agent-data is writable
    printf '# Verify /mnt/agent-data is writable\n'
    printf 'if ! touch /mnt/agent-data/.write-test 2>/dev/null; then\n'
    printf '    printf '"'"'ERROR: /mnt/agent-data is not writable by %%s\\n'"'"' "$(id)" >&2\n'
    printf '    ls -la /mnt/agent-data 2>&1 || printf '"'"'/mnt/agent-data does not exist\\n'"'"' >&2\n'
    printf '    exit 1\n'
    printf 'fi\n'
    printf 'rm -f /mnt/agent-data/.write-test\n\n'

    # mkdir commands first
    if [[ ${#unique_mkdir_targets[@]} -gt 0 ]]; then
        printf 'run_cmd mkdir -p \\\n'
        for i in "${!unique_mkdir_targets[@]}"; do
            if [[ $i -eq $((${#unique_mkdir_targets[@]} - 1)) ]]; then
                printf '    %s\n' "${unique_mkdir_targets[$i]}"
            else
                printf '    %s \\\n' "${unique_mkdir_targets[$i]}"
            fi
        done
        printf '\n'
    fi

    # Symlink commands - emit separate rm and ln commands with proper quoting
    for entry in "${symlink_cmds[@]}"; do
        IFS='|' read -r volume_path container_path needs_rm <<< "$entry"
        if [[ "$needs_rm" == "1" ]]; then
            # Emit separate rm command before ln
            printf 'run_cmd rm -rf -- "%s"\n' "$container_path"
        fi
        printf 'run_cmd ln -sfn -- "%s" "%s"\n' "$volume_path" "$container_path"
    done
} > "$OUTPUT_FILE"

chmod +x "$OUTPUT_FILE"
printf 'Generated: %s\n' "$OUTPUT_FILE" >&2
