#!/usr/bin/env bash
set -euo pipefail

# Constants
readonly SANDBOX_IMAGE="docker/sandbox-templates:claude-code"
readonly CUSTOM_IMAGE="claude-code:latest"
readonly DOCKERFILE_PATH="$HOME/.claude/templates/sandbox"

# Color output helpers
info() { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
error() { echo "❌ $*" >&2; }
warn() { echo "⚠️  $*"; }

# Get latest Claude Code version from npm
get_latest_npm_version() {
    npm view @anthropic-ai/claude-code version 2>/dev/null || echo ""
}

# Get version from a Docker image
get_image_version() {
    local image="$1"
    docker run --rm "$image" bash -c "source ~/.bashrc 2>/dev/null; claude --version 2>/dev/null | cut -d' ' -f1" 2>/dev/null || echo ""
}

# Compare two version strings (returns 0 if v1 >= v2)
version_gte() {
    local v1="$1"
    local v2="$2"
    [[ "$v1" == "$v2" ]] && return 0
    [[ "$(printf '%s\n' "$v1" "$v2" | sort -V | tail -n1)" == "$v1" ]]
}

# Clean up custom-built images
cleanup_custom_images() {
    info "Cleaning up custom-built Claude images..."
    docker images --format "{{.Repository}}:{{.Tag}}" | \
        grep "^claude-code:" | \
        xargs -r docker rmi 2>/dev/null || true
}

# Build new custom image
build_custom_image() {
    info "Building custom Claude Code image with latest version..."

    if ! docker build --no-cache \
        -f "$DOCKERFILE_PATH/Dockerfile" \
        -t "$CUSTOM_IMAGE" \
        "$DOCKERFILE_PATH"; then
        error "Build failed!"
        return 1
    fi

    info "Tagging custom image as sandbox template..."
    docker tag "$CUSTOM_IMAGE" "$SANDBOX_IMAGE"

    success "Custom Claude Code sandbox created successfully!"
    info "Run 'docker sandbox run claude' to use it"
}

# Pull and check official Docker template
check_official_template() {
    local latest_version="$1"

    info "Pulling official Docker template from Docker Hub..."

    if ! docker pull docker/sandbox-templates:claude-code 2>&1 | grep -q "Status:"; then
        warn "Failed to pull official template from Docker Hub"
        return 1
    fi

    local official_version
    official_version=$(get_image_version "$SANDBOX_IMAGE")

    if [[ -z "$official_version" ]]; then
        warn "Could not determine official template version"
        return 1
    fi

    echo "📦 Official template version: $official_version"

    if version_gte "$official_version" "$latest_version"; then
        success "Official template is up to date or newer!"
        cleanup_custom_images
        success "Using official template (version $official_version)"
        info "Run 'docker sandbox run claude' to use it"
        return 0
    fi

    info "Official template is outdated ($official_version < $latest_version)"
    return 1
}

# Main update logic
main() {
    info "Checking for Claude Code updates..."

    # Get latest version from npm
    local latest_version
    latest_version=$(get_latest_npm_version)

    if [[ -z "$latest_version" ]]; then
        error "Could not fetch latest version from npm"
        return 1
    fi

    echo "📦 Latest npm version: $latest_version"

    # Check if official Docker template is up to date
    if check_official_template "$latest_version"; then
        return 0
    fi

    # Official is outdated, build custom image with latest
    build_custom_image
}

# Run main function
main "$@"