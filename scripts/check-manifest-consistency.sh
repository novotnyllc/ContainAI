#!/usr/bin/env bash
# Check consistency between src/manifests/ and generated import-sync-map.sh
#
# src/manifests/ is the authoritative source of truth for:
# - What gets synced from host $HOME to the data volume
# - What symlinks are created in the container image
# - What directory structure is initialized on first boot
# - What agents are available and their configurations
#
# This script verifies that:
# 1. All manifest files have valid TOML syntax
# 2. All manifests with [agent] sections have valid agent schema
# 3. The generated _IMPORT_SYNC_MAP in src/lib/import-sync-map.sh matches
#    what gen-import-map.sh produces from the manifests
#
# Architecture note: src/lib/import-sync-map.sh is the generated artifact that
# should be used by runtime code. The spec (fn-51) says this "replaces the
# hardcoded _IMPORT_SYNC_MAP in src/lib/import.sh". During transition, import.sh
# still contains a fallback map. This checker validates the generated file is
# correct; the runtime integration is handled separately.
#
# Usage: scripts/check-manifest-consistency.sh
# Exit codes:
#   0 - consistent
#   1 - inconsistent (errors printed to stderr)
#   2 - script error (missing files, etc.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MANIFESTS_DIR="${REPO_ROOT}/src/manifests"
IMPORT_SYNC_MAP="${REPO_ROOT}/src/lib/import-sync-map.sh"
GEN_IMPORT_MAP="${REPO_ROOT}/src/scripts/gen-import-map.sh"
PARSE_MANIFEST="${REPO_ROOT}/src/scripts/parse-manifest.sh"
PARSE_TOML="${REPO_ROOT}/src/parse-toml.py"

# Counters for summary
toml_passed=0
toml_failed=0
agent_passed=0
agent_failed=0
sync_map_passed=0
sync_map_failed=0

# Validate prerequisites
if [[ ! -d "$MANIFESTS_DIR" ]]; then
    printf 'ERROR: manifests directory not found: %s\n' "$MANIFESTS_DIR" >&2
    exit 2
fi
if [[ ! -f "$IMPORT_SYNC_MAP" ]]; then
    printf 'ERROR: import-sync-map.sh not found: %s\n' "$IMPORT_SYNC_MAP" >&2
    exit 2
fi
if [[ ! -x "$GEN_IMPORT_MAP" ]]; then
    printf 'ERROR: gen-import-map.sh not found or not executable: %s\n' "$GEN_IMPORT_MAP" >&2
    exit 2
fi
if [[ ! -x "$PARSE_MANIFEST" ]]; then
    printf 'ERROR: parse-manifest.sh not found or not executable: %s\n' "$PARSE_MANIFEST" >&2
    exit 2
fi
if [[ ! -f "$PARSE_TOML" ]]; then
    printf 'ERROR: parse-toml.py not found: %s\n' "$PARSE_TOML" >&2
    exit 2
fi

# Verify manifests exist
if ! compgen -G "${MANIFESTS_DIR}/*.toml" >/dev/null; then
    printf 'ERROR: no .toml files found in manifests directory: %s\n' "$MANIFESTS_DIR" >&2
    exit 2
fi

printf '=== Checking TOML syntax for all manifests ===\n'

# Validate TOML syntax using parse-toml.py
for manifest in "${MANIFESTS_DIR}"/*.toml; do
    manifest_name="$(basename "$manifest")"
    if ! python3 "$PARSE_TOML" --file "$manifest" --json >/dev/null 2>&1; then
        printf 'ERROR: invalid TOML syntax: %s\n' "$manifest_name" >&2
        # Get error message for diagnostics (|| true to avoid pipefail exit)
        python3 "$PARSE_TOML" --file "$manifest" --json 2>&1 | head -3 >&2 || true
        toml_failed=$((toml_failed + 1))
    else
        toml_passed=$((toml_passed + 1))
    fi
done

printf 'TOML syntax: %d passed, %d failed\n\n' "$toml_passed" "$toml_failed"

printf '=== Validating [agent] sections ===\n'

# Validate [agent] sections using parse-toml.py --emit-agents
# Call --emit-agents on all manifests; handle "null" return for those without [agent]
for manifest in "${MANIFESTS_DIR}"/*.toml; do
    manifest_name="$(basename "$manifest")"
    if ! agent_output=$(python3 "$PARSE_TOML" --file "$manifest" --emit-agents 2>&1); then
        printf 'ERROR: invalid [agent] section in %s\n' "$manifest_name" >&2
        printf '  %s\n' "$agent_output" >&2
        agent_failed=$((agent_failed + 1))
    else
        # "null" means no [agent] section - skip count
        if [[ "$agent_output" != "null" ]]; then
            agent_passed=$((agent_passed + 1))
        fi
    fi
done

printf '[agent] validation: %d passed, %d failed\n\n' "$agent_passed" "$agent_failed"

printf '=== Verifying _IMPORT_SYNC_MAP matches generated version ===\n'

# Generate expected import map and compare with actual
# Capture stderr to show on failure
gen_stderr=$(mktemp)
if ! expected_output=$("$GEN_IMPORT_MAP" "$MANIFESTS_DIR" 2>"$gen_stderr"); then
    printf 'ERROR: gen-import-map.sh failed\n' >&2
    cat "$gen_stderr" >&2
    rm -f "$gen_stderr"
    exit 2
fi
rm -f "$gen_stderr"

# Read actual import-sync-map.sh content
actual_output=$(cat "$IMPORT_SYNC_MAP")

# Compare (both should be identical)
if [[ "$expected_output" != "$actual_output" ]]; then
    printf 'ERROR: import-sync-map.sh does not match generated output\n' >&2
    printf 'Regenerate with: src/scripts/gen-import-map.sh src/manifests/ src/lib/import-sync-map.sh\n' >&2

    # Use parse-manifest.sh --emit-source-file to build source attribution
    # and show which manifest files have entries that differ
    printf '\nMismatched entries by source file:\n' >&2

    # Build expected entries with source file tracking
    if manifest_output=$("$PARSE_MANIFEST" --emit-source-file "$MANIFESTS_DIR" 2>/dev/null); then
        # Create temp files for comparison
        actual_entries=$(mktemp)
        expected_entries=$(mktemp)

        # Extract entries from actual import-sync-map.sh
        grep -oE '"/source/[^"]+:[^"]+:[^"]+"' "$IMPORT_SYNC_MAP" | tr -d '"' | sort > "$actual_entries" || true

        # Extract entries from generated output
        printf '%s\n' "$expected_output" | grep -oE '"/source/[^"]+:[^"]+:[^"]+"' | tr -d '"' | sort > "$expected_entries" || true

        # Find entries only in actual (stale entries)
        while IFS= read -r entry; do
            printf '  EXTRA (not in manifests): %s\n' "$entry" >&2
        done < <(comm -23 "$actual_entries" "$expected_entries")

        # Find entries only in expected (missing from actual)
        while IFS= read -r entry; do
            # Try to find source file for this entry
            source_path="${entry#/source/}"
            source_path="${source_path%%:*}"
            # Use -F for fixed string matching (source_path may contain regex metacharacters like '.')
            source_file=$(printf '%s\n' "$manifest_output" | grep -F "${source_path}|" | cut -d'|' -f8 | head -1)
            if [[ -n "$source_file" ]]; then
                source_file="$(basename "$source_file")"
                printf '  MISSING (from %s): %s\n' "$source_file" "$entry" >&2
            else
                printf '  MISSING: %s\n' "$entry" >&2
            fi
        done < <(comm -13 "$actual_entries" "$expected_entries")

        rm -f "$actual_entries" "$expected_entries"
    fi

    # Also show diff for full context
    printf '\nFull diff:\n' >&2
    diff -u <(printf '%s\n' "$actual_output") <(printf '%s\n' "$expected_output") >&2 || true
    sync_map_failed=1
else
    printf 'import-sync-map.sh is up to date\n'
    sync_map_passed=1
fi

printf '\n=== Summary ===\n'
total_passed=$((toml_passed + agent_passed + sync_map_passed))
total_failed=$((toml_failed + agent_failed + sync_map_failed))
printf 'TOML syntax:        %d passed, %d failed\n' "$toml_passed" "$toml_failed"
printf '[agent] validation: %d passed, %d failed\n' "$agent_passed" "$agent_failed"
printf 'Import map:         %d passed, %d failed\n' "$sync_map_passed" "$sync_map_failed"
printf 'Total:              %d passed, %d failed\n' "$total_passed" "$total_failed"

if [[ $total_failed -gt 0 ]]; then
    printf '\nFAILED: %d issues found\n' "$total_failed" >&2
    exit 1
else
    printf '\nOK: all checks passed\n'
    exit 0
fi
