#!/usr/bin/env bash
# Generate _IMPORT_SYNC_MAP indexed array from manifest files
# Usage: gen-import-map.sh <manifest_path_or_dir> [output_path]
# Reads manifest TOML file(s) and outputs bash code defining _IMPORT_SYNC_MAP
# When given a directory, iterates *.toml files in sorted order for deterministic output.
# If output_path is omitted, writes to stdout.
#
# Output format (indexed array, same as today):
#   _IMPORT_SYNC_MAP=(
#       "/source/.claude.json:/target/claude/claude.json:fjs"
#       "/source/.config/gh/hosts.yml:/target/config/gh/hosts.yml:fs"
#       # ... etc
#   )
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_PATH="${1:-}"
OUTPUT_FILE="${2:-}"

if [[ -z "$MANIFEST_PATH" ]]; then
    printf 'ERROR: manifest file or directory required as first argument\n' >&2
    exit 1
fi
if [[ ! -e "$MANIFEST_PATH" ]]; then
    printf 'ERROR: manifest path not found: %s\n' "$MANIFEST_PATH" >&2
    exit 1
fi

# Parse manifest
PARSE_SCRIPT="${SCRIPT_DIR}/parse-manifest.sh"
if [[ ! -x "$PARSE_SCRIPT" ]]; then
    printf 'ERROR: parse-manifest.sh not found or not executable\n' >&2
    exit 1
fi

# Determine header text based on whether input is file or directory
if [[ -d "$MANIFEST_PATH" ]]; then
    HEADER_SOURCE="src/manifests/"
else
    HEADER_SOURCE="$(basename "$MANIFEST_PATH")"
fi

# Collect entries
declare -a entries=()
declare -a comments=()
current_section=""

while IFS='|' read -r source target container_link flags disabled entry_type optional; do
    # Skip disabled entries (they're not in _IMPORT_SYNC_MAP)
    [[ "$disabled" == "true" ]] && continue

    # Skip container_symlinks (no import entry)
    [[ "$entry_type" == "symlink" ]] && continue

    # Skip entries without target
    [[ -z "$target" ]] && continue

    # Skip entries with 'g' flag (git-filter) - handled separately by _cai_import_git_config()
    [[ "$flags" == *g* ]] && continue

    # Strip flags not used by import (R = remove existing first, only for symlink creation)
    import_flags="${flags//R/}"

    # Build the entry in format: /source/<source>:/target/<target>:<flags>
    entry="/source/${source}:/target/${target}:${import_flags}"
    entries+=("$entry")
done < <("$PARSE_SCRIPT" "$MANIFEST_PATH")

# Generate output
generate_output() {
    printf '# Generated from %s - DO NOT EDIT\n' "$HEADER_SOURCE"
    printf '# Regenerate with: src/scripts/gen-import-map.sh src/manifests/\n'
    printf '#\n'
    printf '# This array maps host paths to volume paths for import.\n'
    printf '# Format: /source/<host_path>:/target/<volume_path>:<flags>\n'
    printf '#\n'
    printf '# Flags:\n'
    printf '#   f = file, d = directory\n'
    printf '#   j = json-init (create {} if empty)\n'
    printf '#   s = secret (skipped with --no-secrets)\n'
    printf '#   o = optional (skip if source does not exist)\n'
    printf '#   g = git-filter (strip credential.helper and signing config)\n'
    printf '#   x = exclude .system/ subdirectory\n'
    printf '#   p = exclude *.priv.* files\n'
    printf '\n'
    printf '_IMPORT_SYNC_MAP=(\n'
    for entry in "${entries[@]}"; do
        printf '    "%s"\n' "$entry"
    done
    printf ')\n'
}

if [[ -n "$OUTPUT_FILE" ]]; then
    generate_output > "$OUTPUT_FILE"
    printf 'Generated: %s (%d entries)\n' "$OUTPUT_FILE" "${#entries[@]}" >&2
else
    generate_output
fi
