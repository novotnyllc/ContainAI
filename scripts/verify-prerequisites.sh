#!/usr/bin/env bash
# Verify that all prerequisites for CodingAgents are installed and configured
# Usage: ./scripts/verify-prerequisites.sh

set -euo pipefail

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

# Check Docker or Podman installation
print_checking "Container runtime (Docker or Podman)"
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
elif command -v podman &> /dev/null; then
    PODMAN_VERSION=$(podman --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    print_success "Podman installed (version $PODMAN_VERSION)"
    CONTAINER_CMD="podman"
    
    # Check if Podman version is recent enough (3.0.0+)
    PODMAN_MAJOR=$(echo "$PODMAN_VERSION" | cut -d. -f1)
    
    if [ "$PODMAN_MAJOR" -lt 3 ]; then
        print_warning "Podman version $PODMAN_VERSION is old. Recommend 3.0.0+"
    fi
else
    print_error "Neither Docker nor Podman is installed"
    echo "         Install Docker from: https://docs.docker.com/get-docker/"
    echo "         Or Podman from: https://podman.io/getting-started/installation"
fi

# Check if container runtime is running
if [ -n "$CONTAINER_CMD" ]; then
    print_checking "$CONTAINER_CMD daemon status"
    if $CONTAINER_CMD info > /dev/null 2>&1; then
        print_success "$CONTAINER_CMD daemon is running"
    else
        print_error "$CONTAINER_CMD daemon is not running"
        if [ "$CONTAINER_CMD" = "docker" ]; then
            echo "         Start Docker Desktop or run: sudo systemctl start docker"
        else
            echo "         Start Podman service: sudo systemctl start podman"
        fi
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

# Check GitHub CLI installation
print_checking "GitHub CLI installation"
if command -v gh &> /dev/null; then
    GH_VERSION=$(gh --version | head -1 | grep -oP '\d+\.\d+\.\d+')
    print_success "GitHub CLI installed (version $GH_VERSION)"
else
    print_error "GitHub CLI is not installed"
    echo "         Install from: https://cli.github.com/"
fi

# Check GitHub CLI authentication
print_checking "GitHub CLI authentication"
if command -v gh &> /dev/null; then
    if gh auth status > /dev/null 2>&1; then
        GH_USER=$(gh api user --jq .login 2>/dev/null || echo "unknown")
        print_success "GitHub CLI authenticated (user: $GH_USER)"
    else
        print_error "GitHub CLI is not authenticated"
        echo "         Run: gh auth login"
    fi
else
    print_error "Cannot check authentication (gh not installed)"
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

# Check WSL (Windows only)
if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    print_checking "WSL version"
    if command -v wsl.exe &> /dev/null; then
        WSL_VERSION=$(wsl.exe --version 2>/dev/null | grep "WSL version" | grep -oP '\d+\.\d+\.\d+' || echo "2.x")
        print_success "Running in WSL $WSL_VERSION"
    else
        print_success "Running in WSL"
    fi
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
