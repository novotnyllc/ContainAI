#!/usr/bin/env bash
# Generate JSON link specification for container runtime verification
# Usage: gen-container-link-spec.sh <manifest_path> <output_path>
# Reads sync-manifest.toml and outputs JSON for link-repair.sh / cai links check
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

# Collect link specs
declare -a links=()

while IFS='|' read -r source target container_link flags disabled entry_type; do
    # Skip entries without container_link
    [[ -z "$container_link" ]] && continue
    # Skip dynamic pattern entries (G flag)
    [[ "$flags" == *G* ]] && continue

    needs_rm=0
    [[ "$flags" == *R* ]] && needs_rm=1

    # Build container_path (relative to $HOME_DIR)
    container_path="${HOME_DIR}/${container_link}"
    # Target on data volume
    volume_path="${DATA_MOUNT}/${target}"

    # Escape JSON special characters (minimal - just quotes and backslashes)
    container_path_escaped="${container_path//\\/\\\\}"
    container_path_escaped="${container_path_escaped//\"/\\\"}"
    volume_path_escaped="${volume_path//\\/\\\\}"
    volume_path_escaped="${volume_path_escaped//\"/\\\"}"

    link_json="    {\"link\": \"${container_path_escaped}\", \"target\": \"${volume_path_escaped}\", \"remove_first\": ${needs_rm}}"
    links+=("$link_json")
# Include disabled entries - they document optional paths that may be imported via additional_paths
done < <("$PARSE_SCRIPT" --include-disabled "$MANIFEST_FILE")

# Write output
{
    printf '{\n'
    printf '  "version": 1,\n'
    printf '  "data_mount": "%s",\n' "$DATA_MOUNT"
    printf '  "home_dir": "%s",\n' "$HOME_DIR"
    printf '  "links": [\n'
    for i in "${!links[@]}"; do
        if [[ $i -eq $((${#links[@]} - 1)) ]]; then
            printf '%s\n' "${links[$i]}"
        else
            printf '%s,\n' "${links[$i]}"
        fi
    done
    printf '  ]\n'
    printf '}\n'
} > "$OUTPUT_FILE"

printf 'Generated: %s (%d links)\n' "$OUTPUT_FILE" "${#links[@]}" >&2
