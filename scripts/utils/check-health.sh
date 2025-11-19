#!/usr/bin/env bash
# CodingAgents Doctor: Diagnoses system readiness and security posture.
# Usage: ./scripts/utils/check-health.sh

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

load_common_functions() {
    if [ -n "${COMMON_FUNCS_LOADED:-}" ]; then
        return
    fi
    local saved_shell_opts
    saved_shell_opts=$(set +o)
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/common-functions.sh"
    eval "$saved_shell_opts"
    COMMON_FUNCS_LOADED=1
}

# --- Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

header() { echo -e "\n${CYAN}🏥 $1${NC}"; echo "----------------------------------------"; }
pass()   { echo -e "${GREEN}✅ $1${NC}"; ((PASS++)); }
warn()   { echo -e "${YELLOW}⚠️  $1${NC}"; echo "   💡 $2"; ((WARN++)); }
fail()   { echo -e "${RED}❌ $1${NC}"; echo "   👉 Fix: $2"; ((FAIL++)); }
info()   { echo -e "   ℹ️  $1"; }

echo -e "${BLUE}CodingAgents System Diagnosis${NC}"

# --- 1. PRIVILEGE CHECK ---
header "User Context"
if [ "$(id -u)" -eq 0 ]; then
    pass "Running as Root (System Install Ready)"
    # Warn if they are running as root but inside a user namespace (e.g. rootless podman)
    if [ "$(cat /proc/self/uid_map 2>/dev/null | awk '{print $1}')" != "0" ]; then
        info "Note: You appear to be root inside a user namespace."
    fi
else
    pass "Running as User $(whoami)"
    if command -v sudo >/dev/null; then
        info "Sudo is available (Required for 'install-system')"
    else
        warn "No Sudo Access" "You can run agents, but cannot perform a System Install."
    fi
fi

# --- 2. OS ENVIRONMENT ---
header "Operating System"
OS_TYPE=$(uname -s)
ARCH=$(uname -m)

if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
    pass "Environment: WSL 2 ($ARCH)"
    IS_WSL=1
    
    # WSL 2 Specific Security Checks
    # A. Systemd
    if [ -d /run/systemd/system ]; then
        pass "WSL: Systemd is active"
    else
        fail "WSL: Systemd is disabled" "Run './scripts/utils/fix-wsl-security.sh' to enable."
    fi

    # B. Kernel Version
    KERNEL_VER=$(uname -r)
    if [[ "$KERNEL_VER" =~ ^([0-9]+)\.([0-9]+) ]]; then
        MAJOR=${BASH_REMATCH[1]}
        MINOR=${BASH_REMATCH[2]}
        if [ "$MAJOR" -lt 5 ] || ([ "$MAJOR" -eq 5 ] && [ "$MINOR" -lt 10 ]); then
             warn "WSL: Kernel too old ($KERNEL_VER)" "Run 'wsl --update' in PowerShell for better security."
        else
             pass "WSL: Kernel v$KERNEL_VER (Supported)"
        fi
    fi

    # C. AppArmor (The Critical Check)
    if [ -f /sys/kernel/security/apparmor/profiles ]; then
        pass "WSL: AppArmor is active"
    else
        fail "WSL: AppArmor DISABLED" "Your agents are running unconfined! Run './scripts/utils/fix-wsl-security.sh' immediately."
    fi

elif [ "$OS_TYPE" = "Darwin" ]; then
    pass "Environment: macOS ($ARCH)"
    IS_WSL=0
elif [ "$OS_TYPE" = "Linux" ]; then
    pass "Environment: Native Linux ($ARCH)"
    IS_WSL=0
    
    # Native Linux requires stricter checks
    if ! command -v apparmor_parser >/dev/null; then
         warn "AppArmor tools missing" "Install 'apparmor-utils' for container hardening."
    fi
else
    warn "Environment: Unknown ($OS_TYPE)" "Support is best-effort."
    IS_WSL=0
fi

# --- 3. CONTAINER ENGINE ---
header "Container Engine"

CONTAINER_CMD=""
if command -v docker >/dev/null; then
    CONTAINER_CMD="docker"
elif command -v podman >/dev/null; then
    CONTAINER_CMD="podman"
fi

if [ -z "$CONTAINER_CMD" ]; then
    fail "No Container Engine" "Install Docker Desktop or Podman."
else
    # Inspect the runtime
    if INFO=$("$CONTAINER_CMD" info --format '{{json .}}' 2>/dev/null); then
        SERVER_VER=$(echo "$INFO" | grep -o '"ServerVersion":"[^"]*"' | cut -d'"' -f4)
        pass "$CONTAINER_CMD v$SERVER_VER is running"
        
        # Check Backend Type
        IS_DESKTOP=0
        if echo "$INFO" | grep -q "Docker Desktop"; then
            IS_DESKTOP=1
            pass "Backend: Docker Desktop (Safe VM Isolation)"
        elif [ "$IS_WSL" -eq 1 ]; then
             warn "Backend: Native Engine (WSL 2)" "You are running Docker directly in WSL. AppArmor is REQUIRED here."
        elif [ "$OS_TYPE" = "Linux" ]; then
             # Check for gVisor
             if echo "$INFO" | grep -q "runsc"; then
                 pass "Runtime: gVisor (runsc) available"
             else
                 warn "Runtime: Standard (Shared Kernel)" "Consider installing gVisor (runsc) for stronger isolation."
             fi
        fi
        
        # Check User Namespaces (Podman)
        if [ "$CONTAINER_CMD" = "podman" ]; then
             if echo "$INFO" | grep -q "rootless"; then
                 pass "Mode: Rootless (Good)"
             else
                 warn "Mode: Rootful" "Running as root is riskier on Linux."
             fi
        fi
    else
        fail "$CONTAINER_CMD is installed but NOT running" "Start the service or desktop app."
    fi
fi

# --- 4. NETWORK ---
header "Connectivity"
if curl --head --fail --silent --max-time 3 "https://ghcr.io" >/dev/null; then
    pass "Registry: ghcr.io Reachable"
else
    warn "Registry: ghcr.io Unreachable" "Check VPN/Proxy settings. Agent pulls may fail."
fi

# --- 5. STORAGE ---
header "Storage"
# Check install dir or current dir
CHECK_PATH="${INSTALL_DIR:-$PWD}"
# Portable Space Check (POSIX df)
FREE_MB=$(df -kP "$CHECK_PATH" | awk 'NR==2 {print $4}')
FREE_GB=$((FREE_MB / 1024 / 1024))

if [ "$FREE_GB" -ge 5 ]; then
    pass "Space: ${FREE_GB}GB Available"
else
    warn "Space: Low (${FREE_GB}GB)" "Agents and images require ~5GB."
fi

# --- 6. SECURITY GUARDRAILS ---
header "Launcher Security Gates"

if load_common_functions; then
    CODING_AGENTS_REPO_ROOT="$REPO_ROOT"
    if host_output=$(verify_host_security_prereqs "$REPO_ROOT" 2>&1); then
        pass "Host enforcement: seccomp & AppArmor present"
    else
        fail "Host enforcement failed" "Resolve the errors below (run fix-wsl-security if on WSL)."
        while IFS= read -r line; do
            [ -n "$line" ] && info "$line"
        done <<< "$host_output"
    fi

    if container_output=$(verify_container_security_support 2>&1); then
        pass "Runtime enforcement: container advertises seccomp+AppArmor"
    else
        fail "Runtime enforcement failed" "Update Docker/Podman so it reports seccomp & AppArmor."
        while IFS= read -r line; do
            [ -n "$line" ] && info "$line"
        done <<< "$container_output"
    fi
else
    warn "Security helper load failed" "Unable to run launcher guard checks; inspect scripts/utils/common-functions.sh"
fi

# --- SUMMARY ---
echo ""
echo "========================================"
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✅ System Ready.${NC}"
    if [ $WARN -gt 0 ]; then
        echo -e "${YELLOW}   (With $WARN warnings to consider)${NC}"
    fi
    exit 0
else
    echo -e "${RED}❌ System Check Failed ($FAIL errors).${NC}"
    echo "   Please fix the issues above before launching."
    exit 1
fi