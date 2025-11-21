#!/usr/bin/env bash
# Dev-only helper to build Coding Agents dev images (namespaced to avoid prod overlap).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$PROJECT_ROOT/docker-compose.yml}"
SELECTED_AGENTS=("copilot" "codex" "claude")

print_help() {
    cat <<'EOF'
Usage: scripts/build/build-dev.sh [options]

Builds dev-scoped images (coding-agents-dev-*) tagged as :devlocal using docker compose.

Options:
  --agents LIST    Comma-separated agents (copilot,codex,claude,all). Default: all (proxy always built)
  -h, --help       Show this help message
EOF
}

add_agents_from_csv() {
    local raw="$1"
    IFS=',' read -ra parts <<< "$raw"
    SELECTED_AGENTS=()
    for part in "${parts[@]}"; do
        local value
        value=$(echo "$part" | tr '[:upper:]' '[:lower:]' | xargs)
        case "$value" in
            all|"")
                SELECTED_AGENTS=("copilot" "codex" "claude")
                return
                ;;
            copilot|codex|claude)
                SELECTED_AGENTS+=("$value")
                ;;
            *)
                echo "❌ Invalid agent: $value" >&2
                exit 1
                ;;
        esac
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agents)
            add_agents_from_csv "${2:-}"
            shift 2
            ;;
        --agents=*)
            add_agents_from_csv "${1#*=}"
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

if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker CLI not available. Install Docker or Docker Desktop." >&2
    exit 1
fi
if ! command -v docker compose >/dev/null 2>&1; then
    echo "❌ docker compose is required to build dev images." >&2
    exit 1
fi

select_services() {
    local services=("base" "agents" "proxy")
    for agent in "${SELECTED_AGENTS[@]}"; do
        services+=("$agent")
    done
    echo "${services[@]}"
}

mapfile -t services < <(select_services)
echo "🏗️  Building dev images (${services[*]}) via $COMPOSE_FILE"
docker compose -f "$COMPOSE_FILE" build "${services[@]}"
echo "✅ Dev images built and tagged as :devlocal (coding-agents-dev-*)."
