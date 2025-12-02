#!/usr/bin/env bash
# Centralized base image build/cache management
# Ensures one version per channel, content-hash based caching
#
# Usage:
#   source host/utils/base-image.sh   # Source for functions
#   host/utils/base-image.sh build    # Build base image
#   host/utils/base-image.sh hash     # Show current content hash
#   host/utils/base-image.sh tag      # Show current tag
#   host/utils/base-image.sh list     # List all base images
#   host/utils/base-image.sh cleanup  # Remove old versions for channel

set -euo pipefail

# Use unique variable names to avoid collision when sourced by other scripts
_BASE_IMAGE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BASE_IMAGE_PROJECT_ROOT="$(cd "$_BASE_IMAGE_SCRIPT_DIR/../.." && pwd)"

# Export PROJECT_ROOT only if not already set (avoid overwriting caller's value)
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$_BASE_IMAGE_PROJECT_ROOT"
fi

# Note: We don't source env-detect.sh here to avoid SCRIPT_DIR collision.
# CONTAINAI_LAUNCHER_CHANNEL should be set by the caller if needed,
# otherwise defaults to "dev" in get_base_image_tag().

BASE_IMAGE_REPO="${CONTAINAI_BASE_IMAGE_REPO:-containai-base}"

# ============================================================================
# Content Hash Computation
# ============================================================================

# Compute a content hash of files that affect the base image
# This provides deterministic cache invalidation based on actual content changes
compute_base_image_hash() {
    local project_root="${1:-$PROJECT_ROOT}"
    {
        # Core Dockerfile
        cat "$project_root/docker/base/Dockerfile" 2>/dev/null || true
        # Runtime scripts that get copied into the image
        cat "$project_root/docker/runtime/"*.sh 2>/dev/null || true
        # Agent task runner source code (Rust)
        find "$project_root/docker/runtime/agent-task-runner" -type f -exec cat {} \; 2>/dev/null || true
        # Key host utilities that affect image behavior
        find "$project_root/host/utils" -name "*.sh" -type f -exec cat {} \; 2>/dev/null || true
    } | sha256sum | cut -c1-12
}

# ============================================================================
# Tag Management
# ============================================================================

# Get the full image tag for the current channel and content hash
get_base_image_tag() {
    local channel="${1:-${CONTAINAI_LAUNCHER_CHANNEL:-dev}}"
    local hash="${2:-$(compute_base_image_hash)}"
    echo "${BASE_IMAGE_REPO}:${channel}-${hash}"
}

# Get the tag prefix for a channel (used for cleanup)
get_base_image_channel_prefix() {
    local channel="${1:-${CONTAINAI_LAUNCHER_CHANNEL:-dev}}"
    echo "${BASE_IMAGE_REPO}:${channel}-"
}

# ============================================================================
# Build with Cache Management
# ============================================================================

# Build the base image if needed, returning the tag
# Automatically cleans up old versions of the same channel
build_base_image() {
    local channel="${1:-${CONTAINAI_LAUNCHER_CHANNEL:-dev}}"
    local project_root="${2:-$PROJECT_ROOT}"
    local force="${3:-false}"

    local hash
    hash=$(compute_base_image_hash "$project_root")
    local target_tag
    target_tag=$(get_base_image_tag "$channel" "$hash")

    echo "Base image: channel=${channel} hash=${hash}" >&2

    # Check if we already have this exact version
    if [[ "$force" != "true" ]] && docker image inspect "$target_tag" >/dev/null 2>&1; then
        echo "✓ Base image up-to-date: $target_tag" >&2
        echo "$target_tag"
        return 0
    fi

    echo "Building base image: $target_tag" >&2

    # Build new version
    if ! docker build -f "$project_root/docker/base/Dockerfile" -t "$target_tag" "$project_root"; then
        echo "❌ Base image build failed" >&2
        return 1
    fi

    # Clean up old versions of THIS CHANNEL only (after successful build)
    cleanup_old_base_images "$channel" "$target_tag"

    echo "✓ Base image ready: $target_tag" >&2
    echo "$target_tag"
}

# ============================================================================
# Cleanup
# ============================================================================

# Remove old base images for a specific channel, keeping the specified tag
cleanup_old_base_images() {
    local channel="${1:-${CONTAINAI_LAUNCHER_CHANNEL:-dev}}"
    local keep_tag="${2:-}"

    local channel_prefix
    channel_prefix=$(get_base_image_channel_prefix "$channel")

    local old_images
    old_images=$(docker images --format '{{.Repository}}:{{.Tag}}' \
        | grep "^${channel_prefix}" \
        | { grep -v "^${keep_tag}$" || true; } || true)

    if [[ -n "$old_images" ]]; then
        echo "Removing old base images for channel '$channel':" >&2
        echo "$old_images" | while read -r img; do
            if [[ -n "$img" ]]; then
                echo "  - $img" >&2
                docker rmi "$img" >/dev/null 2>&1 || true
            fi
        done
    fi
}

# Remove all base images for a channel
cleanup_all_base_images() {
    local channel="${1:-${CONTAINAI_LAUNCHER_CHANNEL:-dev}}"
    cleanup_old_base_images "$channel" ""
}

# ============================================================================
# Utility Functions
# ============================================================================

# List all base images on the system
list_base_images() {
    echo "Base images on host:" >&2
    docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}' \
        | grep -E "^${BASE_IMAGE_REPO}:|REPOSITORY" || echo "No base images found"
}

# Check if a specific base image exists
base_image_exists() {
    local tag="${1:-$(get_base_image_tag)}"
    docker image inspect "$tag" >/dev/null 2>&1
}

# ============================================================================
# Export for sourcing
# ============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced - export functions
    export -f compute_base_image_hash
    export -f get_base_image_tag
    export -f get_base_image_channel_prefix
    export -f build_base_image
    export -f cleanup_old_base_images
    export -f cleanup_all_base_images
    export -f list_base_images
    export -f base_image_exists
    export BASE_IMAGE_REPO
    export PROJECT_ROOT
fi

# ============================================================================
# CLI Interface
# ============================================================================

# If run directly, provide CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        build)
            build_base_image "${2:-}" "${3:-$PROJECT_ROOT}" "${4:-false}"
            ;;
        hash)
            compute_base_image_hash "${2:-$PROJECT_ROOT}"
            ;;
        tag)
            get_base_image_tag "${2:-}"
            ;;
        list)
            list_base_images
            ;;
        cleanup)
            cleanup_old_base_images "${2:-}"
            ;;
        cleanup-all)
            cleanup_all_base_images "${2:-}"
            ;;
        exists)
            if base_image_exists "${2:-}"; then
                echo "yes"
                exit 0
            else
                echo "no"
                exit 1
            fi
            ;;
        help|--help|-h)
            cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  build [channel] [project_root] [force]  Build base image (default)
  hash [project_root]                     Show content hash
  tag [channel]                           Show image tag for channel
  list                                    List all base images
  cleanup [channel]                       Remove old versions for channel
  cleanup-all [channel]                   Remove ALL versions for channel
  exists [tag]                            Check if image exists (exit 0/1)
  help                                    Show this help

Environment:
  CONTAINAI_LAUNCHER_CHANNEL  Channel name (default: dev)
  CONTAINAI_BASE_IMAGE_REPO   Image repository (default: containai-base)

Examples:
  $(basename "$0") build                  # Build for current channel
  $(basename "$0") build prod             # Build for prod channel
  $(basename "$0") tag dev                # Show dev channel tag
  $(basename "$0") cleanup dev            # Remove old dev images
EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            echo "Run '$(basename "$0") help' for usage" >&2
            exit 1
            ;;
    esac
fi
