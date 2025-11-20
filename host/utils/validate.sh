#!/usr/bin/env bash
# Validation script to check if the container is properly configured

set -euo pipefail

echo "🔍 Validating Coding Agents Container Setup..."
echo ""

ERRORS=0
WARNINGS=0

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

# Check workspace
echo "Checking workspace..."
if [ -d "/workspace" ]; then
    check_pass "Workspace directory exists"
    cd /workspace
    
    if [ -d ".git" ]; then
        check_pass "Git repository detected"
    else
        check_warn "Not a git repository"
    fi
else
    check_fail "Workspace directory not found"
fi
echo ""

# Check git configuration
echo "Checking git configuration..."
if command -v git &> /dev/null; then
    check_pass "Git is installed"
    
    if git config user.name &> /dev/null; then
        check_pass "Git user.name configured: $(git config user.name)"
    else
        check_warn "Git user.name not configured"
    fi
    
    if git config user.email &> /dev/null; then
        check_pass "Git user.email configured: $(git config user.email)"
    else
        check_warn "Git user.email not configured"
    fi
else
    check_fail "Git is not installed"
fi
echo ""

# Check GitHub CLI
echo "Checking GitHub CLI..."
if command -v gh &> /dev/null; then
    check_pass "GitHub CLI is installed"
    
    if gh auth status &> /dev/null; then
        check_pass "GitHub CLI is authenticated"
    else
        check_warn "GitHub CLI is not authenticated"
    fi
else
    check_fail "GitHub CLI is not installed"
fi
echo ""

# Check GitHub Copilot
echo "Checking GitHub Copilot..."
if command -v github-copilot-cli &> /dev/null; then
    check_pass "GitHub Copilot CLI is installed"
else
    check_warn "GitHub Copilot CLI is not installed"
fi
echo ""

# Check Node.js
echo "Checking Node.js..."
if command -v node &> /dev/null; then
    check_pass "Node.js is installed: $(node --version)"
else
    check_fail "Node.js is not installed"
fi

if command -v npm &> /dev/null; then
    check_pass "npm is installed: $(npm --version)"
else
    check_fail "npm is not installed"
fi
echo ""

# Check Python
echo "Checking Python..."
if command -v python3 &> /dev/null; then
    check_pass "Python is installed: $(python3 --version)"
else
    check_fail "Python is not installed"
fi

if command -v pip3 &> /dev/null; then
    check_pass "pip is installed: $(pip3 --version)"
else
    check_fail "pip is not installed"
fi
echo ""

# Check .NET
echo "Checking .NET SDK..."
if command -v dotnet &> /dev/null; then
    check_pass ".NET SDK is installed: $(dotnet --version)"
else
    check_warn ".NET SDK is not installed (optional)"
fi
echo ""

# Check MCP configuration
echo "Checking MCP configuration..."
CONFIG_FILE="/home/agentuser/.config/coding-agents/config.toml"
if [ -f "$CONFIG_FILE" ]; then
    check_pass "MCP config file exists"
else
    check_fail "MCP config file not found"
fi
echo ""

# Check environment variables
echo "Checking environment variables..."
if [ ! -z "$GITHUB_TOKEN" ]; then
    check_pass "GITHUB_TOKEN is set"
else
    check_warn "GITHUB_TOKEN is not set (GitHub MCP may not work)"
fi

if [ ! -z "$CONTEXT7_API_KEY" ]; then
    check_pass "CONTEXT7_API_KEY is set"
else
    check_warn "CONTEXT7_API_KEY is not set (Context7 MCP may not work)"
fi
echo ""

# Check Playwright
echo "Checking Playwright..."
if npx playwright --version &> /dev/null; then
    check_pass "Playwright is installed: $(npx playwright --version)"
else
    check_warn "Playwright may not be properly installed"
fi
echo ""

# Check uvx (for Serena)
echo "Checking uvx (for Serena MCP)..."
if command -v uvx &> /dev/null; then
    check_pass "uvx is installed"
else
    check_warn "uvx is not installed (Serena MCP may not work)"
fi
echo ""

# Check network connectivity
echo "Checking network connectivity..."
if ping -c 1 google.com &> /dev/null; then
    check_pass "Internet connectivity is working"
else
    check_fail "No internet connectivity"
fi

if curl -s https://api.github.com &> /dev/null; then
    check_pass "GitHub API is accessible"
else
    check_warn "GitHub API may not be accessible"
fi
echo ""

# Summary
echo "================================"
echo "Validation Summary"
echo "================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo "Your container is properly configured."
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Validation completed with warnings: $WARNINGS${NC}"
    echo "The container should work, but some optional features may not be available."
    exit 0
else
    echo -e "${RED}✗ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo "Please fix the errors above before using the container."
    exit 1
fi
