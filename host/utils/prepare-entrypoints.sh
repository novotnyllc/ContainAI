#!/usr/bin/env bash
# Builds channel-specific launcher entrypoints from the dev templates.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SOURCE="$SCRIPT_DIR/../launchers/entrypoints"
channel="dev"
source_dir="$DEFAULT_SOURCE"
dest_dir=""

print_help() {
    cat <<'EOF'
Usage: prepare-entrypoints.sh [--channel dev|prod|nightly] [--source DIR] [--dest DIR]

Copies dev-named launcher entrypoints to a target directory with channel-specific names:
  dev:     run-copilot-dev (default in repo)
  prod:    run-copilot
  nightly: run-copilot-nightly

If --dest is omitted, the source directory is updated in place (dev only). For prod/nightly you must provide --dest to avoid polluting the repo entrypoints path.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel) channel="$2"; shift 2 ;;
        --source) source_dir="$2"; shift 2 ;;
        --dest) dest_dir="$2"; shift 2 ;;
        -h|--help) print_help; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; print_help >&2; exit 1 ;;
    esac
done

case "$channel" in
    dev|prod|nightly) ;;
    *) echo "Unsupported channel: $channel" >&2; exit 1 ;;
esac

if [ ! -d "$source_dir" ]; then
    echo "Entrypoint source directory not found: $source_dir" >&2
    exit 1
fi

if [ -z "$dest_dir" ]; then
    if [ "$channel" != "dev" ]; then
        echo "--dest is required for channel $channel to avoid mutating the source directory" >&2
        exit 1
    fi
    dest_dir="$source_dir"
fi

if [ "$channel" != "dev" ] && [ "$dest_dir" = "$source_dir" ]; then
    echo "Refusing to write $channel entrypoints into source directory: $source_dir" >&2
    echo "Use --dest to point to a staging/output directory instead." >&2
    exit 1
fi

mkdir -p "$dest_dir"

generated_count=0
skipped_count=0
for template in "$source_dir"/*-dev "$source_dir"/*-dev.ps1; do
    [ -f "$template" ] || continue
    base=$(basename "$template")
    ext=""
    stem="$base"
    if [[ "$base" == *.ps1 ]]; then
        ext=".ps1"
        stem="${base%.ps1}"
    fi
    [[ "$stem" == *-dev ]] || continue
    stem="${stem%-dev}"
    case "$channel" in
        dev) target="${stem}-dev${ext}" ;;
        prod) target="${stem}${ext}" ;;
        nightly) target="${stem}-nightly${ext}" ;;
    esac
    target_path="$dest_dir/$target"
    if [ "$template" = "$target_path" ]; then
        # In-place dev mode: file already exists with correct name
        ((skipped_count++)) || true
        continue
    fi
    cp "$template" "$target_path"
    chmod --reference="$template" "$target_path" 2>/dev/null || true
    ((generated_count++)) || true
done

total_count=$((generated_count + skipped_count))
if [ "$total_count" -eq 0 ]; then
    echo "❌ No entrypoint templates found in $source_dir" >&2
    exit 1
fi

if [ "$skipped_count" -gt 0 ]; then
    echo "Prepared entrypoints for channel '$channel' in $dest_dir ($skipped_count already in place)"
else
    echo "Prepared $generated_count entrypoints for channel '$channel' in $dest_dir"
fi
