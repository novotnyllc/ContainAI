#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="$REPO_ROOT/src/manifests"

if [[ ! -d "$MANIFEST_DIR" ]]; then
    printf 'ERROR: manifest directory not found: %s\n' "$MANIFEST_DIR" >&2
    exit 1
fi

if ! command -v dotnet >/dev/null 2>&1; then
    printf 'ERROR: dotnet SDK is required for manifest consistency checks\n' >&2
    exit 1
fi

CAI_CMD=(dotnet run --project "$REPO_ROOT/src/cai" --)

printf '=== Validating manifest TOML parse ===\n'
for manifest in "$MANIFEST_DIR"/*.toml; do
    printf '  %s\n' "$(basename "$manifest")"
    "${CAI_CMD[@]}" manifest parse "$manifest" >/dev/null
done

printf '\n=== Validating generated artifacts ===\n'

import_map_tmp="$(mktemp)"
link_spec_tmp="$(mktemp)"
tmp_root="$(mktemp -d)"
trap 'rm -f "$import_map_tmp" "$link_spec_tmp"; rm -rf "$tmp_root"' EXIT

"${CAI_CMD[@]}" manifest generate import-map "$MANIFEST_DIR" "$import_map_tmp"
"${CAI_CMD[@]}" manifest generate container-link-spec "$MANIFEST_DIR" "$link_spec_tmp"
"${CAI_CMD[@]}" manifest apply init-dirs "$MANIFEST_DIR" --data-dir "$tmp_root/data" >/dev/null
"${CAI_CMD[@]}" manifest apply container-links "$MANIFEST_DIR" --home-dir "$tmp_root/home" --data-dir "$tmp_root/data" >/dev/null

if ! grep -q '^_IMPORT_SYNC_MAP=(' "$import_map_tmp"; then
    printf 'ERROR: generated import map missing _IMPORT_SYNC_MAP header\n' >&2
    exit 1
fi

if ! grep -q '"link"' "$link_spec_tmp" || ! grep -q '"target"' "$link_spec_tmp"; then
    printf 'ERROR: generated link spec appears invalid\n' >&2
    exit 1
fi

if [[ ! -d "$tmp_root/data" || ! -d "$tmp_root/home" ]]; then
    printf 'ERROR: manifest apply did not create expected directories\n' >&2
    exit 1
fi

printf 'Manifest consistency check passed.\n'
