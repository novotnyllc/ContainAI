#!/usr/bin/env bash
# Parse sync-manifest.toml and output entries in machine-readable format
# Usage: parse-manifest.sh <manifest_path>
# Output: One line per entry with fields: source|target|container_link|flags|type
#   type: "entry" for [[entries]], "symlink" for [[container_symlinks]]
set -euo pipefail

MANIFEST_FILE="${1:-}"
if [[ -z "$MANIFEST_FILE" || ! -f "$MANIFEST_FILE" ]]; then
    printf 'ERROR: manifest file required\n' >&2
    exit 1
fi

# State variables
in_entry=0
in_container_symlink=0
source=""
target=""
container_link=""
flags=""

emit_entry() {
    local type="$1"
    if [[ -n "$target" && -n "$container_link" ]]; then
        printf '%s|%s|%s|%s|%s\n' "$source" "$target" "$container_link" "$flags" "$type"
    fi
    source=""
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
        if [[ $in_entry -eq 1 || $in_container_symlink -eq 1 ]]; then
            [[ $in_entry -eq 1 ]] && emit_entry "entry"
            [[ $in_container_symlink -eq 1 ]] && emit_entry "symlink"
        fi
        in_entry=1
        in_container_symlink=0
        continue
    fi
    if [[ "$line" == "[[container_symlinks]]" ]]; then
        if [[ $in_entry -eq 1 || $in_container_symlink -eq 1 ]]; then
            [[ $in_entry -eq 1 ]] && emit_entry "entry"
            [[ $in_container_symlink -eq 1 ]] && emit_entry "symlink"
        fi
        in_entry=0
        in_container_symlink=1
        continue
    fi

    # Parse key = "value" lines
    if [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*(#.*)?$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        case "$key" in
            source) source="$value" ;;
            target) target="$value" ;;
            container_link) container_link="$value" ;;
            flags) flags="$value" ;;
        esac
    fi
done < "$MANIFEST_FILE"

# Emit final entry if any
[[ $in_entry -eq 1 ]] && emit_entry "entry"
[[ $in_container_symlink -eq 1 ]] && emit_entry "symlink"
