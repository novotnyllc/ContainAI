#!/usr/bin/env bash
# Generates channel-specific security profiles from source templates.
# Called by build-payload.sh (CI) and setup-local-dev.sh (local dev) to ensure
# identical profile generation logic in both environments.
#
# Output: Channel-specific profiles with embedded profile names, ready for
# SHA256 validation and direct loading without runtime modification.
set -euo pipefail

print_help() {
    cat <<'EOF'
Usage: prepare-profiles.sh --channel CHANNEL --source DIR --dest DIR [--manifest PATH]

Generates channel-specific security profiles from source templates.

Options:
  --channel CHANNEL   Channel name (dev|nightly|prod) - determines profile naming
  --source DIR        Source directory containing template profiles
  --dest DIR          Destination directory for generated profiles
  --manifest PATH     Optional: write SHA256 manifest to this path
  -h, --help          Show this help

Profile Naming:
  Template profile:  profile containai-agent { ... }
  Generated (dev):   profile containai-agent-dev { ... }
  Generated (prod):  profile containai-agent-prod { ... }

The generated profiles are ready for direct loading with apparmor_parser
without any runtime modification. This ensures SHA256 checksums remain
valid from build time through installation.
EOF
}

CHANNEL=""
SOURCE_DIR=""
DEST_DIR=""
MANIFEST_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel) CHANNEL="$2"; shift 2 ;;
        --source) SOURCE_DIR="$2"; shift 2 ;;
        --dest) DEST_DIR="$2"; shift 2 ;;
        --manifest) MANIFEST_PATH="$2"; shift 2 ;;
        -h|--help) print_help; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; print_help >&2; exit 1 ;;
    esac
done

# Validate arguments
if [[ -z "$CHANNEL" || -z "$SOURCE_DIR" || -z "$DEST_DIR" ]]; then
    echo "❌ --channel, --source, and --dest are required" >&2
    print_help >&2
    exit 1
fi

case "$CHANNEL" in
    dev|nightly|prod) ;;
    *) echo "❌ Invalid channel: $CHANNEL (must be dev|nightly|prod)" >&2; exit 1 ;;
esac

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "❌ Source directory not found: $SOURCE_DIR" >&2
    exit 1
fi

mkdir -p "$DEST_DIR"

# Profile mappings: base_name -> source_filename
declare -A APPARMOR_PROFILES=(
    ["containai-agent"]="apparmor-containai-agent.profile"
    ["containai-proxy"]="apparmor-containai-proxy.profile"
    ["containai-log-forwarder"]="apparmor-containai-log-forwarder.profile"
)

declare -A SECCOMP_PROFILES=(
    ["containai-agent"]="seccomp-containai-agent.json"
    ["containai-proxy"]="seccomp-containai-proxy.json"
    ["containai-log-forwarder"]="seccomp-containai-log-forwarder.json"
)

# SHA256 helper
file_sha256() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$file"
    fi
}

# Generate AppArmor profile with channel-specific name
generate_apparmor_profile() {
    local base_name="$1"
    local source_file="$2"
    local dest_file="$3"
    local target_name="${base_name}-${CHANNEL}"

    python3 - "$target_name" "$base_name" "$source_file" "$dest_file" <<'PY'
import pathlib, re, sys

target_name, base_name, source_path, dest_path = sys.argv[1:]
text = pathlib.Path(source_path).read_text()

# Pattern matches: profile containai-agent flags=...
# and replaces base_name with target_name (channel-specific)
pattern = re.compile(
    r"^(\s*profile\s+)" + re.escape(base_name) + r"(\s)",
    re.MULTILINE
)
if not pattern.search(text):
    print(f"❌ Profile declaration not found for '{base_name}' in {source_path}", file=sys.stderr)
    sys.exit(1)

# Also update peer= references within the profile
text = pattern.sub(r"\g<1>" + target_name + r"\g<2>", text)

# Update peer=base_name references to peer=target_name
peer_pattern = re.compile(r"peer=" + re.escape(base_name) + r"(\s|,|$)")
text = peer_pattern.sub(r"peer=" + target_name + r"\1", text)

pathlib.Path(dest_path).write_text(text)
print(f"  ✓ Generated {dest_path}")
PY
}

# Track generated files for manifest
declare -a MANIFEST_ENTRIES=()

echo "📦 Generating channel-specific profiles (channel: $CHANNEL)"
echo "   Source: $SOURCE_DIR"
echo "   Dest:   $DEST_DIR"
echo ""

# Generate AppArmor profiles
echo "Generating AppArmor profiles..."
for base_name in "${!APPARMOR_PROFILES[@]}"; do
    source_file="$SOURCE_DIR/${APPARMOR_PROFILES[$base_name]}"
    # Output filename includes channel for clarity
    dest_filename="apparmor-${base_name}-${CHANNEL}.profile"
    dest_file="$DEST_DIR/$dest_filename"

    if [[ ! -f "$source_file" ]]; then
        echo "❌ Source profile missing: $source_file" >&2
        exit 1
    fi

    generate_apparmor_profile "$base_name" "$source_file" "$dest_file"
    MANIFEST_ENTRIES+=("$dest_filename $(file_sha256 "$dest_file")")
done

# Copy seccomp profiles with channel suffix for consistency
echo ""
echo "Copying seccomp profiles..."
for base_name in "${!SECCOMP_PROFILES[@]}"; do
    source_file="$SOURCE_DIR/${SECCOMP_PROFILES[$base_name]}"
    # Add channel suffix: seccomp-containai-agent.json -> seccomp-containai-agent-dev.json
    source_basename="${SECCOMP_PROFILES[$base_name]}"
    dest_filename="${source_basename%.json}-${CHANNEL}.json"
    dest_file="$DEST_DIR/$dest_filename"

    if [[ ! -f "$source_file" ]]; then
        echo "❌ Source seccomp profile missing: $source_file" >&2
        exit 1
    fi

    cp "$source_file" "$dest_file"
    echo "  ✓ Copied $dest_filename"
    MANIFEST_ENTRIES+=("$dest_filename $(file_sha256 "$dest_file")")
done

# Write manifest if requested
if [[ -n "$MANIFEST_PATH" ]]; then
    echo ""
    echo "Writing manifest: $MANIFEST_PATH"
    printf '%s\n' "${MANIFEST_ENTRIES[@]}" > "$MANIFEST_PATH"
fi

echo ""
echo "✅ Profile generation complete for channel '$CHANNEL'"
