#!/usr/bin/env bash
# Check consistency between sync-manifest.toml and _IMPORT_SYNC_MAP in import.sh
#
# sync-manifest.toml is the authoritative source of truth for:
# - What gets synced from host $HOME to the data volume
# - What symlinks are created in the container image
# - What directory structure is initialized on first boot
#
# This script verifies that the hardcoded _IMPORT_SYNC_MAP in src/lib/import.sh
# matches the manifest, catching drift between the two.
#
# Usage: scripts/check-manifest-consistency.sh
# Exit codes:
#   0 - consistent
#   1 - inconsistent (errors printed to stderr)
#   2 - script error (missing files, etc.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MANIFEST_FILE="${REPO_ROOT}/src/sync-manifest.toml"
IMPORT_SH="${REPO_ROOT}/src/lib/import.sh"
PARSE_SCRIPT="${REPO_ROOT}/src/scripts/parse-manifest.sh"

# Validate prerequisites
if [[ ! -f "$MANIFEST_FILE" ]]; then
    printf 'ERROR: manifest not found: %s\n' "$MANIFEST_FILE" >&2
    exit 2
fi
if [[ ! -f "$IMPORT_SH" ]]; then
    printf 'ERROR: import.sh not found: %s\n' "$IMPORT_SH" >&2
    exit 2
fi
if [[ ! -x "$PARSE_SCRIPT" ]]; then
    printf 'ERROR: parse-manifest.sh not found or not executable: %s\n' "$PARSE_SCRIPT" >&2
    exit 2
fi

# Helper to normalize a path for comparison
# Strips /source/ and /target/ prefixes that import.sh uses internally
normalize_path() {
    local path="$1"
    path="${path#/source/}"
    path="${path#/target/}"
    # Strip leading dot if present (manifest uses .claude, import uses .claude)
    printf '%s' "$path"
}

# Helper to extract flags (strip irrelevant flags for comparison)
# import.sh uses different flag conventions in some cases
normalize_flags() {
    local flags="$1"
    # For comparison, we only care about: f (file), d (dir), s (secret), j (json), x (exclude .system)
    # R (remove) and G (glob) are not in import map
    local result=""
    [[ "$flags" == *f* ]] && result+="f"
    [[ "$flags" == *d* ]] && result+="d"
    [[ "$flags" == *s* ]] && result+="s"
    [[ "$flags" == *j* ]] && result+="j"
    [[ "$flags" == *x* ]] && result+="x"
    printf '%s' "$result"
}

# Parse manifest into associative array: key=source, value="target:flags"
declare -A manifest_entries
while IFS='|' read -r source target container_link flags disabled entry_type; do
    # Skip container_symlinks section - not in import map
    [[ "$entry_type" == "symlink" ]] && continue
    # Skip dynamic pattern entries (G flag) - discovered at runtime
    [[ "$flags" == *G* ]] && continue
    # Skip entries with empty source (container-only)
    [[ -z "$source" ]] && continue
    # Skip .gitconfig - handled specially by _cai_import_git_config()
    [[ "$source" == ".gitconfig" ]] && continue

    norm_flags=$(normalize_flags "$flags")
    manifest_entries["$source"]="$target:$norm_flags"
done < <("$PARSE_SCRIPT" "$MANIFEST_FILE")

# Extract _IMPORT_SYNC_MAP entries from import.sh
# Format: "/source/<path>:/target/<path>:<flags>"
declare -A import_map_entries
in_sync_map=0
while IFS= read -r line; do
    # Detect start of _IMPORT_SYNC_MAP array
    if [[ "$line" =~ _IMPORT_SYNC_MAP=\( ]]; then
        in_sync_map=1
        continue
    fi
    # Detect end of array
    if [[ $in_sync_map -eq 1 && "$line" =~ ^\) ]]; then
        in_sync_map=0
        continue
    fi
    # Parse entry lines
    if [[ $in_sync_map -eq 1 ]]; then
        # Strip leading whitespace and quotes
        line="${line#"${line%%[![:space:]]*}"}"
        # Skip comments and empty lines
        [[ -z "$line" || "$line" == \#* ]] && continue
        # Extract quoted entry with full format: "/source/...:target:flags"
        # Must have exactly 3 colon-separated parts to be a valid entry
        if [[ "$line" =~ ^\"(/source/[^:]+:/target/[^:]+:[^\"]+)\" ]]; then
            entry="${BASH_REMATCH[1]}"
            # Parse source:target:flags
            source_part="${entry%%:*}"
            rest="${entry#*:}"
            target_part="${rest%%:*}"
            flags_part="${rest##*:}"

            # Normalize source (strip /source/ prefix)
            source_norm="${source_part#/source/}"
            # Normalize target (strip /target/ prefix)
            target_norm="${target_part#/target/}"
            # Normalize flags
            flags_norm=$(normalize_flags "$flags_part")

            import_map_entries["$source_norm"]="$target_norm:$flags_norm"
        fi
    fi
done < "$IMPORT_SH"

# Compare entries
errors=0

# Check manifest entries exist in import map
printf 'Checking manifest entries against import map...\n'
for source in "${!manifest_entries[@]}"; do
    manifest_val="${manifest_entries[$source]}"
    if [[ -z "${import_map_entries[$source]+x}" ]]; then
        printf 'ERROR: manifest entry missing from _IMPORT_SYNC_MAP: %s\n' "$source" >&2
        errors=$((errors + 1))
    else
        import_val="${import_map_entries[$source]}"
        if [[ "$manifest_val" != "$import_val" ]]; then
            printf 'ERROR: mismatch for %s:\n' "$source" >&2
            printf '  manifest: %s\n' "$manifest_val" >&2
            printf '  import:   %s\n' "$import_val" >&2
            errors=$((errors + 1))
        fi
    fi
done

# Check import map entries exist in manifest
printf 'Checking import map entries against manifest...\n'
for source in "${!import_map_entries[@]}"; do
    if [[ -z "${manifest_entries[$source]+x}" ]]; then
        printf 'ERROR: _IMPORT_SYNC_MAP entry missing from manifest: %s\n' "$source" >&2
        errors=$((errors + 1))
    fi
done

if [[ $errors -gt 0 ]]; then
    printf '\n%d inconsistencies found between manifest and import map.\n' "$errors" >&2
    printf 'sync-manifest.toml is the authoritative source - update _IMPORT_SYNC_MAP to match.\n' >&2
    exit 1
else
    printf 'OK: manifest and import map are consistent (%d entries checked)\n' "${#manifest_entries[@]}"
    exit 0
fi
