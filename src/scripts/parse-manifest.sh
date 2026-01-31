#!/usr/bin/env bash
# Parse sync-manifest.toml and output entries in machine-readable format
# Usage: parse-manifest.sh [--include-disabled] <manifest_path>
# Output: One line per entry with fields: source|target|container_link|flags|disabled|type|optional
#   type: "entry" for [[entries]], "symlink" for [[container_symlinks]]
#   disabled: "true" or "false"
#   optional: "true" if flags contains 'o', "false" otherwise
# By default, disabled entries are excluded. Use --include-disabled to include them.
set -euo pipefail

INCLUDE_DISABLED=false
MANIFEST_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --include-disabled)
            INCLUDE_DISABLED=true
            shift
            ;;
        *)
            MANIFEST_FILE="$1"
            shift
            ;;
    esac
done

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
disabled="false"

emit_entry() {
    local type="$1"
    # Skip disabled entries unless --include-disabled is set
    if [[ "$disabled" == "true" && "$INCLUDE_DISABLED" == "false" ]]; then
        source=""
        target=""
        container_link=""
        flags=""
        disabled="false"
        return
    fi
    # Determine if entry is optional (has 'o' flag)
    local optional="false"
    if [[ "$flags" == *o* ]]; then
        optional="true"
    fi
    # Emit entry if target is set (container_link may be empty for some entries)
    if [[ -n "$target" ]]; then
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$source" "$target" "$container_link" "$flags" "$disabled" "$type" "$optional"
    fi
    source=""
    target=""
    container_link=""
    flags=""
    disabled="false"
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

    # Parse key = "value" lines (quoted strings)
    if [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*(#.*)?$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        case "$key" in
            source) source="$value" ;;
            target) target="$value" ;;
            container_link) container_link="$value" ;;
            flags) flags="$value" ;;
        esac
    # Parse key = value lines (booleans like disabled = true)
    elif [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*(#.*)?$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        case "$key" in
            disabled) disabled="$value" ;;
        esac
    fi
done < "$MANIFEST_FILE"

# Emit final entry if any
[[ $in_entry -eq 1 ]] && emit_entry "entry"
[[ $in_container_symlink -eq 1 ]] && emit_entry "symlink"
