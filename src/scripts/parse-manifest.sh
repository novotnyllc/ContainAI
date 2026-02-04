#!/usr/bin/env bash
# Parse sync-manifest.toml and output entries in machine-readable format
# Usage: parse-manifest.sh [--include-disabled] [--emit-source-file] <manifest_path_or_dir>
# Output: One line per entry with fields: source|target|container_link|flags|disabled|type|optional[|source_file]
#   type: "entry" for [[entries]], "symlink" for [[container_symlinks]]
#   disabled: "true" or "false"
#   optional: "true" if flags contains 'o', "false" otherwise
#   source_file: path to originating manifest file (only with --emit-source-file)
# By default, disabled entries are excluded. Use --include-disabled to include them.
# When given a directory, iterates *.toml files in sorted order for deterministic output.
# The [agent] section is skipped (not needed for sync entries).
set -euo pipefail

INCLUDE_DISABLED=false
EMIT_SOURCE_FILE=false
MANIFEST_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --include-disabled)
            INCLUDE_DISABLED=true
            shift
            ;;
        --emit-source-file)
            EMIT_SOURCE_FILE=true
            shift
            ;;
        *)
            MANIFEST_PATH="$1"
            shift
            ;;
    esac
done

if [[ -z "$MANIFEST_PATH" ]]; then
    printf 'ERROR: manifest file or directory required\n' >&2
    exit 1
fi

# Build list of manifest files to process
MANIFEST_FILES=()
if [[ -d "$MANIFEST_PATH" ]]; then
    # Directory mode: iterate *.toml files in sorted order
    # Note: read returns non-zero on EOF, so we guard with || true
    while IFS= read -r -d '' file || [[ -n "$file" ]]; do
        MANIFEST_FILES+=("$file")
    done < <(find "$MANIFEST_PATH" -maxdepth 1 -name '*.toml' -type f -print0 | sort -z)
    if [[ ${#MANIFEST_FILES[@]} -eq 0 ]]; then
        printf 'ERROR: no .toml files found in directory: %s\n' "$MANIFEST_PATH" >&2
        exit 1
    fi
elif [[ -f "$MANIFEST_PATH" ]]; then
    # Single file mode (backward compatibility)
    MANIFEST_FILES=("$MANIFEST_PATH")
else
    printf 'ERROR: manifest file or directory not found: %s\n' "$MANIFEST_PATH" >&2
    exit 1
fi

# Process a single manifest file
# Arguments: $1 = manifest file path
process_manifest_file() {
    local manifest_file="$1"

    # State variables (local to prevent shell pollution)
    local in_entry=0
    local in_container_symlink=0
    local in_agent=0
    local source=""
    local target=""
    local container_link=""
    local flags=""
    local disabled="false"
    local line key value

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
            if [[ "$EMIT_SOURCE_FILE" == "true" ]]; then
                printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$source" "$target" "$container_link" "$flags" "$disabled" "$type" "$optional" "$manifest_file"
            else
                printf '%s|%s|%s|%s|%s|%s|%s\n' "$source" "$target" "$container_link" "$flags" "$disabled" "$type" "$optional"
            fi
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
            if [[ $in_entry -eq 1 ]]; then
                emit_entry "entry"
            elif [[ $in_container_symlink -eq 1 ]]; then
                emit_entry "symlink"
            fi
            in_entry=1
            in_container_symlink=0
            in_agent=0
            continue
        fi
        if [[ "$line" == "[[container_symlinks]]" ]]; then
            if [[ $in_entry -eq 1 ]]; then
                emit_entry "entry"
            elif [[ $in_container_symlink -eq 1 ]]; then
                emit_entry "symlink"
            fi
            in_entry=0
            in_container_symlink=1
            in_agent=0
            continue
        fi
        # Skip [agent] section (not needed for sync entries)
        if [[ "$line" == "[agent]" ]]; then
            if [[ $in_entry -eq 1 ]]; then
                emit_entry "entry"
            elif [[ $in_container_symlink -eq 1 ]]; then
                emit_entry "symlink"
            fi
            in_entry=0
            in_container_symlink=0
            in_agent=1
            continue
        fi

        # Skip lines while in [agent] section
        [[ $in_agent -eq 1 ]] && continue

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
    done < "$manifest_file"

    # Emit final entry if any
    if [[ $in_entry -eq 1 ]]; then
        emit_entry "entry"
    fi
    if [[ $in_container_symlink -eq 1 ]]; then
        emit_entry "symlink"
    fi
}

# Process all manifest files
for MANIFEST_FILE in "${MANIFEST_FILES[@]}"; do
    process_manifest_file "$MANIFEST_FILE"
done
