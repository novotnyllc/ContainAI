#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Build ContainAI Docker images (layered build)
# ==============================================================================
# Usage: ./build.sh [options] [docker buildx options]
#   --dotnet-channel CHANNEL  .NET SDK channel (default: 10.0)
#   --layer LAYER             Build only specific layer (base|sdks|agents|all)
#   --image-prefix PREFIX     Image name prefix (default: ghcr.io/novotnyllc/containai)
#   --version VERSION         Version for OCI labels (default: from NBGV or "unknown")
#   --platforms PLATFORMS     Build with buildx for platforms (e.g., linux/amd64,linux/arm64)
#   --builder NAME            Use a specific buildx builder
#   --build-setup             Configure buildx builder + binfmt if required
#   --push                    Push images (buildx only)
#   --load                    Load image into local docker (buildx only; single-platform)
#   --context NAME            Docker context (default: containai-docker if present)
#   --help                    Show this help
#
# Defaults: docker build; buildx is used only when requested
#
# Build order: base -> sdks -> agents -> containai (alias)
#
# Examples:
#   ./build.sh                          # Build all layers
#   ./build.sh --layer base             # Build only base layer
#   ./build.sh --dotnet-channel lts     # Use latest LTS for .NET
#   ./build.sh --image-prefix ghcr.io/org/containai
#   ./build.sh --no-cache               # Pass option to docker build/buildx
#   ./build.sh --platforms linux/amd64  # Cross-build single platform with buildx
#   ./build.sh --platforms linux/amd64,linux/arm64 --push
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATE_TAG="$(date +%Y-%m-%d)"

# Defaults
DOTNET_CHANNEL="10.0"
BUILD_LAYER="all"
IMAGE_PREFIX="ghcr.io/novotnyllc/containai"
PLATFORMS=""
BUILDX_BUILDER=""
BUILDX_PUSH=0
BUILDX_LOAD=0
USE_BUILDX=0
BUILD_SETUP=0
BUILDX_REQUESTED=0
HAS_OUTPUT=0
HAS_REGISTRY_OUTPUT=0
DOCKER_CONTEXT=""
DOCKER_CMD=(docker)
BUILD_VERSION=""  # Set via --version or NBGV_SemVer2 env var

# Parse options
DOCKER_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dotnet-channel)
            if [[ -z "${2-}" ]]; then
                echo "ERROR: --dotnet-channel requires a value" >&2
                exit 1
            fi
            DOTNET_CHANNEL="$2"
            shift 2
            ;;
        --layer)
            if [[ -z "${2-}" ]]; then
                echo "ERROR: --layer requires a value (base|sdks|agents|all)" >&2
                exit 1
            fi
            BUILD_LAYER="$2"
            shift 2
            ;;
        --image-prefix)
            if [[ -z "${2-}" ]]; then
                echo "ERROR: --image-prefix requires a value" >&2
                exit 1
            fi
            IMAGE_PREFIX="$2"
            shift 2
            ;;
        --platforms|--platform)
            if [[ -z "${2-}" ]]; then
                echo "ERROR: --platforms requires a value (e.g., linux/amd64,linux/arm64)" >&2
                exit 1
            fi
            PLATFORMS="$2"
            BUILDX_REQUESTED=1
            shift 2
            ;;
        --builder)
            if [[ -z "${2-}" ]]; then
                echo "ERROR: --builder requires a value" >&2
                exit 1
            fi
            BUILDX_BUILDER="$2"
            BUILDX_REQUESTED=1
            shift 2
            ;;
        --build-setup)
            BUILD_SETUP=1
            BUILDX_REQUESTED=1
            shift
            ;;
        --push)
            BUILDX_PUSH=1
            BUILDX_REQUESTED=1
            shift
            ;;
        --load)
            BUILDX_LOAD=1
            BUILDX_REQUESTED=1
            shift
            ;;
        --help | -h)
            sed -n '4,34p' "$0" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        --platforms=*|--platform=*)
            PLATFORMS="${1#*=}"
            if [[ -z "$PLATFORMS" ]]; then
                echo "ERROR: --platforms requires a value (e.g., linux/amd64,linux/arm64)" >&2
                exit 1
            fi
            BUILDX_REQUESTED=1
            shift
            ;;
        --builder=*)
            BUILDX_BUILDER="${1#*=}"
            if [[ -z "$BUILDX_BUILDER" ]]; then
                echo "ERROR: --builder requires a value" >&2
                exit 1
            fi
            BUILDX_REQUESTED=1
            shift
            ;;
        --context)
            if [[ -z "${2-}" ]]; then
                echo "ERROR: --context requires a value" >&2
                exit 1
            fi
            DOCKER_CONTEXT="$2"
            shift 2
            ;;
        --context=*)
            DOCKER_CONTEXT="${1#*=}"
            if [[ -z "$DOCKER_CONTEXT" ]]; then
                echo "ERROR: --context requires a value" >&2
                exit 1
            fi
            shift
            ;;
        --image-prefix=*)
            IMAGE_PREFIX="${1#*=}"
            if [[ -z "$IMAGE_PREFIX" ]]; then
                echo "ERROR: --image-prefix requires a value" >&2
                exit 1
            fi
            shift
            ;;
        --version)
            if [[ -z "${2-}" ]]; then
                echo "ERROR: --version requires a value" >&2
                exit 1
            fi
            BUILD_VERSION="$2"
            shift 2
            ;;
        --version=*)
            BUILD_VERSION="${1#*=}"
            if [[ -z "$BUILD_VERSION" ]]; then
                echo "ERROR: --version requires a value" >&2
                exit 1
            fi
            shift
            ;;
        *)
            DOCKER_ARGS+=("$1")
            shift
            ;;
    esac
done

# Enable BuildKit
export DOCKER_BUILDKIT=1

# Buildx helpers
detect_host_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)
            printf '%s' "amd64"
            ;;
        aarch64|arm64)
            printf '%s' "arm64"
            ;;
        *)
            printf 'ERROR: Unsupported host architecture: %s\n' "$arch" >&2
            return 1
            ;;
    esac
}

normalize_image_prefix() {
    local prefix="$1"
    prefix="${prefix%/}"
    if [[ -z "$prefix" ]]; then
        printf 'ERROR: --image-prefix cannot be empty\n' >&2
        return 1
    fi
    if [[ "$prefix" =~ [[:space:]] ]]; then
        printf 'ERROR: --image-prefix must not contain whitespace\n' >&2
        return 1
    fi
    printf '%s' "$prefix"
}

normalize_platforms() {
    local raw="$1"
    local out=""
    local p
    local parts=()
    IFS=',' read -r -a parts <<< "$raw"
    for p in "${parts[@]}"; do
        p="${p//[[:space:]]/}"
        if [[ -z "$p" ]]; then
            continue
        fi
        case "$p" in
            linux/amd64|linux/arm64)
                ;;
            *)
                printf 'ERROR: Unsupported platform "%s". Supported: linux/amd64, linux/arm64.\n' "$p" >&2
                return 1
                ;;
        esac
        if [[ -n "$out" ]]; then
            out+=",${p}"
        else
            out="$p"
        fi
    done
    if [[ -z "$out" ]]; then
        printf 'ERROR: --platforms must include at least one platform.\n' >&2
        return 1
    fi
    printf '%s' "$out"
}

buildx_inspect() {
    local builder="$1"
    if [[ -n "$builder" ]]; then
        "${DOCKER_CMD[@]}" buildx inspect "$builder" --bootstrap 2>/dev/null
    else
        "${DOCKER_CMD[@]}" buildx inspect --bootstrap 2>/dev/null
    fi
}

buildx_driver() {
    local builder="$1"
    local output
    output="$(buildx_inspect "$builder")" || return 1
    printf '%s\n' "$output" | awk -F': ' '/Driver:/ {print $2; exit}'
}

buildx_platforms() {
    local builder="$1"
    local output
    output="$(buildx_inspect "$builder")" || return 1
    printf '%s\n' "$output" | awk -F': ' '/Platforms:/ {print $2; exit}'
}

buildx_setup() {
    local builder="$1"
    local driver

    if ! "${DOCKER_CMD[@]}" buildx inspect "$builder" >/dev/null 2>&1; then
        printf 'Creating buildx builder "%s"...\n' "$builder"
        "${DOCKER_CMD[@]}" buildx create --name "$builder" --driver docker-container --use >/dev/null
    else
        "${DOCKER_CMD[@]}" buildx use "$builder" >/dev/null
    fi

    driver="$(buildx_driver "$builder")" || return 1
    if [[ "$driver" != "docker-container" ]]; then
        printf 'ERROR: buildx builder "%s" uses driver "%s"; expected "docker-container".\n' "$builder" "$driver" >&2
        return 1
    fi

    printf 'Ensuring binfmt is installed for amd64 and arm64...\n'
    "${DOCKER_CMD[@]}" run --privileged --rm tonistiigi/binfmt --install amd64,arm64 >/dev/null
    "${DOCKER_CMD[@]}" buildx inspect "$builder" --bootstrap >/dev/null
}

buildx_check_platforms() {
    local builder="$1"
    local required="$2"
    local available
    local p
    local parts=()

    available="$(buildx_platforms "$builder")" || return 1
    available="${available//[[:space:]]/}"
    IFS=',' read -r -a parts <<< "$required"
    for p in "${parts[@]}"; do
        if [[ ",${available}," != *",${p},"* ]]; then
            printf 'Missing platform in buildx builder: %s\n' "$p" >&2
            return 1
        fi
    done
    return 0
}

# Buildx validation/setup
IMAGE_PREFIX="$(normalize_image_prefix "$IMAGE_PREFIX")" || exit 1
IMAGE_BASE="${IMAGE_PREFIX}/base"
IMAGE_SDKS="${IMAGE_PREFIX}/sdks"
IMAGE_AGENTS="${IMAGE_PREFIX}/agents"
IMAGE_MAIN="${IMAGE_PREFIX}"

# Use buildx only when requested (multi-arch/push/load/output/builder/build-setup)
if [[ "$BUILDX_REQUESTED" -eq 1 ]]; then
    USE_BUILDX=1
fi

# Docker availability and context selection (applies to buildx and docker build)
if ! command -v docker >/dev/null 2>&1; then
    printf 'ERROR: docker is not installed or not in PATH.\n' >&2
    exit 1
fi
if [[ -n "$DOCKER_CONTEXT" ]]; then
    if ! docker context inspect "$DOCKER_CONTEXT" >/dev/null 2>&1; then
        printf 'ERROR: docker context "%s" not found.\n' "$DOCKER_CONTEXT" >&2
        exit 1
    fi
    DOCKER_CMD=(docker --context "$DOCKER_CONTEXT")
else
    if docker context inspect containai-docker >/dev/null 2>&1; then
        DOCKER_CMD=(docker --context containai-docker)
    fi
fi

if [[ "$USE_BUILDX" -eq 1 ]]; then
    HAS_OUTPUT=0
    HAS_REGISTRY_OUTPUT=0
    if [[ " ${DOCKER_ARGS[*]-} " =~ [[:space:]]--output([[:space:]]|=) ]]; then
        HAS_OUTPUT=1
        # Check if output type is registry (supports --output=type=registry and --output type=registry)
        if [[ " ${DOCKER_ARGS[*]-} " =~ type=registry ]]; then
            HAS_REGISTRY_OUTPUT=1
        fi
    fi

    if ! "${DOCKER_CMD[@]}" buildx version >/dev/null 2>&1; then
        if [[ "$BUILDX_REQUESTED" -eq 1 ]]; then
            printf 'ERROR: docker buildx is not available. Install the buildx plugin.\n' >&2
        else
            printf 'ERROR: docker buildx is not available. Install the buildx plugin to match CI builds.\n' >&2
        fi
        exit 1
    fi
    if [[ -z "$PLATFORMS" ]]; then
        PLATFORMS="linux/$(detect_host_arch)"
    else
        PLATFORMS="$(normalize_platforms "$PLATFORMS")"
    fi
    if [[ "$BUILDX_PUSH" -eq 1 && "$BUILDX_LOAD" -eq 1 ]]; then
        printf 'ERROR: --push and --load cannot be used together\n' >&2
        exit 1
    fi
    if [[ "$PLATFORMS" == *","* && "$BUILDX_LOAD" -eq 1 ]]; then
        printf 'ERROR: --load only supports a single platform\n' >&2
        exit 1
    fi
    if [[ "$PLATFORMS" == *","* && "$BUILDX_PUSH" -eq 0 && "$HAS_OUTPUT" -eq 0 ]]; then
        printf 'ERROR: multi-platform buildx requires --push or --output\n' >&2
        exit 1
    fi
    if [[ "$BUILDX_PUSH" -eq 0 && "$HAS_OUTPUT" -eq 0 && "$BUILDX_LOAD" -eq 0 ]]; then
        if [[ "$PLATFORMS" != *","* ]]; then
            BUILDX_LOAD=1
        fi
    fi

    if ! buildx_check_platforms "$BUILDX_BUILDER" "$PLATFORMS"; then
        if [[ "$BUILD_SETUP" -eq 1 ]]; then
            if [[ -z "$BUILDX_BUILDER" ]]; then
                BUILDX_BUILDER="containai"
            fi
            buildx_setup "$BUILDX_BUILDER" || exit 1
            buildx_check_platforms "$BUILDX_BUILDER" "$PLATFORMS" || exit 1
        else
            printf 'ERROR: buildx builder does not support required platforms: %s\n' "$PLATFORMS" >&2
            printf 'Hint: re-run with --build-setup to configure buildx + binfmt.\n' >&2
            exit 1
        fi
    fi
fi

# Generate OCI label values
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

# Determine VERSION for OCI labels
# Priority: --version flag > NBGV_SemVer2 env var > dotnet nbgv > "unknown"
if [[ -z "$BUILD_VERSION" ]]; then
    if [[ -n "${NBGV_SemVer2:-}" ]]; then
        BUILD_VERSION="$NBGV_SemVer2"
    elif command -v dotnet >/dev/null 2>&1 && [[ -f "$SCRIPT_DIR/../version.json" ]]; then
        BUILD_VERSION="$(dotnet nbgv get-version -v SemVer2 2>/dev/null || echo 'unknown')"
    else
        BUILD_VERSION="unknown"
    fi
fi

# Helper to check if a local image exists in current Docker context
# Returns 0 if exists, 1 otherwise
local_image_exists() {
    local image="$1"
    "${DOCKER_CMD[@]}" image inspect "$image" >/dev/null 2>&1
}

# ==============================================================================
# Run manifest-driven generators for full/all layer builds
# ==============================================================================
generate_container_files() {
    local manifest="${SCRIPT_DIR}/sync-manifest.toml"
    local gen_dir="${SCRIPT_DIR}/container/generated"
    local scripts_dir="${SCRIPT_DIR}/scripts"

    if [[ ! -f "$manifest" ]]; then
        printf 'ERROR: sync-manifest.toml not found: %s\n' "$manifest" >&2
        return 1
    fi

    echo ""
    echo "=== Generating container files from manifest ==="
    echo ""

    mkdir -p "$gen_dir"

    # Generate symlinks shell script (COPY'd and RUN in Dockerfile)
    if ! "${scripts_dir}/gen-dockerfile-symlinks.sh" "$manifest" "${gen_dir}/symlinks.sh"; then
        printf 'ERROR: Failed to generate symlinks.sh\n' >&2
        return 1
    fi

    # Generate init-dirs script
    if ! "${scripts_dir}/gen-init-dirs.sh" "$manifest" "${gen_dir}/init-dirs.sh"; then
        printf 'ERROR: Failed to generate init-dirs.sh\n' >&2
        return 1
    fi

    # Generate link-spec.json
    if ! "${scripts_dir}/gen-container-link-spec.sh" "$manifest" "${gen_dir}/link-spec.json"; then
        printf 'ERROR: Failed to generate link-spec.json\n' >&2
        return 1
    fi

    # Copy link-repair.sh to generated dir so it gets included in build context
    cp "${SCRIPT_DIR}/container/link-repair.sh" "${gen_dir}/link-repair.sh"

    # Verify generated files are newer than manifest (staleness check)
    local manifest_mtime gen_file_mtime
    manifest_mtime=$(stat -c %Y "$manifest" 2>/dev/null || stat -f %m "$manifest" 2>/dev/null)
    for gen_file in "${gen_dir}/symlinks.sh" "${gen_dir}/init-dirs.sh" "${gen_dir}/link-spec.json"; do
        gen_file_mtime=$(stat -c %Y "$gen_file" 2>/dev/null || stat -f %m "$gen_file" 2>/dev/null)
        if [[ "$gen_file_mtime" -lt "$manifest_mtime" ]]; then
            printf 'ERROR: Generated file is stale: %s\n' "$gen_file" >&2
            return 1
        fi
    done

    echo "  Generated files:"
    ls -la "${gen_dir}"
    echo ""
}

# Build function for a single layer
build_layer() {
    local name="$1"
    local dockerfile="$2"
    local extra_args=("${@:3}")
    local repo="${IMAGE_PREFIX}/${name}"
    local build_cmd=("${DOCKER_CMD[@]}" build)

    echo ""
    echo "=== Building containai/${name} ==="
    echo ""

    if [[ "$USE_BUILDX" -eq 1 ]]; then
        build_cmd=("${DOCKER_CMD[@]}" buildx build)
        if [[ -n "$BUILDX_BUILDER" ]]; then
            build_cmd+=(--builder "$BUILDX_BUILDER")
        fi
        if [[ -n "$PLATFORMS" ]]; then
            build_cmd+=(--platform "$PLATFORMS")
        fi
        if [[ "$BUILDX_PUSH" -eq 1 ]]; then
            build_cmd+=(--push)
        elif [[ "$BUILDX_LOAD" -eq 1 ]]; then
            build_cmd+=(--load)
        fi
    fi

    "${build_cmd[@]}" \
        -t "${repo}:latest" \
        -t "${repo}:${DATE_TAG}" \
        --build-arg BUILD_DATE="$BUILD_DATE" \
        --build-arg VCS_REF="$VCS_REF" \
        --build-arg VERSION="$BUILD_VERSION" \
        ${extra_args[@]+"${extra_args[@]}"} \
        ${DOCKER_ARGS[@]+"${DOCKER_ARGS[@]}"} \
        -f "${SCRIPT_DIR}/container/${dockerfile}" \
        "$SCRIPT_DIR"

    echo "  Tagged: ${repo}:latest, ${repo}:${DATE_TAG}"
}

# Build layers based on selection
case "$BUILD_LAYER" in
    base)
        build_layer "base" "Dockerfile.base"
        ;;
    sdks)
        sdks_args=(--build-arg DOTNET_CHANNEL="$DOTNET_CHANNEL")
        if local_image_exists "${IMAGE_BASE}:latest"; then
            printf '[INFO] Using local base image: %s\n' "${IMAGE_BASE}:latest"
            sdks_args+=(--build-arg BASE_IMAGE="${IMAGE_BASE}:latest")
        else
            printf '[INFO] No local base image found, using Dockerfile default\n'
        fi
        build_layer "sdks" "Dockerfile.sdks" "${sdks_args[@]}"
        ;;
    agents)
        generate_container_files || exit 1
        agents_args=()
        if local_image_exists "${IMAGE_SDKS}:latest"; then
            printf '[INFO] Using local sdks image: %s\n' "${IMAGE_SDKS}:latest"
            agents_args+=(--build-arg SDKS_IMAGE="${IMAGE_SDKS}:latest")
        else
            printf '[INFO] No local sdks image found, using Dockerfile default\n'
        fi
        build_layer "agents" "Dockerfile.agents" "${agents_args[@]}"
        ;;
    full)
        echo "ERROR: Layer 'full' has been renamed to 'agents'. Use: --layer agents" >&2
        exit 1
        ;;
    all)
        echo "Building all ContainAI layers..."
        echo "  .NET channel: $DOTNET_CHANNEL"

        # Generate container files from manifest before agents layer
        generate_container_files || exit 1

        # Build in dependency order
        build_layer "base" "Dockerfile.base"

        # sdks layer: pass BASE_IMAGE build-arg
        # When using --push or --output=type=registry, images go to registry and are
        # available for subsequent builds. For local builds (--load or default), check
        # if local image exists. Non-registry outputs (local, tar) can't be chained.
        all_sdks_args=(--build-arg DOTNET_CHANNEL="$DOTNET_CHANNEL")
        if [[ "$BUILDX_PUSH" -eq 1 ]] || [[ "$HAS_REGISTRY_OUTPUT" -eq 1 ]]; then
            printf '[INFO] Using pushed base image: %s\n' "${IMAGE_BASE}:latest"
            all_sdks_args+=(--build-arg BASE_IMAGE="${IMAGE_BASE}:latest")
        elif local_image_exists "${IMAGE_BASE}:latest"; then
            printf '[INFO] Using local base image: %s\n' "${IMAGE_BASE}:latest"
            all_sdks_args+=(--build-arg BASE_IMAGE="${IMAGE_BASE}:latest")
        else
            printf '[INFO] No local base image found, using Dockerfile default\n'
        fi
        build_layer "sdks" "Dockerfile.sdks" "${all_sdks_args[@]}"

        # agents layer: pass SDKS_IMAGE build-arg
        all_agents_args=()
        if [[ "$BUILDX_PUSH" -eq 1 ]] || [[ "$HAS_REGISTRY_OUTPUT" -eq 1 ]]; then
            printf '[INFO] Using pushed sdks image: %s\n' "${IMAGE_SDKS}:latest"
            all_agents_args+=(--build-arg SDKS_IMAGE="${IMAGE_SDKS}:latest")
        elif local_image_exists "${IMAGE_SDKS}:latest"; then
            printf '[INFO] Using local sdks image: %s\n' "${IMAGE_SDKS}:latest"
            all_agents_args+=(--build-arg SDKS_IMAGE="${IMAGE_SDKS}:latest")
        else
            printf '[INFO] No local sdks image found, using Dockerfile default\n'
        fi
        build_layer "agents" "Dockerfile.agents" "${all_agents_args[@]}"

        # Build final alias image
        echo ""
        echo "=== Building containai (final image) ==="
        echo ""
        final_cmd=("${DOCKER_CMD[@]}" build)
        if [[ "$USE_BUILDX" -eq 1 ]]; then
            final_cmd=("${DOCKER_CMD[@]}" buildx build)
            if [[ -n "$BUILDX_BUILDER" ]]; then
                final_cmd+=(--builder "$BUILDX_BUILDER")
            fi
            if [[ -n "$PLATFORMS" ]]; then
                final_cmd+=(--platform "$PLATFORMS")
            fi
            if [[ "$BUILDX_PUSH" -eq 1 ]]; then
                final_cmd+=(--push)
            elif [[ "$BUILDX_LOAD" -eq 1 ]]; then
                final_cmd+=(--load)
            fi
        fi
        # Pass AGENTS_IMAGE build-arg for final image
        final_args=()
        if [[ "$BUILDX_PUSH" -eq 1 ]] || [[ "$HAS_REGISTRY_OUTPUT" -eq 1 ]]; then
            printf '[INFO] Using pushed agents image: %s\n' "${IMAGE_AGENTS}:latest"
            final_args+=(--build-arg AGENTS_IMAGE="${IMAGE_AGENTS}:latest")
        elif local_image_exists "${IMAGE_AGENTS}:latest"; then
            printf '[INFO] Using local agents image: %s\n' "${IMAGE_AGENTS}:latest"
            final_args+=(--build-arg AGENTS_IMAGE="${IMAGE_AGENTS}:latest")
        else
            printf '[INFO] No local agents image found, using Dockerfile default\n'
        fi
        "${final_cmd[@]}" \
            -t "${IMAGE_MAIN}:latest" \
            -t "${IMAGE_MAIN}:${DATE_TAG}" \
            --build-arg BUILD_DATE="$BUILD_DATE" \
            --build-arg VCS_REF="$VCS_REF" \
            --build-arg VERSION="$BUILD_VERSION" \
            "${final_args[@]}" \
            ${DOCKER_ARGS[@]+"${DOCKER_ARGS[@]}"} \
            -f "${SCRIPT_DIR}/container/Dockerfile" \
            "$SCRIPT_DIR"
        echo "  Tagged: ${IMAGE_MAIN}:latest, ${IMAGE_MAIN}:${DATE_TAG}"
        ;;
    *)
        echo "ERROR: Unknown layer '$BUILD_LAYER'. Use: base, sdks, agents, or all" >&2
        exit 1
        ;;
esac

echo ""
echo "Build complete!"
echo ""
if [[ "$USE_BUILDX" -eq 1 && "$BUILDX_LOAD" -eq 0 && ( "$BUILDX_PUSH" -eq 1 || "$HAS_OUTPUT" -eq 1 ) ]]; then
    printf 'Images were pushed or exported; no local images loaded.\n'
else
    "${DOCKER_CMD[@]}" images "${IMAGE_PREFIX}*" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" | head -20
fi
