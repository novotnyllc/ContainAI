#!/usr/bin/env bash
# shellcheck disable=SC2054,SC2162
# Build script for the coding agents containers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

print_usage() {
    cat <<'EOF'
Usage: build.sh [OPTIONS]

Build Coding Agents container images.

Options:
  -a, --agents LIST   Comma-separated list of targets to build.
                      Valid values: copilot, codex, claude, proxy, all
                      Default: all
    --from-source       Build images locally instead of pulling published tags
  -h, --help          Show this help message and exit

Examples:
    ./scripts/build/build.sh                       # Pull every published image
    ./scripts/build/build.sh --agents copilot      # Only Copilot image
    ./scripts/build/build.sh --from-source         # Force a local rebuild
    ./scripts/build/build.sh -a copilot,proxy      # Copilot + proxy
EOF
}

ALL_TARGETS=(copilot codex claude proxy)
DEFAULT_TARGETS=("${ALL_TARGETS[@]}")
RAW_AGENT_SELECTION=()
SECRET_SCANNER_BIN="${CODING_AGENTS_TRIVY_BIN:-}"
SECRET_SCAN_ARGS=(image --scanners secret --severity HIGH,CRITICAL --exit-code 1 --no-progress)
REGISTRY_OWNER="${CODING_AGENTS_IMAGE_OWNER:-novotnyllc}"
REGISTRY_PREFIX="ghcr.io/${REGISTRY_OWNER}"
BUILD_FROM_SOURCE=false

ensure_secret_scanner() {
    if [[ -n "$SECRET_SCANNER_BIN" ]]; then
        if command -v "$SECRET_SCANNER_BIN" >/dev/null 2>&1; then
            SECRET_SCANNER_BIN="$(command -v "$SECRET_SCANNER_BIN")"
            return
        fi
        echo "❌ CODING_AGENTS_TRIVY_BIN is set to '$SECRET_SCANNER_BIN' but it is not executable"
        exit 1
    fi
    if command -v trivy >/dev/null 2>&1; then
        SECRET_SCANNER_BIN="$(command -v trivy)"
        return
    fi
    cat <<'EOF'
❌ Trivy CLI is required for automatic secret scanning.
   Install it from https://aquasecurity.github.io/trivy or set CODING_AGENTS_TRIVY_BIN.
EOF
    exit 1
}

scan_image_for_secrets() {
    local image="$1"
    ensure_secret_scanner
    echo "🔍 Secret scanning $image for embedded credentials..."
    if ! "$SECRET_SCANNER_BIN" "${SECRET_SCAN_ARGS[@]}" "$image"; then
        echo "❌ Secret scan failed for $image"
        exit 1
    fi
}

pull_registry_image() {
    local target="$1"
    local remote=""
    local local_tag=""

    case "$target" in
        base)
            remote="${REGISTRY_PREFIX}/coding-agents-base:latest"
            local_tag="coding-agents-base:local"
            ;;
        all)
            remote="${REGISTRY_PREFIX}/coding-agents:latest"
            local_tag="coding-agents:local"
            ;;
        proxy)
            remote="${REGISTRY_PREFIX}/coding-agents-proxy:latest"
            local_tag="coding-agents-proxy:local"
            ;;
        *)
            remote="${REGISTRY_PREFIX}/coding-agents-${target}:latest"
            local_tag="coding-agents-${target}:local"
            ;;
    esac

    echo "📥 Pulling ${remote}"
    if docker pull "$remote"; then
        docker tag "$remote" "$local_tag" >/dev/null 2>&1 || true
        echo "   ✅ Tagged as $local_tag"
    else
        echo "❌ Failed to pull $remote"
        exit 1
    fi
}

add_agents_from_csv() {
    local raw="$1"
    IFS=',' read -ra PARTS <<< "$raw"
    for part in "${PARTS[@]}"; do
        local value
        value=$(echo "$part" | tr '[:upper:]' '[:lower:]' | xargs)
        [[ -n "$value" ]] && RAW_AGENT_SELECTION+=("$value")
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--agents)
            if [[ $# -lt 2 ]]; then
                echo "❌ Missing value for --agents"
                exit 1
            fi
            add_agents_from_csv "$2"
            shift 2
            ;;
        --agents=*)
            add_agents_from_csv "${1#*=}"
            shift
            ;;
        --from-source)
            BUILD_FROM_SOURCE=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo ""
            print_usage
            exit 1
            ;;
    esac
done

if [[ ${#RAW_AGENT_SELECTION[@]} -eq 0 ]]; then
    RAW_AGENT_SELECTION=(all)
fi

SELECTED_TARGETS=()
declare -A SEEN_TARGETS=()

normalize_targets() {
    for target in "${RAW_AGENT_SELECTION[@]}"; do
        case "$target" in
            all)
                SELECTED_TARGETS=("${DEFAULT_TARGETS[@]}")
                return
                ;;
            copilot|codex|claude|proxy)
                SEEN_TARGETS["$target"]=1
                ;;
            *)
                echo "❌ Invalid agent target: $target"
                echo "   Valid options: copilot, codex, claude, proxy, all"
                exit 1
                ;;
        esac
    done

    for candidate in "${DEFAULT_TARGETS[@]}"; do
        if [[ -n "${SEEN_TARGETS[$candidate]:-}" ]]; then
            SELECTED_TARGETS+=("$candidate")
        fi
    done
}

normalize_targets

AGENT_IMAGES=()
for candidate in copilot codex claude; do
    if printf '%s\n' "${SELECTED_TARGETS[@]}" | grep -qx "$candidate"; then
        AGENT_IMAGES+=("$candidate")
    fi
done

BUILD_PROXY=false
if printf '%s\n' "${SELECTED_TARGETS[@]}" | grep -qx "proxy"; then
    BUILD_PROXY=true
fi

NEEDS_AGENT_IMAGES=false
[[ ${#AGENT_IMAGES[@]} -gt 0 ]] && NEEDS_AGENT_IMAGES=true

cd "$PROJECT_DIR"

echo "🏗️  Building Coding Agents Containers"
echo "🎯 Targets: ${SELECTED_TARGETS[*]}"
echo ""

if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running!"
    echo "   Please start Docker and try again"
    exit 1
fi

if ! $BUILD_FROM_SOURCE; then
    PULL_TARGETS=()
    if $NEEDS_AGENT_IMAGES; then
        PULL_TARGETS+=(base all)
        PULL_TARGETS+=("${AGENT_IMAGES[@]}")
    fi
    if $BUILD_PROXY; then
        PULL_TARGETS+=(proxy)
    fi

    if [[ ${#PULL_TARGETS[@]} -eq 0 ]]; then
        echo "⚠️  No targets were selected. Nothing to pull."
        exit 0
    fi

    declare -A PULLED_TARGETS=()
    echo "📥 Syncing published images locally"
    for target in "${PULL_TARGETS[@]}"; do
        [[ -n "$target" ]] || continue
        if [[ -n "${PULLED_TARGETS[$target]:-}" ]]; then
            continue
        fi
        pull_registry_image "$target"
        PULLED_TARGETS["$target"]=1
    done

    echo ""
    echo "✅ Images are ready for launchers (local tags synced)."
    exit 0
fi

ensure_secret_scanner

BASE_IMAGE=""
BUILT_IMAGES=()

if $NEEDS_AGENT_IMAGES; then
    echo "Select base image source:"
    echo "1) Pull from GitHub Container Registry (recommended)"
    echo "2) Build locally (takes ~15 minutes)"
    read -p "Enter choice (1 or 2): " choice

    case $choice in
        1)
            read -p "Enter GitHub username or org for base image [novotnyllc]: " gh_username
            gh_username=${gh_username:-novotnyllc}
            BASE_IMAGE="ghcr.io/$gh_username/coding-agents-base:latest"
            echo ""
            echo "📥 Pulling base image: $BASE_IMAGE"
            if ! docker pull "$BASE_IMAGE"; then
                echo "❌ Failed to pull base image"
                echo "   Make sure the image exists and you're authenticated:"
                echo "   docker login ghcr.io -u $gh_username"
                echo ""
                echo "   Or build locally instead (option 2)"
                exit 1
            fi
            ;;
        2)
            echo ""
            echo "🔨 Building base image locally..."
            echo "   This will take approximately 15 minutes..."
            if ! docker build -f docker/base/Dockerfile -t coding-agents-base:local .; then
                echo "❌ Failed to build base image"
                exit 1
            fi
            scan_image_for_secrets "coding-agents-base:local"
            BASE_IMAGE="coding-agents-base:local"
            ;;
        *)
            echo "❌ Invalid choice: $choice"
            echo "   Please enter 1 or 2"
            exit 1
            ;;
    esac

    echo ""
    echo "🔨 Building all-agents image..."
    if ! docker build -f docker/agents/all/Dockerfile --build-arg BASE_IMAGE="$BASE_IMAGE" -t coding-agents:local .; then
        echo "❌ Failed to build all-agents image"
        exit 1
    fi
    scan_image_for_secrets "coding-agents:local"
    BUILT_IMAGES+=("coding-agents:local (all agents, interactive shell)")

    if [[ ${#AGENT_IMAGES[@]} -gt 0 ]]; then
        echo ""
        echo "🔨 Building selected agent images..."
        for agent in "${AGENT_IMAGES[@]}"; do
            if ! docker build -f "docker/agents/${agent}/Dockerfile" --build-arg BASE_IMAGE=coding-agents:local -t "coding-agents-${agent}:local" .; then
                echo "❌ Failed to build ${agent} image"
                exit 1
            fi
            scan_image_for_secrets "coding-agents-${agent}:local"
            case "$agent" in
                copilot)
                    BUILT_IMAGES+=("coding-agents-copilot:local (launches Copilot directly)")
                    ;;
                codex)
                    BUILT_IMAGES+=("coding-agents-codex:local (launches Codex directly)")
                    ;;
                claude)
                    BUILT_IMAGES+=("coding-agents-claude:local (launches Claude directly)")
                    ;;
            esac
        done
    fi
fi

if $BUILD_PROXY; then
    echo ""
    echo "🔨 Building network proxy image..."
    if ! docker build -f docker/proxy/Dockerfile -t coding-agents-proxy:local .; then
        echo "❌ Failed to build proxy image"
        exit 1
    fi
    scan_image_for_secrets "coding-agents-proxy:local"
    BUILT_IMAGES+=("coding-agents-proxy:local (Squid network proxy sidecar)")
fi

if [[ ${#BUILT_IMAGES[@]} -eq 0 ]]; then
    echo "⚠️  No build targets were selected. Nothing to do."
    exit 0
fi

echo ""
echo "✅ Build complete!"
echo ""
echo "Images created:"
for image in "${BUILT_IMAGES[@]}"; do
    echo "  • $image"
done

echo ""
echo "🚀 Launch an agent container with:"
echo "   ./host/launchers/run-agent copilot /path/to/your/repo"
echo "   # or use the shortcuts like ./host/launchers/run-copilot ."

echo ""
echo "   Or using docker-compose:"
echo "   cp .env.example .env"
echo "   # Edit .env with your repo path and WSL username"
echo "   docker-compose up -d                    # All agents"
echo "   docker-compose --profile copilot up -d  # Just Copilot"
echo "   docker-compose --profile codex up -d    # Just Codex"
echo "   docker-compose --profile claude up -d   # Just Claude"
