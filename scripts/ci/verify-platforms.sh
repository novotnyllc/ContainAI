#!/usr/bin/env bash
# Verify that all expected platforms were built for multi-arch images.
# This script is used in CI to ensure no platform builds were silently skipped.
#
# Usage:
#   scripts/ci/verify-platforms.sh --digests-dir <dir> --expected-platforms <platforms>
#
# Arguments:
#   --digests-dir <dir>        Directory containing arch digest JSON files
#   --expected-platforms <p>   Comma-separated list of expected platforms (e.g., "linux/amd64,linux/arm64")
#   --image <name>             Image name to verify (optional, verifies all if not specified)
#
# The script checks that each expected platform has a corresponding digest artifact.
# Exit code 0 = all platforms present, 1 = missing platforms

set -euo pipefail

DIGESTS_DIR=""
EXPECTED_PLATFORMS=""
IMAGE_FILTER=""

print_help() {
    cat <<'EOF'
Usage: scripts/ci/verify-platforms.sh [options]

Verify that all expected platforms were built for multi-arch images.

Options:
  --digests-dir <dir>        Directory containing arch digest JSON files
  --expected-platforms <p>   Comma-separated list of expected platforms
  --image <name>             Image name to verify (optional, verifies all)
  -h, --help                 Show this help message

Example:
  ./scripts/ci/verify-platforms.sh \
    --digests-dir arch-digests \
    --expected-platforms "linux/amd64,linux/arm64" \
    --image containai-base
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --digests-dir)
            DIGESTS_DIR="$2"
            shift 2
            ;;
        --digests-dir=*)
            DIGESTS_DIR="${1#*=}"
            shift
            ;;
        --expected-platforms)
            EXPECTED_PLATFORMS="$2"
            shift 2
            ;;
        --expected-platforms=*)
            EXPECTED_PLATFORMS="${1#*=}"
            shift
            ;;
        --image)
            IMAGE_FILTER="$2"
            shift 2
            ;;
        --image=*)
            IMAGE_FILTER="${1#*=}"
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$DIGESTS_DIR" ]]; then
    echo "❌ --digests-dir is required" >&2
    exit 1
fi

if [[ -z "$EXPECTED_PLATFORMS" ]]; then
    echo "❌ --expected-platforms is required" >&2
    exit 1
fi

if [[ ! -d "$DIGESTS_DIR" ]]; then
    echo "❌ Digests directory does not exist: $DIGESTS_DIR" >&2
    exit 1
fi

# Parse expected platforms into array
IFS=',' read -ra PLATFORMS <<< "$EXPECTED_PLATFORMS"
echo "🔍 Verifying platforms: ${PLATFORMS[*]}"

# Find all unique images in the digests directory
if [[ -n "$IMAGE_FILTER" ]]; then
    IMAGES=("$IMAGE_FILTER")
else
    mapfile -t IMAGES < <(find "$DIGESTS_DIR" -name "*.json" -exec jq -r '.image // empty' {} \; 2>/dev/null | sort -u)
fi

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "❌ No images found in digests directory" >&2
    exit 1
fi

echo "📦 Checking images: ${IMAGES[*]}"
echo ""

MISSING=()
FOUND=()

for image in "${IMAGES[@]}"; do
    echo "  Checking $image..."
    
    for platform in "${PLATFORMS[@]}"; do
        # Convert platform to arch slug (linux/amd64 -> amd64)
        arch_slug="${platform##*/}"
        
        # Look for digest file for this image+arch combination
        digest_file=""
        
        # Try different naming patterns
        for pattern in "$DIGESTS_DIR/${image}-${arch_slug}.json" "$DIGESTS_DIR"/*"/${image}-${arch_slug}.json"; do
            if [[ -f "$pattern" ]]; then
                digest_file="$pattern"
                break
            fi
        done
        
        # Also search recursively
        if [[ -z "$digest_file" ]]; then
            digest_file=$(find "$DIGESTS_DIR" -name "${image}-${arch_slug}.json" -type f 2>/dev/null | head -1 || true)
        fi
        
        if [[ -n "$digest_file" && -f "$digest_file" ]]; then
            # Verify the file contains expected data
            file_image=$(jq -r '.image // empty' "$digest_file" 2>/dev/null || true)
            file_arch=$(jq -r '.arch // empty' "$digest_file" 2>/dev/null || true)
            file_digest=$(jq -r '.digest // empty' "$digest_file" 2>/dev/null || true)
            
            if [[ "$file_image" == "$image" && -n "$file_digest" ]]; then
                echo "    ✅ $platform: $file_digest"
                FOUND+=("$image:$platform")
            else
                echo "    ❌ $platform: digest file exists but has invalid content"
                MISSING+=("$image:$platform")
            fi
        else
            echo "    ❌ $platform: missing"
            MISSING+=("$image:$platform")
        fi
    done
    echo ""
done

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Platform Verification Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Expected platforms: ${PLATFORMS[*]}"
echo "Images checked:     ${#IMAGES[@]}"
echo "Platforms found:    ${#FOUND[@]}"
echo "Platforms missing:  ${#MISSING[@]}"

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo ""
    echo "❌ Missing platform builds:"
    for item in "${MISSING[@]}"; do
        echo "   - $item"
    done
    echo ""
    echo "This may indicate:"
    echo "  - A platform build job failed"
    echo "  - A platform was accidentally excluded from the matrix"
    echo "  - Artifact upload failed for the platform"
    exit 1
fi

echo ""
echo "✅ All expected platforms were built successfully!"
