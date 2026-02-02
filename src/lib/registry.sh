#!/usr/bin/env bash
# ==============================================================================
# ContainAI Registry Library - GHCR registry API helpers
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_ghcr_token()           - Get anonymous token for GHCR
#   _cai_ghcr_manifest_digest() - Get manifest digest via HEAD request
#   _cai_ghcr_image_metadata()  - Get image metadata (size, created, version)
#   _cai_registry_cache_get()   - Get cached registry data
#   _cai_registry_cache_set()   - Cache registry data
#   _cai_base_image()           - Get base image based on channel config
#
# Dependencies:
#   - Requires lib/core.sh to be sourced first for logging functions
#   - Requires curl for API requests
#   - Requires python3 for JSON parsing
#
# Usage: source lib/registry.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    printf '%s\n' "[ERROR] lib/registry.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s\n' "[ERROR] lib/registry.sh must be sourced, not executed directly" >&2
    printf '%s\n' "Usage: source lib/registry.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_REGISTRY_LOADED:-}" ]]; then
    return 0
fi
_CAI_REGISTRY_LOADED=1

# ==============================================================================
# Constants
# ==============================================================================

# Registry API timeout in seconds for freshness checks
# Per spec: "Registry API calls timeout at 2 seconds"
_CAI_REGISTRY_TIMEOUT=2

# Cache TTL in seconds (60 minutes)
_CAI_REGISTRY_CACHE_TTL=3600

# Cache directory
_CAI_REGISTRY_CACHE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containai/cache/registry"

# Default ContainAI image
_CAI_DEFAULT_IMAGE="ghcr.io/novotnyllc/containai"

# ==============================================================================
# Base Image Resolution
# ==============================================================================

# Get base image based on channel configuration
# Uses _cai_config_channel() for precedence resolution and validation
# Outputs: Full image reference (e.g., ghcr.io/novotnyllc/containai:latest)
_cai_base_image() {
    local channel

    # Use _cai_config_channel() for precedence and validation (emits warnings for invalid values)
    if command -v _cai_config_channel >/dev/null 2>&1; then
        channel=$(_cai_config_channel)
    else
        # Fallback if config.sh not loaded: simple precedence without warnings
        channel="${_CAI_CHANNEL_OVERRIDE:-${CONTAINAI_CHANNEL:-${_CAI_IMAGE_CHANNEL:-stable}}}"
    fi

    # Map channel to image tag
    case "$channel" in
        nightly)
            printf '%s' "$_CAI_DEFAULT_IMAGE:nightly"
            ;;
        *)
            printf '%s' "$_CAI_DEFAULT_IMAGE:latest"
            ;;
    esac
}

# ==============================================================================
# Cache Functions
# ==============================================================================

# Ensure cache directory exists
_cai_registry_ensure_cache_dir() {
    if [[ ! -d "$_CAI_REGISTRY_CACHE_DIR" ]]; then
        mkdir -p "$_CAI_REGISTRY_CACHE_DIR" 2>/dev/null || return 1
    fi
    return 0
}

# Get cached registry data
# Args: $1 = image (e.g., "novotnyllc/containai"), $2 = tag, $3 = prefix (optional, for namespace)
# Outputs: JSON cache data if valid, empty if expired/missing
# Returns: 0 if cache hit, 1 if miss
_cai_registry_cache_get() {
    local image="$1"
    local tag="$2"
    local prefix="${3:-}"
    local cache_file cache_time now

    # Sanitize image and tag for filename (replace non-safe chars with -)
    local safe_image="${image//\//-}"
    local safe_tag="${tag//[^A-Za-z0-9_.-]/-}"
    if [[ -n "$prefix" ]]; then
        cache_file="$_CAI_REGISTRY_CACHE_DIR/${prefix}-${safe_image}-${safe_tag}.json"
    else
        cache_file="$_CAI_REGISTRY_CACHE_DIR/${safe_image}-${safe_tag}.json"
    fi

    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    # Check if cache is expired
    # Use stat -c for Linux, fall back to date-based check
    if command -v stat >/dev/null 2>&1; then
        if stat --version 2>/dev/null | grep -q GNU; then
            cache_time=$(stat -c '%Y' "$cache_file" 2>/dev/null) || return 1
        else
            # BSD stat
            cache_time=$(stat -f '%m' "$cache_file" 2>/dev/null) || return 1
        fi
    else
        return 1
    fi

    now=$(date +%s)
    if (( now - cache_time > _CAI_REGISTRY_CACHE_TTL )); then
        # Cache expired
        return 1
    fi

    # Output cache content
    cat "$cache_file"
    return 0
}

# Cache registry data
# Args: $1 = image, $2 = tag, $3 = prefix (optional, for namespace), stdin = JSON data to cache
# Returns: 0 on success, 1 on failure
_cai_registry_cache_set() {
    local image="$1"
    local tag="$2"
    local prefix="${3:-}"

    if ! _cai_registry_ensure_cache_dir; then
        return 1
    fi

    # Sanitize image and tag for filename
    local safe_image="${image//\//-}"
    local safe_tag="${tag//[^A-Za-z0-9_.-]/-}"
    local cache_file
    if [[ -n "$prefix" ]]; then
        cache_file="$_CAI_REGISTRY_CACHE_DIR/${prefix}-${safe_image}-${safe_tag}.json"
    else
        cache_file="$_CAI_REGISTRY_CACHE_DIR/${safe_image}-${safe_tag}.json"
    fi

    cat > "$cache_file" 2>/dev/null
}

# ==============================================================================
# GHCR API Functions
# ==============================================================================

# Get anonymous token for GHCR
# Args: $1 = image (e.g., "novotnyllc/containai"), $2 = timeout seconds (optional)
# Outputs: Token string
# Returns: 0 on success, 1 on failure
_cai_ghcr_token() {
    local image="$1"
    local timeout="${2:-$_CAI_REGISTRY_TIMEOUT}"
    local response

    response=$(curl -sf --max-time "$timeout" \
        "https://ghcr.io/token?scope=repository:${image}:pull" 2>/dev/null) || return 1

    if [[ -z "$response" ]]; then
        return 1
    fi

    printf '%s' "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    token = data.get('token', '')
    if token:
        print(token, end='')
    else:
        sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null || return 1
}

# Get manifest digest via HEAD request
# Args: $1 = image, $2 = tag, $3 = token
# Outputs: Digest (sha256:...)
# Returns: 0 on success, 1 on failure
_cai_ghcr_manifest_digest() {
    local image="$1"
    local tag="$2"
    local token="$3"
    local headers

    headers=$(curl -sf --max-time "$_CAI_REGISTRY_TIMEOUT" -I \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json" \
        "https://ghcr.io/v2/${image}/manifests/${tag}" 2>/dev/null) || return 1

    # Extract Docker-Content-Digest header (case-insensitive)
    printf '%s' "$headers" | grep -i "docker-content-digest" | awk '{print $2}' | tr -d '\r\n'
}

# Get image metadata from registry
# Args: $1 = full image reference (e.g., ghcr.io/novotnyllc/containai:latest)
# Outputs: JSON object with size, created, version (to stdout)
# Returns: 0 on success, 1 on failure (network, auth, etc.)
# Note: Enforces 2s total time budget - skips optional calls if budget exhausted
_cai_ghcr_image_metadata() {
    local full_image="$1"
    local image tag token manifest
    local start_time

    # Record start time for budget tracking (monotonic)
    start_time=$(python3 -c "import time; print(time.monotonic())" 2>/dev/null || date +%s)

    # Remaining time budget in seconds (float). Returns non-zero if exhausted.
    _cai_registry_time_left() {
        _CAI_REGISTRY_START="$start_time" _CAI_REGISTRY_BUDGET="$_CAI_REGISTRY_TIMEOUT" python3 - <<'PY'
import os, time, sys
try:
    start = float(os.environ.get('_CAI_REGISTRY_START', '0'))
    budget = float(os.environ.get('_CAI_REGISTRY_BUDGET', '2'))
    now = time.monotonic()
    remaining = budget - (now - start)
    if remaining <= 0:
        sys.exit(1)
    print(f"{remaining:.3f}")
except Exception:
    sys.exit(1)
PY
    }

    # Parse image reference
    # Handle ghcr.io/org/repo:tag format
    local ref="${full_image#ghcr.io/}"
    if [[ "$ref" == "$full_image" ]]; then
        # Not a ghcr.io image
        return 1
    fi

    # Split into image and tag
    if [[ "$ref" == *:* ]]; then
        image="${ref%:*}"
        tag="${ref##*:}"
    else
        image="$ref"
        tag="latest"
    fi

    # Check cache first (use "meta" prefix to avoid collision with freshness cache)
    local cached
    if cached=$(_cai_registry_cache_get "$image" "$tag" "meta" 2>/dev/null); then
        # Validate cached JSON is not empty
        if [[ -n "$cached" ]] && [[ "$cached" != "{}" ]]; then
            printf '%s' "$cached"
            return 0
        fi
    fi

    # Get token (respect remaining time budget)
    local remaining_time
    if ! remaining_time=$(_cai_registry_time_left); then
        return 1
    fi
    if ! token=$(_cai_ghcr_token "$image" "$remaining_time"); then
        return 1
    fi

    # Get manifest (handles both single and multi-arch)
    if ! remaining_time=$(_cai_registry_time_left); then
        return 1
    fi
    manifest=$(curl -sf --max-time "$remaining_time" \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json" \
        "https://ghcr.io/v2/${image}/manifests/${tag}" 2>/dev/null) || return 1

    # Detect host architecture for multi-arch manifest selection
    # Map uname -m to OCI architecture names
    local host_arch
    case "$(uname -m)" in
        x86_64)  host_arch="amd64" ;;
        aarch64) host_arch="arm64" ;;
        armv7l)  host_arch="arm" ;;
        *)       host_arch="amd64" ;;  # Fallback to amd64
    esac

    # Parse manifest to get platform-specific manifest digest (for multi-arch)
    # or extract size directly (for single manifest)
    local parse_result
    parse_result=$(printf '%s' "$manifest" | _CAI_HOST_ARCH="$host_arch" python3 -c "
import sys, json, os

try:
    manifest = json.load(sys.stdin)
    media_type = manifest.get('mediaType', '')
    host_arch = os.environ.get('_CAI_HOST_ARCH', 'amd64')

    # Multi-arch manifest list - find matching host arch or first available
    if media_type in ['application/vnd.oci.image.index.v1+json',
                       'application/vnd.docker.distribution.manifest.list.v2+json']:
        manifests = manifest.get('manifests', [])
        target = None
        for m in manifests:
            platform = m.get('platform', {})
            if platform.get('os') == 'linux' and platform.get('architecture') == host_arch:
                target = m
                break
        if not target and manifests:
            target = manifests[0]  # Fallback to first
        if target:
            print('MULTIARCH')
            print(target.get('digest', ''))
        else:
            print('ERROR')

    # Single manifest - calculate size and get config digest
    elif media_type in ['application/vnd.docker.distribution.manifest.v2+json',
                         'application/vnd.oci.image.manifest.v1+json']:
        size = 0
        for layer in manifest.get('layers', []):
            size += layer.get('size', 0)
        size += manifest.get('config', {}).get('size', 0)
        config_digest = manifest.get('config', {}).get('digest', '')
        print('SINGLE')
        print(size)
        print(config_digest)
    else:
        print('ERROR')
except Exception:
    print('ERROR')
" 2>/dev/null)

    local manifest_type size config_digest platform_manifest
    manifest_type=$(printf '%s' "$parse_result" | head -1)

    if [[ "$manifest_type" == "MULTIARCH" ]]; then
        # Fetch platform-specific manifest
        local platform_digest
        platform_digest=$(printf '%s' "$parse_result" | sed -n '2p')
        if [[ -z "$platform_digest" ]]; then
            return 1
        fi
        if ! remaining_time=$(_cai_registry_time_left); then
            return 1
        fi
        platform_manifest=$(curl -sf --max-time "$remaining_time" \
            -H "Authorization: Bearer $token" \
            -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json" \
            "https://ghcr.io/v2/${image}/manifests/${platform_digest}" 2>/dev/null) || {
            return 1
        }

        # Parse platform manifest for size and config digest
        local platform_parse
        platform_parse=$(printf '%s' "$platform_manifest" | python3 -c "
import sys, json
try:
    manifest = json.load(sys.stdin)
    size = 0
    for layer in manifest.get('layers', []):
        size += layer.get('size', 0)
    size += manifest.get('config', {}).get('size', 0)
    config_digest = manifest.get('config', {}).get('digest', '')
    print(size)
    print(config_digest)
except:
    print('0')
    print('')
" 2>/dev/null)
        size=$(printf '%s' "$platform_parse" | head -1)
        config_digest=$(printf '%s' "$platform_parse" | sed -n '2p')

    elif [[ "$manifest_type" == "SINGLE" ]]; then
        size=$(printf '%s' "$parse_result" | sed -n '2p')
        config_digest=$(printf '%s' "$parse_result" | sed -n '3p')
    else
        return 1
    fi

    # Fetch config blob to get labels (created, version) - only if budget allows
    local created="" version=""
    if [[ -n "$config_digest" ]]; then
        if ! remaining_time=$(_cai_registry_time_left); then
            config_digest=""
        fi
    fi
    if [[ -n "$config_digest" ]]; then
        local config_blob
        config_blob=$(curl -sf --max-time "$remaining_time" \
            -H "Authorization: Bearer $token" \
            "https://ghcr.io/v2/${image}/blobs/${config_digest}" 2>/dev/null) || true

        if [[ -n "$config_blob" ]]; then
            local labels_parse
            labels_parse=$(printf '%s' "$config_blob" | python3 -c "
import sys, json
try:
    config = json.load(sys.stdin)
    labels = config.get('config', {}).get('Labels', {})
    created = labels.get('org.opencontainers.image.created', '')
    version = labels.get('org.opencontainers.image.version', '')
    print(created)
    print(version)
except:
    print('')
    print('')
" 2>/dev/null)
            created=$(printf '%s' "$labels_parse" | head -1)
            version=$(printf '%s' "$labels_parse" | sed -n '2p')
        fi
    fi

    # Build result JSON using environment variables to avoid shell interpolation issues
    local metadata
    metadata=$(_CAI_SIZE="${size:-0}" _CAI_CREATED="$created" _CAI_VERSION="$version" python3 -c "
import os, json
result = {
    'size': int(os.environ.get('_CAI_SIZE', '0') or '0'),
    'created': os.environ.get('_CAI_CREATED', ''),
    'version': os.environ.get('_CAI_VERSION', '')
}
print(json.dumps(result))
" 2>/dev/null)

    if [[ -z "$metadata" ]] || [[ "$metadata" == "{}" ]]; then
        return 1
    fi

    # Cache the result (use "meta" prefix to avoid collision with freshness cache)
    printf '%s' "$metadata" | _cai_registry_cache_set "$image" "$tag" "meta" 2>/dev/null || true

    printf '%s' "$metadata"
    return 0
}

# Format bytes to human-readable size
# Args: $1 = bytes
# Outputs: Human-readable size (e.g., "2.1 GB")
_cai_format_size() {
    local bytes="$1"

    python3 -c "
import sys
try:
    b = int(sys.argv[1])
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if b < 1024:
            print(f'~{b:.1f} {unit}')
            break
        b /= 1024
except:
    print('unknown size')
" "$bytes" 2>/dev/null || printf 'unknown size'
}

# ==============================================================================
# Local Image Inspection
# ==============================================================================

# Get local image digest from RepoDigests
# For multi-arch images, RepoDigests contains the manifest list digest
# Args: $1 = full image reference, $2 = docker_context (optional)
# Outputs: Digest (sha256:...) to stdout
# Returns: 0 on success, 1 if image not found or no digest
_cai_local_image_digest() {
    local image="$1"
    local docker_context="${2:-}"
    local -a docker_cmd=(docker)
    local repo_digest

    if [[ -n "$docker_context" ]]; then
        docker_cmd=(docker --context "$docker_context")
    fi

    # Get first RepoDigest - for images pulled from registry, this is the manifest list digest
    repo_digest=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" image inspect "$image" \
        --format '{{index .RepoDigests 0}}' 2>/dev/null) || return 1

    if [[ -z "$repo_digest" ]]; then
        return 1
    fi

    # Extract just the digest part (after @)
    # Format: ghcr.io/novotnyllc/containai@sha256:abc123...
    local digest="${repo_digest##*@}"
    if [[ -z "$digest" ]] || [[ "$digest" == "$repo_digest" ]]; then
        return 1
    fi

    printf '%s' "$digest"
}

# Get local image version from OCI labels
# Args: $1 = full image reference, $2 = docker_context (optional)
# Outputs: Version string to stdout (e.g., "0.1.0")
# Returns: 0 on success, 1 if image not found or no version label
_cai_local_image_version() {
    local image="$1"
    local docker_context="${2:-}"
    local -a docker_cmd=(docker)
    local version

    if [[ -n "$docker_context" ]]; then
        docker_cmd=(docker --context "$docker_context")
    fi

    version=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" image inspect "$image" \
        --format '{{index .Config.Labels "org.opencontainers.image.version"}}' 2>/dev/null) || return 1

    if [[ -z "$version" ]]; then
        return 1
    fi

    printf '%s' "$version"
}

# Get local image created date from OCI labels
# Args: $1 = full image reference, $2 = docker_context (optional)
# Outputs: Created date (YYYY-MM-DD) to stdout
# Returns: 0 on success, 1 if image not found or no created label
_cai_local_image_created() {
    local image="$1"
    local docker_context="${2:-}"
    local -a docker_cmd=(docker)
    local created_raw

    if [[ -n "$docker_context" ]]; then
        docker_cmd=(docker --context "$docker_context")
    fi

    created_raw=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" image inspect "$image" \
        --format '{{index .Config.Labels "org.opencontainers.image.created"}}' 2>/dev/null) || return 1

    if [[ -z "$created_raw" ]]; then
        return 1
    fi

    # Format: extract YYYY-MM-DD from ISO format
    printf '%s' "${created_raw:0:10}"
}

# ==============================================================================
# Image Freshness Check
# ==============================================================================

# Check if a newer base image is available and display notice
# This is a non-blocking check - never fails the overall flow
# Args: $1 = full image reference, $2 = docker_context (optional)
# Returns: Always 0 (never blocks startup)
# Outputs: [NOTICE] message to stderr if newer image available
#
# Error handling per epic:
# - 401/403 auth failure: [NOTICE] Cannot check for updates (authentication required)
# - Network timeout/error: [NOTICE] Cannot check for updates (network error)
# - Parse error: silently skip (internal issue, not user-actionable)
_cai_check_image_freshness() {
    local full_image="$1"
    local docker_context="${2:-}"
    local image tag
    local local_digest remote_digest
    local local_version local_created
    local remote_version remote_created

    # Parse image reference
    local ref="${full_image#ghcr.io/}"
    if [[ "$ref" == "$full_image" ]]; then
        # Not a ghcr.io image - skip check silently
        return 0
    fi

    # Split into image and tag
    if [[ "$ref" == *:* ]]; then
        image="${ref%:*}"
        tag="${ref##*:}"
    else
        image="$ref"
        tag="latest"
    fi

    # Get local image info
    if ! local_digest=$(_cai_local_image_digest "$full_image" "$docker_context"); then
        # No local digest - image might not have been pulled from registry
        # Silently skip (could be a locally built image)
        return 0
    fi

    # Get local version and created date for display
    local_version=$(_cai_local_image_version "$full_image" "$docker_context") || local_version=""
    local_created=$(_cai_local_image_created "$full_image" "$docker_context") || local_created=""

    # Check cache for recent check (avoid redundant network calls)
    # Per spec: cache key is <image>-<tag>.json with {digest, version, created, checked_at}
    local cached
    if cached=$(_cai_registry_cache_get "$image" "$tag" 2>/dev/null); then
        # Parse cached digest
        local cached_digest
        cached_digest=$(printf '%s' "$cached" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('digest', ''), end='')
except:
    pass
" 2>/dev/null) || cached_digest=""

        if [[ -n "$cached_digest" ]]; then
            if [[ "$cached_digest" == "$local_digest" ]]; then
                # Cached remote digest matches local - no update available
                return 0
            fi
            # Cached remote digest differs - use cached metadata for display
            remote_digest="$cached_digest"
            remote_version=$(printf '%s' "$cached" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('version', ''), end='')
except:
    pass
" 2>/dev/null) || remote_version=""
            remote_created=$(printf '%s' "$cached" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('created', '')[:10] if data.get('created') else '', end='')
except:
    pass
" 2>/dev/null) || remote_created=""
            # Display notice and return
            _cai_display_freshness_notice "$local_version" "$local_created" "$remote_version" "$remote_created"
            return 0
        fi
    fi

    # Get token for registry access with HTTP status check for auth errors
    local token token_response http_status
    token_response=$(curl -s --max-time "$_CAI_REGISTRY_TIMEOUT" -w '\n%{http_code}' \
        "https://ghcr.io/token?scope=repository:${image}:pull" 2>/dev/null) || {
        _cai_notice "Cannot check for updates (network error)"
        return 0
    }

    # Extract HTTP status code (last line)
    http_status="${token_response##*$'\n'}"
    token_response="${token_response%$'\n'"$http_status"}"

    # Check for auth errors (401, 403)
    if [[ "$http_status" == "401" ]] || [[ "$http_status" == "403" ]]; then
        _cai_notice "Cannot check for updates (authentication required)"
        return 0
    fi

    # Check for other HTTP errors
    if [[ "${http_status:0:1}" != "2" ]]; then
        _cai_notice "Cannot check for updates (network error)"
        return 0
    fi

    # Parse token from response
    token=$(printf '%s' "$token_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    token = data.get('token', '')
    if token:
        print(token, end='')
    else:
        sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null) || {
        # Parse error - silently skip
        return 0
    }

    if [[ -z "$token" ]]; then
        # No token - silently skip (parse error)
        return 0
    fi

    # Get remote manifest list digest via HEAD request with status check
    local manifest_response manifest_status
    manifest_response=$(curl -s --max-time "$_CAI_REGISTRY_TIMEOUT" -I -w '\n%{http_code}' \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json" \
        "https://ghcr.io/v2/${image}/manifests/${tag}" 2>/dev/null) || {
        _cai_notice "Cannot check for updates (network error)"
        return 0
    }

    # Extract HTTP status code (last line)
    manifest_status="${manifest_response##*$'\n'}"

    # Check for auth errors
    if [[ "$manifest_status" == "401" ]] || [[ "$manifest_status" == "403" ]]; then
        _cai_notice "Cannot check for updates (authentication required)"
        return 0
    fi

    # Check for other HTTP errors
    if [[ "${manifest_status:0:1}" != "2" ]]; then
        _cai_notice "Cannot check for updates (network error)"
        return 0
    fi

    # Extract Docker-Content-Digest header (case-insensitive)
    remote_digest=$(printf '%s' "$manifest_response" | grep -i "docker-content-digest" | awk '{print $2}' | tr -d '\r\n')
    if [[ -z "$remote_digest" ]]; then
        # Parse error - silently skip
        return 0
    fi

    # Compare digests
    if [[ "$remote_digest" == "$local_digest" ]]; then
        # Up to date - cache the result with digest for future quick checks
        local cache_json checked_at
        checked_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        cache_json=$(_CAI_DIGEST="$local_digest" _CAI_VERSION="$local_version" _CAI_CREATED="$local_created" _CAI_CHECKED="$checked_at" python3 -c "
import os, json
result = {
    'digest': os.environ.get('_CAI_DIGEST', ''),
    'version': os.environ.get('_CAI_VERSION', ''),
    'created': os.environ.get('_CAI_CREATED', ''),
    'checked_at': os.environ.get('_CAI_CHECKED', '')
}
print(json.dumps(result))
" 2>/dev/null) || cache_json=""
        if [[ -n "$cache_json" ]]; then
            printf '%s' "$cache_json" | _cai_registry_cache_set "$image" "$tag" 2>/dev/null || true
        fi
        return 0
    fi

    # Digests differ - newer version available
    # Fetch remote metadata for version/created display
    local metadata
    if metadata=$(_cai_ghcr_image_metadata "$full_image" 2>/dev/null); then
        remote_version=$(printf '%s' "$metadata" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('version', ''), end='')
except:
    pass
" 2>/dev/null) || remote_version=""
        remote_created=$(printf '%s' "$metadata" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    created = data.get('created', '')
    print(created[:10] if created else '', end='')
except:
    pass
" 2>/dev/null) || remote_created=""

        # Cache the result with new digest
        local cache_json checked_at
        checked_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        cache_json=$(_CAI_DIGEST="$remote_digest" _CAI_VERSION="$remote_version" _CAI_CREATED="$remote_created" _CAI_CHECKED="$checked_at" python3 -c "
import os, json
result = {
    'digest': os.environ.get('_CAI_DIGEST', ''),
    'version': os.environ.get('_CAI_VERSION', ''),
    'created': os.environ.get('_CAI_CREATED', ''),
    'checked_at': os.environ.get('_CAI_CHECKED', '')
}
print(json.dumps(result))
" 2>/dev/null) || cache_json=""
        if [[ -n "$cache_json" ]]; then
            printf '%s' "$cache_json" | _cai_registry_cache_set "$image" "$tag" 2>/dev/null || true
        fi
    fi

    # Display the notice
    _cai_display_freshness_notice "$local_version" "$local_created" "$remote_version" "$remote_created"
    return 0
}

# Internal helper to display the freshness notice
# Args: $1=local_version, $2=local_created, $3=remote_version, $4=remote_created
_cai_display_freshness_notice() {
    local local_version="${1:-}"
    local local_created="${2:-}"
    local remote_version="${3:-}"
    local remote_created="${4:-}"

    _cai_notice "A newer ContainAI base image is available."

    # Format local info
    local local_info=""
    if [[ -n "$local_version" ]]; then
        local_info="$local_version"
        if [[ -n "$local_created" ]]; then
            local_info="$local_info ($local_created)"
        fi
    elif [[ -n "$local_created" ]]; then
        local_info="($local_created)"
    fi

    # Format remote info
    local remote_info=""
    if [[ -n "$remote_version" ]]; then
        remote_info="$remote_version"
        if [[ -n "$remote_created" ]]; then
            remote_info="$remote_info ($remote_created)"
        fi
    elif [[ -n "$remote_created" ]]; then
        remote_info="($remote_created)"
    fi

    # Display version comparison if available
    if [[ -n "$local_info" ]] || [[ -n "$remote_info" ]]; then
        if [[ -n "$local_info" ]]; then
            printf '%s\n' "         Local: $local_info" >&2
        fi
        if [[ -n "$remote_info" ]]; then
            printf '%s\n' "         Remote: $remote_info" >&2
        fi
        printf '\n' >&2
    fi

    printf '%s\n' "         Run 'cai --refresh' to update." >&2
    printf '\n' >&2
}

return 0
