#!/usr/bin/env bash
# ContainAI Doctor: Diagnoses system readiness and security posture.
# shellcheck source-path=SCRIPTDIR source=common-functions.sh
# Usage: ./host/utils/check-health.sh

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
declare -a FIX_COMMAND=()
HOST_APPARMOR_ACTIVE=0
COSIGN_BIN="${COSIGN_BIN:-cosign}"
ENV_DETECTED=0

header() { echo -e "\n${CYAN}🏥 $1${NC}"; echo "----------------------------------------"; }
pass()   { echo -e "${GREEN}✅ $1${NC}"; ((PASS++)); }
warn()   { echo -e "${YELLOW}⚠️  $1${NC}"; echo "   💡 $2"; ((WARN++)); }
fail()   { echo -e "${RED}❌ $1${NC}"; echo "   👉 Fix: $2"; ((FAIL++)); }
info()   { echo -e "   ℹ️  $1"; }

load_env_profile() {
    local env_script="$SCRIPT_DIR/env-detect.sh"
    if [ -x "$env_script" ]; then
        if env_output=$("$env_script" --format env 2>/dev/null); then
            eval "$env_output"
            ENV_DETECTED=1
        fi
    fi
}

suggest_fix() {
    if [ ${#FIX_COMMAND[@]} -eq 0 ]; then
        FIX_COMMAND=("$@")
    fi
}

prompt_fix_command() {
    if [ ${#FIX_COMMAND[@]} -eq 0 ]; then
        echo -e "${YELLOW}💡 Review the errors above and follow the suggested manual steps.${NC}"
        return
    fi

    local display_cmd
    if [[ "${FIX_COMMAND[0]}" == "$REPO_ROOT"* ]]; then
        display_cmd="./${FIX_COMMAND[0]#$REPO_ROOT/}"
    else
        display_cmd="${FIX_COMMAND[0]}"
    fi
    if [ ${#FIX_COMMAND[@]} -gt 1 ]; then
        display_cmd+=" ${FIX_COMMAND[*]:1}"
    fi

    if [ ! -t 0 ]; then
        echo -e "${YELLOW}💡 Suggested fix: run '${display_cmd}' and rerun check-health.${NC}"
        return
    fi

    read -r -p "$(echo -e "${CYAN}Run ${display_cmd} now? [y/N]: ${NC}")" reply
    if [[ "$reply" =~ ^[Yy]$ || "$reply" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${BLUE}▶ Executing ${display_cmd}${NC}"
        if ( cd "$REPO_ROOT" && "${FIX_COMMAND[@]}" ); then
            echo -e "${GREEN}✅ Fix command completed. Re-run check-health to confirm.${NC}"
        else
            echo -e "${RED}❌ Fix command failed. Review the output above for details.${NC}"
        fi
    else
        echo -e "${YELLOW}ℹ️  Skipped automated fix. Run '${display_cmd}' later.${NC}"
    fi
}

verify_sigstore_artifacts() {
    local install_root="${CONTAINAI_ROOT:-$REPO_ROOT}"
    local release_root=""

    if [ -L "$install_root/current" ]; then
        release_root="$(readlink -f "$install_root/current" || true)"
    elif [ -d "$install_root/releases" ]; then
        release_root="$install_root"
    fi

    if [ -z "$release_root" ] || [ ! -d "$release_root" ]; then
        warn "Sigstore: no release tree found" "Install via host/utils/install-package.sh to enable signature verification."
        return
    fi

    local tarball
    tarball=$(find "$release_root" -maxdepth 1 -name 'containai-*.tar.gz' | head -n 1)
    if [ -z "$tarball" ]; then
        warn "Sigstore: tarball copy missing" "Installers now retain tarball+sig for verification; reinstall to restore."
        return
    fi

    local sig="$tarball.sig"
    if [ ! -f "$sig" ]; then
        warn "Sigstore: signature missing" "Repackage with scripts/release/package.sh --sign to produce $sig"
        return
    fi

    if ! command -v "$COSIGN_BIN" >/dev/null 2>&1; then
        warn "Sigstore: cosign not available" "Install cosign to verify $sig"
        return
    fi

    if COSIGN_EXPERIMENTAL=1 "$COSIGN_BIN" verify-blob --signature "$sig" "$tarball" >/dev/null 2>&1; then
        pass "Sigstore: tarball signature verified"
    else
        fail "Sigstore verification failed" "Rebuild package or verify signing identity."
    fi
}

echo -e "${BLUE}ContainAI System Diagnosis${NC}"
load_env_profile

# --- 1. PRIVILEGE CHECK ---
header "User Context"
if [ "$(id -u)" -eq 0 ]; then
    pass "Running as Root (System Install Ready)"
    # Warn if they are running as root but inside a user namespace
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
        fail "WSL: Systemd is disabled" "Run './host/utils/fix-wsl-security.sh' to enable."
        suggest_fix "$REPO_ROOT/host/utils/fix-wsl-security.sh"
    fi

    # B. Kernel Version
    KERNEL_VER=$(uname -r)
    if [[ "$KERNEL_VER" =~ ^([0-9]+)\.([0-9]+) ]]; then
        MAJOR=${BASH_REMATCH[1]}
        MINOR=${BASH_REMATCH[2]}
        if [ "$MAJOR" -lt 5 ] || { [ "$MAJOR" -eq 5 ] && [ "$MINOR" -lt 10 ]; }; then
             warn "WSL: Kernel too old ($KERNEL_VER)" "Run 'wsl --update' in PowerShell for better security."
        else
             pass "WSL: Kernel v$KERNEL_VER (Supported)"
        fi
    fi

    # C. AppArmor (The Critical Check)
    if [ -f /sys/kernel/security/apparmor/profiles ]; then
        pass "WSL: AppArmor is active"
        HOST_APPARMOR_ACTIVE=1
    else
        fail "WSL: AppArmor DISABLED" "Your agents are running unconfined! Run './host/utils/fix-wsl-security.sh' immediately."
        suggest_fix "$REPO_ROOT/host/utils/fix-wsl-security.sh"
    fi

elif [ "$OS_TYPE" = "Darwin" ]; then
    pass "Environment: macOS ($ARCH)"
    IS_WSL=0
elif [ "$OS_TYPE" = "Linux" ]; then
    pass "Environment: Native Linux ($ARCH)"
    IS_WSL=0
    if [ -f /sys/kernel/security/apparmor/profiles ]; then
        HOST_APPARMOR_ACTIVE=1
    fi
    
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
fi
PODMAN_PRESENT=0
if command -v podman >/dev/null 2>&1; then
    PODMAN_PRESENT=1
fi

if [ -z "$CONTAINER_CMD" ]; then
    if [ $PODMAN_PRESENT -eq 1 ]; then
        fail "Podman detected (unsupported)" "Install Docker Desktop or Docker Engine; Podman lacks required seccomp/AppArmor parity."
    else
        fail "No Container Engine" "Install Docker Desktop or Docker Engine."
    fi
else
    # Inspect the runtime
    if INFO=$("$CONTAINER_CMD" info --format '{{json .}}' 2>/dev/null); then
        SERVER_VER=$(echo "$INFO" | grep -o '"ServerVersion":"[^"]*"' | cut -d'"' -f4)
        pass "$CONTAINER_CMD v$SERVER_VER is running"
        
        # Check Backend Type
        # shellcheck disable=SC2034
        # shellcheck disable=SC2034
        IS_DESKTOP=0
        if echo "$INFO" | grep -q "Docker Desktop"; then
            # shellcheck disable=SC2034
            IS_DESKTOP=1
            pass "Backend: Docker Desktop (Safe VM Isolation)"
        elif [ "$IS_WSL" -eq 1 ]; then
             if [ "${HOST_APPARMOR_ACTIVE:-0}" -eq 1 ]; then
                 pass "Backend: Native Engine (WSL 2)"
             else
                 warn "Backend: Native Engine (WSL 2)" "You are running Docker directly in WSL. AppArmor is REQUIRED here."
             fi
        elif [ "$OS_TYPE" = "Linux" ]; then
             # Check for gVisor
             if echo "$INFO" | grep -q "runsc"; then
                 pass "Runtime: gVisor (runsc) available"
             else
                 warn "Runtime: Standard (Shared Kernel)" "Consider installing gVisor (runsc) for stronger isolation."
             fi
        fi
        
    else
        fail "$CONTAINER_CMD is installed but NOT running" "Start the service or desktop app."
    fi
fi

if [ $PODMAN_PRESENT -eq 1 ] && [ "$CONTAINER_CMD" = "docker" ]; then
    warn "Podman detected in PATH" "Launchers enforce Docker; ensure Docker remains default and remove Podman if socket hijacks occur."
fi

# --- 4. NETWORK ---
header "Connectivity"
REGISTRY_URL="https://ghcr.io/v2/"
registry_status=$(curl --silent --show-error --location --write-out "%{http_code}" --output /dev/null --max-time 6 --connect-timeout 3 --retry 1 --retry-connrefused "$REGISTRY_URL" 2>/dev/null || echo "000")
if [[ "$registry_status" =~ ^[0-9]+$ ]] && [ "$registry_status" -ne 000 ] && [ "$registry_status" -lt 500 ]; then
    pass "Registry: ghcr.io reachable (HTTP $registry_status)"
else
    warn "Registry: ghcr.io check failed" "Received HTTP $registry_status. Verify DNS / proxy settings and confirm 'curl $REGISTRY_URL' succeeds manually."
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
    host_output=$(verify_host_security_prereqs "$REPO_ROOT" 2>&1)
    host_status=$?
    if [ $host_status -eq 0 ]; then
        pass "Host enforcement: seccomp & AppArmor present"
    else
        fail "Host enforcement failed" "Resolve the errors below (see suggested fix)."
        profile_file="$REPO_ROOT/host/profiles/apparmor-containai.profile"
        if printf '%s' "$host_output" | grep -q "AppArmor profile 'containai' is not loaded"; then
            suggest_fix sudo apparmor_parser -r "$profile_file"
        elif printf '%s' "$host_output" | grep -q "AppArmor profile file"; then
            suggest_fix "$REPO_ROOT/scripts/install.sh"
        elif printf '%s' "$host_output" | grep -qi "AppArmor kernel support not detected"; then
            suggest_fix "$REPO_ROOT/host/utils/fix-wsl-security.sh"
        elif [ "${IS_WSL:-0}" -eq 1 ]; then
            suggest_fix "$REPO_ROOT/host/utils/fix-wsl-security.sh"
        else
            suggest_fix "$REPO_ROOT/scripts/install.sh"
        fi
    fi
    if [ -n "$host_output" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && info "$line"
        done <<< "$host_output"
    fi

    if container_output=$(verify_container_security_support 2>&1); then
        pass "Runtime enforcement: container advertises seccomp+AppArmor"
    else
        fail "Runtime enforcement failed" "Update Docker so it reports seccomp & AppArmor."
        while IFS= read -r line; do
            [ -n "$line" ] && info "$line"
        done <<< "$container_output"
    fi
else
    warn "Security helper load failed" "Unable to run launcher guard checks; inspect host/utils/common-functions.sh"
fi

# --- 7. INTEGRITY & SIGNATURE ---
header "Integrity & Signature"
verify_sigstore_artifacts

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
    prompt_fix_command
    exit 1
fi
