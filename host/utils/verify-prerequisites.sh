#!/usr/bin/env bash
# Usage: ./host/utils/verify-prerequisites.sh
# Checks if the host environment meets the requirements for running CodingAgents.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
COMMON_FUNCTIONS="$REPO_ROOT/host/utils/common-functions.sh"
if [ ! -f "$COMMON_FUNCTIONS" ]; then
    echo "Unable to locate $COMMON_FUNCTIONS" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$COMMON_FUNCTIONS"
CODING_AGENTS_REPO_ROOT="$REPO_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Print functions
print_checking() {
    echo -e "${BLUE}⏳ Checking:${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

echo ""
echo "======================================"
echo "  CodingAgents Prerequisites Check"
echo "======================================"
echo ""

# Check Docker installation
print_checking "Container runtime (Docker)"
CONTAINER_CMD=""
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    print_success "Docker installed (version $DOCKER_VERSION)"
    CONTAINER_CMD="docker"
    
    # Check if Docker version is recent enough (20.10.0+)
    DOCKER_MAJOR=$(echo "$DOCKER_VERSION" | cut -d. -f1)
    DOCKER_MINOR=$(echo "$DOCKER_VERSION" | cut -d. -f2)
    
    if [ "$DOCKER_MAJOR" -lt 20 ] || ([ "$DOCKER_MAJOR" -eq 20 ] && [ "$DOCKER_MINOR" -lt 10 ]); then
        print_warning "Docker version $DOCKER_VERSION is old. Recommend 20.10.0+"
    fi
else
    print_error "Docker is not installed"
    echo "         Install Docker from: https://docs.docker.com/get-docker/"
fi

# Check if container runtime is running
if [ -n "$CONTAINER_CMD" ]; then
    print_checking "$CONTAINER_CMD daemon status"
    if $CONTAINER_CMD info > /dev/null 2>&1; then
        print_success "$CONTAINER_CMD daemon is running"
    else
        print_error "$CONTAINER_CMD daemon is not running"
        echo "         Start Docker Desktop or run: sudo systemctl start docker"
    fi
fi

# Check Git installation
print_checking "Git installation"
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version | grep -oP '\d+\.\d+\.\d+')
    print_success "Git installed (version $GIT_VERSION)"
else
    print_error "Git is not installed"
    echo "         Install from: https://git-scm.com/downloads"
fi

# Check Git configuration
print_checking "Git user.name configuration"
if GIT_NAME=$(git config --global user.name 2>/dev/null) && [ -n "$GIT_NAME" ]; then
    print_success "Git user.name configured: $GIT_NAME"
else
    print_error "Git user.name not configured"
    echo "         Run: git config --global user.name \"Your Name\""
fi

print_checking "Git user.email configuration"
if GIT_EMAIL=$(git config --global user.email 2>/dev/null) && [ -n "$GIT_EMAIL" ]; then
    print_success "Git user.email configured: $GIT_EMAIL"
else
    print_error "Git user.email not configured"
    echo "         Run: git config --global user.email \"your@email.com\""
fi

# Check socat installation (required for credential/GPG proxy)
print_checking "socat installation"
if command -v socat &> /dev/null; then
    SOCAT_VERSION=$(socat -V 2>&1 | head -1 | grep -oP 'socat version \K[\d.]+' || echo "installed")
    print_success "socat installed (version $SOCAT_VERSION)"
else
    print_error "socat is not installed (required for credential/GPG proxy)"
    if [ -f /etc/debian_version ]; then
        echo "         Install: sudo apt-get install socat"
    elif [ -f /etc/redhat-release ]; then
        echo "         Install: sudo yum install socat"
    elif [ "$(uname)" = "Darwin" ]; then
        echo "         Install: brew install socat"
    else
        echo "         Install socat using your package manager"
    fi
fi

# Check GitHub CLI installation (optional)
print_checking "GitHub CLI installation"
if command -v gh &> /dev/null; then
    GH_VERSION=$(gh --version | head -1 | grep -oP '\d+\.\d+\.\d+')
    print_success "GitHub CLI installed (version $GH_VERSION)"
else
    print_warning "GitHub CLI not found (optional for GitHub-specific commands)"
    echo "         Install from: https://cli.github.com/ if you plan to use gh-based flows"
fi

# Check GitHub CLI authentication (optional)
print_checking "GitHub CLI authentication"
if command -v gh &> /dev/null; then
    if gh auth status > /dev/null 2>&1; then
        GH_USER=$(gh api user --jq .login 2>/dev/null || echo "unknown")
        print_success "GitHub CLI authenticated (user: $GH_USER)"
    else
        print_warning "GitHub CLI is not authenticated (only required for gh workflows)"
        echo "         Run: gh auth login if you plan to use gh commands"
    fi
else
    print_warning "Skipping authentication check (GitHub CLI not installed)"
fi

# Check disk space
print_checking "Available disk space"
if command -v df &> /dev/null; then
    # Get available space in GB for current directory
    AVAILABLE_KB=$(df . | tail -1 | awk '{print $4}')
    AVAILABLE_GB=$(echo "scale=1; $AVAILABLE_KB / 1024 / 1024" | bc)
    
    if (( $(echo "$AVAILABLE_GB >= 5.0" | bc -l) )); then
        print_success "Disk space available: ${AVAILABLE_GB} GB"
    elif (( $(echo "$AVAILABLE_GB >= 3.0" | bc -l) )); then
        print_warning "Disk space available: ${AVAILABLE_GB} GB (recommend 5GB+)"
    else
        print_error "Disk space available: ${AVAILABLE_GB} GB (need at least 5GB)"
        echo "         Free up disk space or choose different location"
    fi
else
    print_warning "Cannot check disk space (df not available)"
fi

# Host/container security gates
print_checking "Host security enforcement (seccomp/AppArmor)"
if HOST_RESULT=$(verify_host_security_prereqs "$REPO_ROOT" 2>&1); then
    print_success "Host prerequisites satisfied"
else
    print_error "Host security prerequisites failed"
    echo "$HOST_RESULT" | sed 's/^/         /'
fi

print_checking "Container runtime security features"
if CONTAINER_RESULT=$(verify_container_security_support 2>&1); then
    print_success "Runtime advertises seccomp + AppArmor"
else
    print_error "Container security support missing"
    echo "$CONTAINER_RESULT" | sed 's/^/         /'
fi

# Check for optional tools
echo ""
echo "Optional Tools:"
echo "---------------"

# VS Code
print_checking "VS Code installation"
if command -v code &> /dev/null; then
    print_success "VS Code installed (for Dev Containers integration)"
else
    echo -e "${YELLOW}ℹ${NC}  VS Code not found (optional, but recommended)"
    echo "         Install from: https://code.visualstudio.com/"
fi

# jq (useful for MCP config)
print_checking "jq installation"
if command -v jq &> /dev/null; then
    JQ_VERSION=$(jq --version | grep -oP '\d+\.\d+' || echo "")
    print_success "jq installed (version $JQ_VERSION)"
else
    echo -e "${YELLOW}ℹ${NC}  jq not found (optional, useful for JSON processing)"
fi

# yq (useful for MCP config)
print_checking "yq installation"
if command -v yq &> /dev/null; then
    YQ_VERSION=$(yq --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "")
    print_success "yq installed (version $YQ_VERSION)"
else
    echo -e "${YELLOW}ℹ${NC}  yq not found (optional, useful for YAML processing)"
fi

# Summary
echo ""
echo "======================================"
echo "  Summary"
echo "======================================"
echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Failed:${NC}   $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✓ All prerequisites met!${NC} You're ready to use CodingAgents."
        echo ""
        echo "Next steps:"
        echo "  1. Get images:      docker pull ghcr.io/novotnyllc/coding-agents-copilot:latest"
        echo "  2. Install scripts: ./scripts/install.sh"
        echo "  3. First launch:    run-copilot"
        exit 0
    else
        echo -e "${YELLOW}⚠ Prerequisites met with warnings.${NC}"
        echo "You can proceed, but consider addressing warnings above."
        exit 0
    fi
else
    echo -e "${RED}✗ Some prerequisites are missing.${NC}"
    echo "Please address the errors above before using CodingAgents."
    echo ""
    echo "See docs/getting-started.md for detailed setup instructions."
    exit 1
fi
