#!/usr/bin/env bash
# ==============================================================================
# ContainAI Network Security - iptables rules for private IP range blocking
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_get_network_config()     - Get bridge name, gateway, and subnet (dynamic for nested)
#   _cai_apply_network_rules()    - Apply iptables rules to block private ranges/metadata
#   _cai_remove_network_rules()   - Remove iptables rules (for uninstall)
#   _cai_check_network_rules()    - Check if rules are present (for doctor)
#   _cai_is_nested_container()    - Check if running in a nested container environment
#   _cai_nested_iptables_supported() - Check if iptables works in nested environment
#
# Per-Container Network Policy (opt-in via .containai/network.conf):
#   _cai_parse_network_conf()     - Parse INI-style network config file
#   _cai_expand_preset()          - Expand preset name to domain list
#   _cai_resolve_domain_to_ips()  - DNS resolution with timeout
#   _cai_ip_conflicts_with_hard_block() - Check if IP conflicts with hard blocks
#   _cai_get_container_ip()       - Get container IP from Docker
#   _cai_apply_container_network_policy() - Apply per-container iptables rules
#   _cai_remove_container_network_rules() - Remove per-container rules
#   _cai_cleanup_container_network() - Cleanup helper for stop paths
#
# Network Policy:
#   Allow:
#   - Host gateway (bridge gateway IP, host.docker.internal)
#   - Internet (default route)
#
#   Block:
#   - Cloud metadata: 169.254.169.254, 169.254.170.2, 100.100.100.200
#   - Private ranges: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
#   - Link-local: 169.254.0.0/16
#
# Implementation Notes:
#   - Uses DOCKER-USER chain (Docker's intended hook for user rules)
#   - DOCKER-USER is processed before Docker's own FORWARD rules
#   - Rules are inserted with proper ordering: gateway ACCEPT first, then DROPs
#   - Comment markers enable clean identification and removal
#   - In nested containers (running inside a ContainAI sandbox):
#     * Uses docker0 bridge instead of cai0
#     * Dynamically detects gateway and subnet from inner Docker
#     * Sysbox containers may have limited iptables access
#     * runc containers with NET_ADMIN have full iptables support
#
# Dependencies:
#   - Requires lib/core.sh for logging functions
#   - Requires lib/platform.sh for _cai_is_container(), _cai_is_sysbox_container()
#   - Requires lib/docker.sh for bridge constants
#
# Usage: source lib/network.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/network.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/network.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/network.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_NETWORK_LOADED:-}" ]]; then
    return 0
fi
_CAI_NETWORK_LOADED=1

# ==============================================================================
# Network Configuration Constants
# ==============================================================================

# Cloud metadata endpoints to block (AWS, ECS, Alibaba)
_CAI_METADATA_ENDPOINTS="169.254.169.254 169.254.170.2 100.100.100.200"

# Private IP ranges to block (RFC 1918 + link-local)
_CAI_PRIVATE_RANGES="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16"

# Comment marker for identifying ContainAI rules
_CAI_IPTABLES_COMMENT="containai-network-security"

# Chain to use for rules - DOCKER-USER is Docker's intended hook for user rules
# It's processed before Docker's own rules in FORWARD chain
_CAI_IPTABLES_CHAIN="DOCKER-USER"

# ==============================================================================
# Nested Container Detection
# ==============================================================================

# Check if running in a nested container environment
# A nested container is when ContainAI is running inside another container
# (e.g., running cai inside a cai sandbox, or inside any Docker container)
# Returns: 0=nested, 1=not nested (host environment)
# Note: Currently equivalent to _cai_is_container(). Used as an intentional
#       abstraction for network rule purposes where we need to know if we're
#       targeting docker0 (nested) vs cai0 (host). This allows future
#       refinement of nested detection without changing callers.
_cai_is_nested_container() {
    _cai_is_container
}

# Determine the environment where network rules should be managed.
# Returns: "nested", "lima", or "host" via stdout.
_cai_detect_network_config_env() {
    if _cai_is_nested_container; then
        printf '%s' "nested"
    elif _cai_is_macos; then
        printf '%s' "lima"
    else
        printf '%s' "host"
    fi
}

# Check if iptables is functional in a nested container environment
# Sysbox containers virtualize the kernel and may not support full iptables
# runc containers with NET_ADMIN capability have full iptables support
# Returns: 0=supported, 1=not supported
# Outputs: Sets _CAI_NESTED_IPTABLES_STATUS with details:
#   - "host" = running on host (not nested), iptables should work
#   - "nested_supported" = nested container with iptables capability
#   - "sysbox_limited" = Sysbox container (outer isolation, skip inner rules)
#   - "no_iptables" = iptables not installed
#   - "no_net_admin" = iptables exists but permission denied (missing CAP_NET_ADMIN)
_cai_nested_iptables_supported() {
    _CAI_NESTED_IPTABLES_STATUS=""

    # If not in a container, iptables should work normally (with root/sudo)
    if ! _cai_is_container; then
        _CAI_NESTED_IPTABLES_STATUS="host"
        return 0
    fi

    # Check if we're in a Sysbox container
    # Sysbox virtualizes the network namespace and iptables may not work
    if _cai_is_sysbox_container; then
        _CAI_NESTED_IPTABLES_STATUS="sysbox_limited"
        # Sysbox provides network isolation at the outer level
        # Inner iptables rules are typically not needed/functional
        return 1
    fi

    # Check if iptables is installed first (before checking permissions)
    if ! _cai_iptables_available; then
        _CAI_NESTED_IPTABLES_STATUS="no_iptables"
        return 1
    fi

    # In a regular container (runc), check if we have NET_ADMIN capability
    # NET_ADMIN is required for iptables manipulation
    if ! _cai_iptables_can_run; then
        _CAI_NESTED_IPTABLES_STATUS="no_net_admin"
        return 1
    fi

    _CAI_NESTED_IPTABLES_STATUS="nested_supported"
    return 0
}

# ==============================================================================
# Network Configuration Detection
# ==============================================================================

# Get network configuration for iptables rules
# Outputs: bridge_name gateway_ip subnet to stdout (space-separated)
# Returns: 0=success, 1=failure
# Note: Returns different values depending on environment:
#   - Host Linux/WSL (standard): cai0, 172.30.0.1, 172.30.0.0/16
#   - macOS/Lima: docker0 inside VM (detected dynamically)
#   - Nested container: docker0 or detected bridge, detected gateway, detected subnet
# Sets: _CAI_NETWORK_CONFIG_ENV with environment type ("host", "lima", or "nested")
_cai_get_network_config() {
    local bridge_name gateway_ip subnet cidr_suffix

    if _cai_is_nested_container; then
        _CAI_NETWORK_CONFIG_ENV="nested"
        # Nested container - detect inner Docker bridge configuration
        # Inner Docker uses docker0 or a custom bridge
        #
        # Detection strategy:
        # 1. Try docker network inspect (most accurate when Docker is running)
        # 2. Fall back to ip command (works even if Docker isn't running yet)
        # 3. Use sensible defaults (docker0, 172.17.0.0/16)

        # Try to get bridge name from Docker
        bridge_name=$(docker network inspect bridge -f '{{.Options.com.docker.network.bridge.name}}' 2>/dev/null) || bridge_name=""
        if [[ -z "$bridge_name" ]]; then
            # Default inner Docker bridge name
            bridge_name="docker0"
        fi

        # Get gateway from Docker network inspect
        gateway_ip=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null) || gateway_ip=""
        if [[ -z "$gateway_ip" ]]; then
            # Fallback: try to detect from bridge interface using ip command
            # This works even if Docker daemon isn't fully ready but bridge exists
            # Use 'exit' in awk to take only the first match (in case of multiple IPs)
            gateway_ip=$(ip -4 addr show dev "$bridge_name" 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}') || gateway_ip=""
        fi
        if [[ -z "$gateway_ip" ]]; then
            # Last resort: try common docker0 default
            # Docker typically uses 172.17.0.1 as gateway
            gateway_ip="172.17.0.1"
            _cai_debug "Using default gateway IP for nested container: $gateway_ip"
        fi

        # Get subnet from Docker network inspect
        subnet=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null) || subnet=""
        if [[ -z "$subnet" ]]; then
            # Fallback: try to derive from bridge interface
            # Use 'exit' in awk to take only the first match (in case of multiple IPs)
            local cidr_addr
            cidr_addr=$(ip -4 addr show dev "$bridge_name" 2>/dev/null | awk '/inet / {print $2; exit}') || cidr_addr=""
            if [[ -n "$cidr_addr" ]]; then
                # Extract CIDR suffix and construct subnet
                local detected_cidr="${cidr_addr##*/}"
                local detected_ip="${cidr_addr%%/*}"
                case "$detected_cidr" in
                    16) subnet="${detected_ip%.*.*}.0.0/16" ;;
                    24) subnet="${detected_ip%.*}.0/24" ;;
                    *)  subnet="${detected_ip%.*.*}.0.0/16" ;;
                esac
            fi
        fi
        if [[ -z "$subnet" ]]; then
            # Last resort: common Docker default
            subnet="172.17.0.0/16"
            _cai_debug "Using default subnet for nested container: $subnet"
        fi
    elif _cai_is_macos; then
        _CAI_NETWORK_CONFIG_ENV="lima"
        # macOS/Lima - detect bridge configuration inside the Lima VM
        # The Lima VM runs Docker with default bridge (docker0)
        local vm_name="${_CAI_LIMA_VM_NAME:-containai-docker}"

        # Try to get bridge name from Docker inside Lima
        bridge_name=$(limactl shell "$vm_name" -- docker network inspect bridge -f '{{.Options.com.docker.network.bridge.name}}' 2>/dev/null) || bridge_name=""
        if [[ -z "$bridge_name" ]]; then
            # Default Docker bridge name
            bridge_name="docker0"
        fi

        # Get gateway from Docker network inspect inside Lima
        gateway_ip=$(limactl shell "$vm_name" -- docker network inspect bridge -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null) || gateway_ip=""
        if [[ -z "$gateway_ip" ]]; then
            # Fallback: try to detect from bridge interface using ip command in VM
            gateway_ip=$(limactl shell "$vm_name" -- ip -4 addr show dev "$bridge_name" 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}') || gateway_ip=""
        fi
        if [[ -z "$gateway_ip" ]]; then
            # Last resort: common docker0 default
            gateway_ip="172.17.0.1"
            _cai_debug "Using default gateway IP for Lima VM: $gateway_ip"
        fi

        # Get subnet from Docker network inspect inside Lima
        subnet=$(limactl shell "$vm_name" -- docker network inspect bridge -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null) || subnet=""
        if [[ -z "$subnet" ]]; then
            # Fallback: try to derive from bridge interface in VM
            local cidr_addr
            cidr_addr=$(limactl shell "$vm_name" -- ip -4 addr show dev "$bridge_name" 2>/dev/null | awk '/inet / {print $2; exit}') || cidr_addr=""
            if [[ -n "$cidr_addr" ]]; then
                local detected_cidr="${cidr_addr##*/}"
                local detected_ip="${cidr_addr%%/*}"
                case "$detected_cidr" in
                    16) subnet="${detected_ip%.*.*}.0.0/16" ;;
                    24) subnet="${detected_ip%.*}.0/24" ;;
                    *)  subnet="${detected_ip%.*.*}.0.0/16" ;;
                esac
            fi
        fi
        if [[ -z "$subnet" ]]; then
            # Last resort: common Docker default
            subnet="172.17.0.0/16"
            _cai_debug "Using default subnet for Lima VM: $subnet"
        fi
    else
        _CAI_NETWORK_CONFIG_ENV="host"
        # Standard host (Linux/WSL) - use ContainAI bridge constants
        bridge_name="${_CAI_CONTAINAI_DOCKER_BRIDGE:-cai0}"

        # Parse gateway IP and CIDR suffix from bridge address constant
        # Format: 172.30.0.1/16 -> gateway=172.30.0.1, cidr=/16
        local bridge_addr="${_CAI_CONTAINAI_DOCKER_BRIDGE_ADDR:-172.30.0.1/16}"
        gateway_ip="${bridge_addr%%/*}"
        cidr_suffix="${bridge_addr##*/}"

        # Construct subnet from gateway IP and CIDR suffix
        # For 172.30.0.1/16, we need 172.30.0.0/16
        # Extract network portion based on CIDR (simplified: assume /8, /12, /16, /24)
        case "$cidr_suffix" in
            8)
                subnet="${gateway_ip%%.*}.0.0.0/8"
                ;;
            12)
                local first_octet second_octet
                first_octet="${gateway_ip%%.*}"
                second_octet="${gateway_ip#*.}"
                second_octet="${second_octet%%.*}"
                # For /12, zero out lower 4 bits of second octet
                second_octet=$((second_octet & 0xF0))
                subnet="${first_octet}.${second_octet}.0.0/12"
                ;;
            16)
                subnet="${gateway_ip%.*.*}.0.0/16"
                ;;
            24)
                subnet="${gateway_ip%.*}.0/24"
                ;;
            *)
                # Default to /16 for unknown CIDR
                subnet="${gateway_ip%.*.*}.0.0/16"
                ;;
        esac
    fi

    # Validate we have required values
    if [[ -z "$bridge_name" ]] || [[ -z "$gateway_ip" ]] || [[ -z "$subnet" ]]; then
        case "${_CAI_NETWORK_CONFIG_ENV:-}" in
            nested)
                _cai_error "Failed to detect network configuration in nested container"
                _cai_error "  Is inner Docker running? Try: systemctl start docker"
                ;;
            lima)
                _cai_error "Failed to detect network configuration in Lima VM"
                _cai_error "  Is Docker running in the VM? Try: limactl shell ${_CAI_LIMA_VM_NAME:-containai-docker} -- sudo systemctl start docker"
                ;;
            *)
                _cai_error "Failed to detect network configuration"
                ;;
        esac
        return 1
    fi

    printf '%s %s %s' "$bridge_name" "$gateway_ip" "$subnet"
    return 0
}

# ==============================================================================
# iptables Rule Management
# ==============================================================================

# Check if iptables command is available
# Returns: 0=available, 1=not available
# Note: On macOS, checks inside the Lima VM via limactl shell
_cai_iptables_available() {
    if _cai_is_macos; then
        # On macOS, iptables runs inside Lima VM
        # Check if Lima VM exists and is running
        if ! command -v limactl >/dev/null 2>&1; then
            return 1
        fi
        local vm_name="${_CAI_LIMA_VM_NAME:-containai-docker}"
        # Check VM status. Prefer --format and fall back to --json for Lima
        # versions that do not support the format flag consistently.
        local vm_status
        vm_status=$(limactl list --format '{{.Name}}\t{{.Status}}' 2>/dev/null | grep "^${vm_name}[[:space:]]" | cut -f2 | head -1) || vm_status=""
        if [[ -z "$vm_status" ]]; then
            vm_status=$(limactl list --json 2>/dev/null | grep -o "\"name\":[ ]*\"$vm_name\"[^}]*\"status\":[ ]*\"[^\"]*\"" | sed 's/.*"status":[ ]*"\([^"]*\)".*/\1/' | head -1) || vm_status=""
        fi
        vm_status=$(printf '%s' "$vm_status" | tr -d '\r' | awk '{print $1}')
        if [[ "${vm_status,,}" != "running" ]]; then
            return 1
        fi
        # Check if any iptables-compatible binary is available inside the VM.
        # Include nft/legacy and explicit sbin fallbacks for non-interactive PATH.
        limactl shell "$vm_name" -- sh -c '
            command -v iptables >/dev/null 2>&1 ||
            command -v iptables-nft >/dev/null 2>&1 ||
            command -v iptables-legacy >/dev/null 2>&1 ||
            [ -x /usr/sbin/iptables ] ||
            [ -x /sbin/iptables ] ||
            [ -x /usr/bin/iptables ] ||
            [ -x /usr/sbin/iptables-nft ] ||
            [ -x /sbin/iptables-nft ] ||
            [ -x /usr/bin/iptables-nft ] ||
            [ -x /usr/sbin/iptables-legacy ] ||
            [ -x /sbin/iptables-legacy ] ||
            [ -x /usr/bin/iptables-legacy ]
        ' >/dev/null 2>&1
    else
        command -v iptables >/dev/null 2>&1
    fi
}

# Run iptables with appropriate privileges
# Platform-aware execution:
# - macOS: Runs inside Lima VM via limactl shell with non-interactive sudo
# - Linux/WSL: Runs directly with privilege escalation
# Order of attempts (Linux/WSL):
# 1. If root (EUID == 0): direct iptables
# 2. If not root: try direct first (works with CAP_NET_ADMIN in containers)
# 3. If direct fails with EPERM and sudo available: try sudo -n (non-interactive)
# Arguments: same as iptables
# Returns: iptables exit code
_cai_iptables() {
    # macOS: Execute inside Lima VM
    if _cai_is_macos; then
        local vm_name="${_CAI_LIMA_VM_NAME:-containai-docker}"
        local candidate
        local output rc
        local -a candidates=(
            iptables
            /usr/sbin/iptables
            /sbin/iptables
            /usr/bin/iptables
            iptables-nft
            /usr/sbin/iptables-nft
            /sbin/iptables-nft
            /usr/bin/iptables-nft
            iptables-legacy
            /usr/sbin/iptables-legacy
            /sbin/iptables-legacy
            /usr/bin/iptables-legacy
        )

        # Prefer non-interactive sudo for root-required iptables operations.
        for candidate in "${candidates[@]}"; do
            output=$(limactl shell "$vm_name" -- sudo -n "$candidate" "$@" 2>&1) && rc=0 || rc=$?
            if [[ $rc -eq 0 ]]; then
                [[ -n "$output" ]] && printf '%s\n' "$output"
                return 0
            fi
        done

        # Fallback: direct execution in case shell user already has privileges.
        for candidate in "${candidates[@]}"; do
            output=$(limactl shell "$vm_name" -- "$candidate" "$@" 2>&1) && rc=0 || rc=$?
            if [[ $rc -eq 0 ]]; then
                [[ -n "$output" ]] && printf '%s\n' "$output"
                return 0
            fi
        done

        [[ -n "${output:-}" ]] && printf '%s\n' "$output" >&2
        return 1
    fi

    # Linux/WSL: Direct execution with privilege handling
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        iptables "$@"
        return $?
    fi

    # Try direct first - works with CAP_NET_ADMIN in containers
    local output rc
    output=$(iptables "$@" 2>&1) && rc=0 || rc=$?

    if [[ $rc -eq 0 ]]; then
        [[ -n "$output" ]] && printf '%s\n' "$output"
        return 0
    fi

    # Check if failure was permission-related (EPERM typically gives rc=4 or message)
    if [[ "$output" == *"Permission denied"* ]] || [[ "$output" == *"Operation not permitted"* ]]; then
        # Try sudo -n (non-interactive, fails if password needed)
        if command -v sudo >/dev/null 2>&1; then
            if sudo -n iptables "$@" 2>/dev/null; then
                return 0
            fi
        fi
    fi

    # Return original error
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    return $rc
}

# Check if we have permissions to run iptables
# Returns: 0=have permissions, 1=no permissions
# Note: On macOS, checks inside the Lima VM
_cai_iptables_can_run() {
    # Try a read-only command - use -S which just lists rules
    # Avoid -L with rule numbers since empty chains fail
    # _cai_iptables handles platform differences (macOS uses limactl shell)
    _cai_iptables -S >/dev/null 2>&1
}

# Ensure DOCKER-USER chain exists
# Docker creates this chain, but we ensure it exists for robustness
# Returns: 0=chain exists or created, 1=failure
_cai_ensure_docker_user_chain() {
    # Check if chain exists
    if _cai_iptables -n -L "$_CAI_IPTABLES_CHAIN" >/dev/null 2>&1; then
        return 0
    fi

    # Chain doesn't exist - this is unusual (Docker should create it)
    # Create it and add jump from FORWARD
    _cai_warn "DOCKER-USER chain does not exist (Docker not running?)"

    if ! _cai_iptables -N "$_CAI_IPTABLES_CHAIN" 2>/dev/null; then
        _cai_error "Failed to create DOCKER-USER chain"
        return 1
    fi

    # Add jump from FORWARD to DOCKER-USER at the beginning
    if ! _cai_iptables -I FORWARD -j "$_CAI_IPTABLES_CHAIN"; then
        _cai_error "Failed to add jump to DOCKER-USER chain"
        return 1
    fi

    _cai_step "Created DOCKER-USER chain"
    return 0
}

# Find the position of the first RETURN rule in DOCKER-USER chain
# Outputs: rule number (1-based) to stdout, or empty if no RETURN
# Returns: 0=found, 1=not found
# Note: Docker's DOCKER-USER chain ends with "RETURN" by default
#       We need to insert our rules BEFORE this RETURN
_cai_find_return_position() {
    local line_num rule_num

    # Use iptables -S to get rules in order, find first RETURN
    # Format: -A DOCKER-USER -j RETURN
    line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        case "$line" in
            *" -j RETURN"*)
                printf '%d' "$line_num"
                return 0
                ;;
        esac
    done < <(_cai_iptables -S "$_CAI_IPTABLES_CHAIN" 2>/dev/null | tail -n +2)
    # tail -n +2 skips the "-N DOCKER-USER" header line

    return 1
}

# Check if a rule exists and is positioned BEFORE the RETURN rule
# Arguments:
#   $@ = rule specification arguments (without chain name)
# Returns: 0=rule exists before RETURN (valid), 1=rule missing or after RETURN
_cai_rule_before_return() {
    local return_pos=0
    local rule_pos=0
    local line_num=0
    local line
    local arg
    local match

    # Find positions of our rule and RETURN
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        case "$line" in
            *" -j RETURN"*)
                return_pos=$line_num
                ;;
        esac
        # Check if this line matches our rule using exact string matching
        # Line must contain our comment AND all specified arguments
        if [[ "$line" == *"$_CAI_IPTABLES_COMMENT"* ]]; then
            match=true
            for arg in "$@"; do
                # Use exact substring match (not regex) to avoid metachar issues
                if [[ "$line" != *"$arg"* ]]; then
                    match=false
                    break
                fi
            done
            if [[ "$match" == "true" ]]; then
                rule_pos=$line_num
            fi
        fi
    done < <(_cai_iptables -S "$_CAI_IPTABLES_CHAIN" 2>/dev/null | tail -n +2)

    # Rule must exist and be before RETURN (or no RETURN exists)
    if [[ "$rule_pos" -gt 0 ]]; then
        if [[ "$return_pos" -eq 0 ]] || [[ "$rule_pos" -lt "$return_pos" ]]; then
            return 0  # Valid position
        fi
    fi

    return 1  # Missing or after RETURN
}

# Ensure a rule exists in valid position (before RETURN in DOCKER-USER)
# If rule exists after RETURN, deletes and reinserts at correct position
# Arguments:
#   $@ = rule specification arguments (without -I/-A and chain name)
# Returns: 0=success, 1=failure
_cai_ensure_rule_before_return() {
    local return_pos

    # Check if rule exists in valid position
    if _cai_rule_before_return "$@"; then
        return 0  # Already in correct position
    fi

    # Rule either doesn't exist or is in wrong position
    # Delete any existing copies first (idempotent cleanup)
    while _cai_iptables -C "$_CAI_IPTABLES_CHAIN" "$@" 2>/dev/null; do
        _cai_iptables -D "$_CAI_IPTABLES_CHAIN" "$@" 2>/dev/null || break
    done

    # Find position of RETURN rule and insert before it
    if return_pos=$(_cai_find_return_position); then
        # Insert at the position where RETURN is (pushes RETURN down)
        if ! _cai_iptables -I "$_CAI_IPTABLES_CHAIN" "$return_pos" "$@"; then
            return 1
        fi
    else
        # No RETURN found, just append
        if ! _cai_iptables -A "$_CAI_IPTABLES_CHAIN" "$@"; then
            return 1
        fi
    fi

    return 0
}

# Apply iptables rules to block private ranges and cloud metadata
# Arguments:
#   $1 = dry_run flag ("true" for dry-run mode, default "false")
# Returns: 0=success, 1=failure
# Note: Requires root/sudo privileges unless running in a privileged container
#       In nested Sysbox containers, iptables may not be fully functional
#       In nested runc containers, requires CAP_NET_ADMIN capability
_cai_apply_network_rules() {
    local dry_run="${1:-false}"
    local bridge_name gateway_ip subnet
    local config endpoint range

    # Check if iptables is supported in nested environment
    if _cai_is_nested_container; then
        if ! _cai_nested_iptables_supported; then
            case "${_CAI_NESTED_IPTABLES_STATUS:-}" in
                sysbox_limited)
                    _cai_warn "Skipping network rules: Sysbox container provides network isolation at outer level"
                    _cai_info "  Inner iptables rules are not needed in Sysbox containers"
                    return 0
                    ;;
                no_iptables)
                    _cai_error "Cannot apply network rules: iptables is not installed in container"
                    _cai_error "  Install iptables package or use an image with iptables included"
                    return 1
                    ;;
                no_net_admin)
                    _cai_error "Cannot apply network rules: missing CAP_NET_ADMIN capability"
                    _cai_error "  Add --cap-add=NET_ADMIN when starting the container"
                    return 1
                    ;;
                *)
                    _cai_warn "Nested container iptables support unknown, attempting anyway"
                    ;;
            esac
        fi
    fi

    # Get network configuration.
    # Set environment marker before command substitution, otherwise globals from
    # _cai_get_network_config are lost in the subshell.
    _CAI_NETWORK_CONFIG_ENV="$(_cai_detect_network_config_env)"
    if ! config=$(_cai_get_network_config); then
        return 1
    fi

    # Parse config
    bridge_name="${config%% *}"
    config="${config#* }"
    gateway_ip="${config%% *}"
    subnet="${config#* }"

    local env_label
    case "${_CAI_NETWORK_CONFIG_ENV:-}" in
        nested) env_label="nested container" ;;
        lima)   env_label="Lima VM" ;;
        *)      env_label="host" ;;
    esac
    _cai_info "Applying network security rules for bridge: $bridge_name ($env_label)"

    # Check iptables availability
    if ! _cai_iptables_available; then
        if [[ "${_CAI_NETWORK_CONFIG_ENV:-}" == "lima" ]]; then
            _cai_error "iptables is not available in Lima VM"
            _cai_error "  Is the Lima VM running? Try: limactl start ${_CAI_LIMA_VM_NAME:-containai-docker}"
        else
            _cai_error "iptables is not installed"
        fi
        return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_dryrun "Would apply network security rules to bridge $bridge_name ($env_label)"
        _cai_dryrun "  Chain: $_CAI_IPTABLES_CHAIN"
        _cai_dryrun "  Gateway allowed: $gateway_ip"
        _cai_dryrun "  Metadata blocked: $_CAI_METADATA_ENDPOINTS"
        _cai_dryrun "  Private ranges blocked: $_CAI_PRIVATE_RANGES"
        return 0
    fi

    # Check permissions
    if ! _cai_iptables_can_run; then
        _cai_error "Insufficient permissions to run iptables (need root or CAP_NET_ADMIN)"
        return 1
    fi

    # Ensure DOCKER-USER chain exists
    if ! _cai_ensure_docker_user_chain; then
        return 1
    fi

    # Check if bridge interface exists
    # On macOS/Lima, check inside the VM
    local bridge_exists=false
    if [[ "${_CAI_NETWORK_CONFIG_ENV:-}" == "lima" ]]; then
        local vm_name="${_CAI_LIMA_VM_NAME:-containai-docker}"
        if limactl shell "$vm_name" -- ip link show "$bridge_name" >/dev/null 2>&1; then
            bridge_exists=true
        fi
    else
        if ip link show "$bridge_name" >/dev/null 2>&1; then
            bridge_exists=true
        fi
    fi

    if [[ "$bridge_exists" != "true" ]]; then
        case "${_CAI_NETWORK_CONFIG_ENV:-}" in
            nested)
                _cai_warn "Bridge $bridge_name does not exist yet in nested container"
                _cai_warn "  Ensure inner Docker is running: systemctl start docker"
                ;;
            lima)
                _cai_warn "Bridge $bridge_name does not exist yet in Lima VM"
                _cai_warn "  Bridge will be created when first container starts"
                ;;
            *)
                _cai_warn "Bridge $bridge_name does not exist yet (will be created by Docker)"
                ;;
        esac
        _cai_warn "Rules will be applied when bridge is available"
        # Don't fail - bridge may not exist until first container starts
        return 0
    fi

    # IMPORTANT: Rule order in DOCKER-USER chain matters!
    # Docker's DOCKER-USER chain ends with a RETURN rule by default.
    # We must insert our rules BEFORE this RETURN, otherwise they never execute.
    #
    # Ordering within our rules:
    # 1. ACCEPT gateway (must be first so host communication works)
    # 2. DROP metadata endpoints (specific IPs)
    # 3. DROP private ranges (broad blocks)
    # 4. RETURN (Docker's existing rule - continue to Docker's own rules)
    #
    # We use -I (insert at top) for gateway to ensure it's always first,
    # and _cai_insert_rule_before_return() for drops to place them before RETURN.

    # Step 1: Allow host gateway (insert at top of DOCKER-USER chain)
    # This ensures container can reach the Docker host
    if ! _cai_iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$gateway_ip" -j ACCEPT -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; then
        if ! _cai_iptables -I "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$gateway_ip" -j ACCEPT -m comment --comment "$_CAI_IPTABLES_COMMENT"; then
            _cai_error "Failed to add gateway allow rule"
            return 1
        fi
        _cai_step "Added gateway allow rule: $gateway_ip"
    else
        _cai_debug "Gateway allow rule already exists"
    fi

    # Step 2: Block specific cloud metadata endpoints (ensure before RETURN)
    # Uses _cai_ensure_rule_before_return which handles:
    # - Rules that don't exist (inserts them)
    # - Rules in wrong position after RETURN (deletes and reinserts)
    # - Rules already in correct position (no-op)
    for endpoint in $_CAI_METADATA_ENDPOINTS; do
        if ! _cai_ensure_rule_before_return -i "$bridge_name" -d "$endpoint" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT"; then
            _cai_error "Failed to add metadata block rule for $endpoint"
            return 1
        fi
        _cai_step "Ensured metadata block rule: $endpoint"
    done

    # Step 3: Block private IP ranges (ensure before RETURN)
    for range in $_CAI_PRIVATE_RANGES; do
        if ! _cai_ensure_rule_before_return -i "$bridge_name" -d "$range" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT"; then
            _cai_error "Failed to add private range block rule for $range"
            return 1
        fi
        _cai_step "Ensured private range block rule: $range"
    done

    _cai_ok "Network security rules applied successfully"
    return 0
}

# Remove iptables rules added by ContainAI
# Arguments:
#   $1 = dry_run flag ("true" for dry-run mode, default "false")
# Returns: 0=success, 1=failure
# Note: In Sysbox containers where rules were skipped, this is a no-op
_cai_remove_network_rules() {
    local dry_run="${1:-false}"
    local bridge_name gateway_ip subnet
    local config endpoint range
    local had_rules=false

    # Check if iptables is supported in nested environment
    if _cai_is_nested_container; then
        if ! _cai_nested_iptables_supported; then
            case "${_CAI_NESTED_IPTABLES_STATUS:-}" in
                sysbox_limited)
                    _cai_info "Skipping rule removal: Sysbox container (no rules applied)"
                    return 0
                    ;;
                no_iptables)
                    _cai_info "Skipping rule removal: iptables not installed in container"
                    return 0
                    ;;
                no_net_admin)
                    _cai_error "Cannot remove network rules: missing CAP_NET_ADMIN capability"
                    return 1
                    ;;
            esac
        fi
    fi

    # Get network configuration.
    # Set environment marker before command substitution, otherwise globals from
    # _cai_get_network_config are lost in the subshell.
    _CAI_NETWORK_CONFIG_ENV="$(_cai_detect_network_config_env)"
    if ! config=$(_cai_get_network_config); then
        return 1
    fi

    # Parse config
    bridge_name="${config%% *}"
    config="${config#* }"
    gateway_ip="${config%% *}"
    subnet="${config#* }"

    local env_label
    case "${_CAI_NETWORK_CONFIG_ENV:-}" in
        nested) env_label="nested container" ;;
        lima)   env_label="Lima VM" ;;
        *)      env_label="host" ;;
    esac
    _cai_info "Removing network security rules from bridge: $bridge_name ($env_label)"

    # Handle dry-run before iptables availability check
    # Dry-run should not fail due to Lima VM not running
    if [[ "$dry_run" == "true" ]]; then
        _cai_dryrun "Would remove network security rules from bridge $bridge_name ($env_label)"
        return 0
    fi

    # Check iptables availability
    if ! _cai_iptables_available; then
        if [[ "${_CAI_NETWORK_CONFIG_ENV:-}" == "lima" ]]; then
            _cai_warn "Lima VM is not running - cannot remove network rules"
            _cai_warn "  Rules may exist inside the VM. To remove them:"
            _cai_warn "  1. Start the VM: limactl start ${_CAI_LIMA_VM_NAME:-containai-docker}"
            _cai_warn "  2. Re-run: cai uninstall"
            # Return failure since rules may exist but weren't removed
            return 1
        else
            _cai_warn "iptables is not installed, no rules to remove"
            return 0
        fi
    fi

    # Check permissions
    if ! _cai_iptables_can_run; then
        _cai_error "Insufficient permissions to run iptables (need root or CAP_NET_ADMIN)"
        return 1
    fi

    # Check if DOCKER-USER chain exists
    if ! _cai_iptables -n -L "$_CAI_IPTABLES_CHAIN" >/dev/null 2>&1; then
        _cai_info "DOCKER-USER chain does not exist, no rules to remove"
        return 0
    fi

    # Remove gateway allow rule
    while _cai_iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$gateway_ip" -j ACCEPT -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; do
        if _cai_iptables -D "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$gateway_ip" -j ACCEPT -m comment --comment "$_CAI_IPTABLES_COMMENT"; then
            _cai_step "Removed gateway allow rule: $gateway_ip"
            had_rules=true
        fi
    done

    # Remove metadata block rules
    for endpoint in $_CAI_METADATA_ENDPOINTS; do
        while _cai_iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$endpoint" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; do
            if _cai_iptables -D "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$endpoint" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT"; then
                _cai_step "Removed metadata block rule: $endpoint"
                had_rules=true
            fi
        done
    done

    # Remove private range block rules
    for range in $_CAI_PRIVATE_RANGES; do
        while _cai_iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$range" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; do
            if _cai_iptables -D "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$range" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT"; then
                _cai_step "Removed private range block rule: $range"
                had_rules=true
            fi
        done
    done

    if [[ "$had_rules" == "true" ]]; then
        _cai_ok "Network security rules removed successfully"
    else
        _cai_info "No ContainAI network rules found to remove"
    fi

    return 0
}

# Check if network security rules are present
# Arguments:
#   $1 = verbose flag ("true" to report details, default "false")
# Returns: 0=all rules present, 1=some or all rules missing
# Outputs: Sets _CAI_NETWORK_RULES_STATUS with details
_cai_check_network_rules() {
    local verbose="${1:-false}"
    local bridge_name gateway_ip subnet
    local config endpoint range
    local missing_rules=0
    local total_rules=0
    local present_rules=0

    _CAI_NETWORK_RULES_STATUS=""

    # Get network configuration.
    # Set environment marker before command substitution, otherwise globals from
    # _cai_get_network_config are lost in the subshell.
    _CAI_NETWORK_CONFIG_ENV="$(_cai_detect_network_config_env)"
    if ! config=$(_cai_get_network_config); then
        _CAI_NETWORK_RULES_STATUS="config_failed"
        return 1
    fi

    # Parse config
    bridge_name="${config%% *}"
    config="${config#* }"
    gateway_ip="${config%% *}"
    subnet="${config#* }"

    # Check iptables availability
    if ! _cai_iptables_available; then
        _CAI_NETWORK_RULES_STATUS="no_iptables"
        if [[ "$verbose" == "true" ]]; then
            if [[ "${_CAI_NETWORK_CONFIG_ENV:-}" == "lima" ]]; then
                _cai_warn "Lima VM not running or iptables not available"
            else
                _cai_warn "iptables is not installed"
            fi
        fi
        return 1
    fi

    # Check permissions
    if ! _cai_iptables_can_run; then
        _CAI_NETWORK_RULES_STATUS="no_permission"
        if [[ "$verbose" == "true" ]]; then
            _cai_warn "Insufficient permissions to check iptables rules"
        fi
        return 1
    fi

    # Check if DOCKER-USER chain exists
    if ! _cai_iptables -n -L "$_CAI_IPTABLES_CHAIN" >/dev/null 2>&1; then
        _CAI_NETWORK_RULES_STATUS="no_chain"
        if [[ "$verbose" == "true" ]]; then
            _cai_warn "DOCKER-USER chain does not exist"
        fi
        return 1
    fi

    # Check gateway allow rule
    total_rules=$((total_rules + 1))
    if _cai_iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$gateway_ip" -j ACCEPT -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; then
        present_rules=$((present_rules + 1))
        if [[ "$verbose" == "true" ]]; then
            _cai_ok "Gateway allow rule present: $gateway_ip"
        fi
    else
        missing_rules=$((missing_rules + 1))
        if [[ "$verbose" == "true" ]]; then
            _cai_warn "Gateway allow rule missing: $gateway_ip"
        fi
    fi

    # Check metadata block rules
    for endpoint in $_CAI_METADATA_ENDPOINTS; do
        total_rules=$((total_rules + 1))
        if _cai_iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$endpoint" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; then
            present_rules=$((present_rules + 1))
            if [[ "$verbose" == "true" ]]; then
                _cai_ok "Metadata block rule present: $endpoint"
            fi
        else
            missing_rules=$((missing_rules + 1))
            if [[ "$verbose" == "true" ]]; then
                _cai_warn "Metadata block rule missing: $endpoint"
            fi
        fi
    done

    # Check private range block rules
    for range in $_CAI_PRIVATE_RANGES; do
        total_rules=$((total_rules + 1))
        if _cai_iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$range" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; then
            present_rules=$((present_rules + 1))
            if [[ "$verbose" == "true" ]]; then
                _cai_ok "Private range block rule present: $range"
            fi
        else
            missing_rules=$((missing_rules + 1))
            if [[ "$verbose" == "true" ]]; then
                _cai_warn "Private range block rule missing: $range"
            fi
        fi
    done

    # Set status
    if [[ "$missing_rules" -eq 0 ]]; then
        _CAI_NETWORK_RULES_STATUS="complete"
        if [[ "$verbose" == "true" ]]; then
            _cai_ok "All $total_rules network security rules are present"
        fi
        return 0
    elif [[ "$present_rules" -eq 0 ]]; then
        _CAI_NETWORK_RULES_STATUS="none"
        if [[ "$verbose" == "true" ]]; then
            _cai_warn "No network security rules found (expected $total_rules)"
        fi
        return 1
    else
        _CAI_NETWORK_RULES_STATUS="partial"
        if [[ "$verbose" == "true" ]]; then
            _cai_warn "$missing_rules of $total_rules network security rules missing"
        fi
        return 1
    fi
}

# Get a summary of network security status for doctor output
# Sets: _CAI_NETWORK_DOCTOR_STATUS with status:
#   - "ok": All rules present
#   - "skipped": Can't check (Sysbox isolation, permission denied)
#   - "bridge_missing": Bridge not present (containai-docker not running)
#   - "rules_missing": Bridge exists but rules missing
#   - "partial": Some rules missing on bridge
#   - "error": iptables not installed or other error
# Sets: _CAI_NETWORK_DOCTOR_DETAIL with human-readable detail
# Returns: 0 always (status is in globals, not return code)
# Note: Call this function directly (not via command substitution) to preserve globals
_cai_network_doctor_status() {
    local config bridge_name env_label

    _CAI_NETWORK_DOCTOR_STATUS=""
    _CAI_NETWORK_DOCTOR_DETAIL=""

    # Check nested container iptables support first
    if _cai_is_nested_container; then
        if ! _cai_nested_iptables_supported; then
            case "${_CAI_NESTED_IPTABLES_STATUS:-}" in
                sysbox_limited)
                    _CAI_NETWORK_DOCTOR_DETAIL="Sysbox container (network isolation at outer level)"
                    _CAI_NETWORK_DOCTOR_STATUS="skipped"
                    return 0
                    ;;
                no_iptables)
                    _CAI_NETWORK_DOCTOR_DETAIL="Nested container missing iptables"
                    _CAI_NETWORK_DOCTOR_STATUS="error"
                    return 0
                    ;;
                no_net_admin)
                    _CAI_NETWORK_DOCTOR_DETAIL="Nested container missing CAP_NET_ADMIN"
                    _CAI_NETWORK_DOCTOR_STATUS="error"
                    return 0
                    ;;
            esac
        fi
    fi

    # Get network configuration.
    # Set environment marker before command substitution, otherwise globals from
    # _cai_get_network_config are lost in the subshell.
    _CAI_NETWORK_CONFIG_ENV="$(_cai_detect_network_config_env)"
    if ! config=$(_cai_get_network_config 2>/dev/null); then
        _CAI_NETWORK_DOCTOR_DETAIL="Failed to detect network configuration"
        _CAI_NETWORK_DOCTOR_STATUS="error"
        return 0
    fi

    bridge_name="${config%% *}"
    case "${_CAI_NETWORK_CONFIG_ENV:-}" in
        nested) env_label=" (nested)" ;;
        lima)   env_label=" (Lima VM)" ;;
        *)      env_label="" ;;
    esac

    # Check iptables
    if ! _cai_iptables_available; then
        if [[ "${_CAI_NETWORK_CONFIG_ENV:-}" == "lima" ]]; then
            _CAI_NETWORK_DOCTOR_DETAIL="Lima VM not running or iptables not available"
        else
            _CAI_NETWORK_DOCTOR_DETAIL="iptables not installed"
        fi
        _CAI_NETWORK_DOCTOR_STATUS="error"
        return 0
    fi

    if ! _cai_iptables_can_run; then
        _CAI_NETWORK_DOCTOR_DETAIL="Cannot check iptables (permission denied)"
        _CAI_NETWORK_DOCTOR_STATUS="skipped"
        return 0
    fi

    # Check if bridge exists
    # On macOS/Lima, check inside the VM
    local bridge_exists=false
    if [[ "${_CAI_NETWORK_CONFIG_ENV:-}" == "lima" ]]; then
        local vm_name="${_CAI_LIMA_VM_NAME:-containai-docker}"
        if limactl shell "$vm_name" -- ip link show "$bridge_name" >/dev/null 2>&1; then
            bridge_exists=true
        fi
    else
        if ip link show "$bridge_name" >/dev/null 2>&1; then
            bridge_exists=true
        fi
    fi

    if [[ "$bridge_exists" != "true" ]]; then
        case "${_CAI_NETWORK_CONFIG_ENV:-}" in
            nested)
                _CAI_NETWORK_DOCTOR_DETAIL="Bridge $bridge_name not present (inner Docker not running?)"
                ;;
            lima)
                _CAI_NETWORK_DOCTOR_DETAIL="Bridge $bridge_name not present in Lima VM (Docker not running?)"
                ;;
            *)
                _CAI_NETWORK_DOCTOR_DETAIL="Bridge $bridge_name not present (containai-docker not running?)"
                ;;
        esac
        # Bridge missing is distinct from rules missing - can't apply rules yet
        _CAI_NETWORK_DOCTOR_STATUS="bridge_missing"
        return 0
    fi

    # Check rules
    if _cai_check_network_rules "false"; then
        _CAI_NETWORK_DOCTOR_DETAIL="All rules present on $bridge_name${env_label}"
        _CAI_NETWORK_DOCTOR_STATUS="ok"
    else
        case "${_CAI_NETWORK_RULES_STATUS:-}" in
            partial)
                _CAI_NETWORK_DOCTOR_DETAIL="Some rules missing on $bridge_name${env_label} (run cai setup to fix)"
                _CAI_NETWORK_DOCTOR_STATUS="partial"
                ;;
            none | no_chain)
                # Bridge exists but rules are missing - this is a real problem
                _CAI_NETWORK_DOCTOR_DETAIL="No rules on $bridge_name${env_label} (run cai setup)"
                _CAI_NETWORK_DOCTOR_STATUS="rules_missing"
                ;;
            *)
                _CAI_NETWORK_DOCTOR_DETAIL="Unknown status on $bridge_name${env_label}"
                _CAI_NETWORK_DOCTOR_STATUS="error"
                ;;
        esac
    fi

    return 0
}

# ==============================================================================
# Per-Container Network Policy (Opt-In)
# ==============================================================================
# These functions implement opt-in network egress restrictions via .containai/network.conf
# The default (no config file) allows all egress except hard blocks (private ranges, metadata)

# Comment marker for per-container rules (distinct from global rules)
_CAI_CONTAINER_IPTABLES_COMMENT="cai"

# Preset definitions for common domain groups
# Format: preset_name -> space-separated list of domains
declare -A _CAI_NETWORK_PRESETS 2>/dev/null || true
_CAI_NETWORK_PRESETS=(
    [package-managers]="registry.npmjs.org pypi.org files.pythonhosted.org crates.io dl.crates.io static.crates.io rubygems.org"
    [git-hosts]="github.com api.github.com codeload.github.com raw.githubusercontent.com objects.githubusercontent.com media.githubusercontent.com gitlab.com registry.gitlab.com bitbucket.org"
    [ai-apis]="api.anthropic.com api.openai.com"
)

# Expand a preset name to its list of domains
# Arguments: $1 = preset name
# Outputs: space-separated domain list to stdout
# Returns: 0=success, 1=unknown preset
_cai_expand_preset() {
    local preset_name="$1"

    if [[ -n "${_CAI_NETWORK_PRESETS[$preset_name]:-}" ]]; then
        printf '%s' "${_CAI_NETWORK_PRESETS[$preset_name]}"
        return 0
    else
        _cai_warn "Unknown network preset: $preset_name"
        return 1
    fi
}

# Resolve a domain name to IP addresses
# Arguments: $1 = domain name
# Outputs: space-separated list of IPs to stdout
# Returns: 0=success, 1=resolution failed
_cai_resolve_domain_to_ips() {
    local domain="$1"
    local ips="" ip_line

    # Use getent for portability (works on most Linux systems)
    # Falls back to dig if getent is unavailable
    # Use timeout wrapper if available to avoid hangs on DNS issues
    if command -v getent >/dev/null 2>&1; then
        # getent ahostsv4 returns all IPv4 addresses for a host
        local getent_output=""
        if command -v timeout >/dev/null 2>&1; then
            getent_output=$(timeout 5 getent ahostsv4 "$domain" 2>/dev/null) || getent_output=""
        else
            getent_output=$(getent ahostsv4 "$domain" 2>/dev/null) || getent_output=""
        fi
        while IFS= read -r ip_line; do
            local ip="${ip_line%% *}"
            # Skip if already in list (dedup)
            case " $ips " in
                *" $ip "*) continue ;;
            esac
            if [[ -n "$ip" ]]; then
                ips="${ips:+$ips }$ip"
            fi
        done < <(printf '%s\n' "$getent_output" | awk '{print $1}' | sort -u)
    elif command -v dig >/dev/null 2>&1; then
        # dig +short returns IPs one per line
        while IFS= read -r ip_line; do
            # Skip CNAME responses (not IPs)
            if [[ "$ip_line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ips="${ips:+$ips }$ip_line"
            fi
        done < <(dig +short +time=5 +tries=2 "$domain" A 2>/dev/null)
    elif command -v host >/dev/null 2>&1; then
        # host command as fallback
        while IFS= read -r ip_line; do
            if [[ "$ip_line" =~ has\ address\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
                ips="${ips:+$ips }${BASH_REMATCH[1]}"
            fi
        done < <(host -t A -W 5 "$domain" 2>/dev/null)
    else
        _cai_warn "No DNS resolution tool available (getent, dig, or host)"
        return 1
    fi

    if [[ -z "$ips" ]]; then
        _cai_warn "DNS resolution failed for: $domain"
        return 1
    fi

    printf '%s' "$ips"
    return 0
}

# Check if an IP address conflicts with hard blocks (private ranges, metadata)
# Arguments: $1 = IP address
# Returns: 0=conflicts (should be blocked), 1=no conflict
_cai_ip_conflicts_with_hard_block() {
    local ip="$1"

    # Parse IP into octets
    local IFS='.'
    local -a octets
    # shellcheck disable=SC2206
    octets=($ip)

    if [[ ${#octets[@]} -ne 4 ]]; then
        return 1  # Invalid IP format, no conflict
    fi

    local o1="${octets[0]}"
    local o2="${octets[1]}"

    # Check private ranges (RFC 1918)
    # 10.0.0.0/8
    if [[ "$o1" -eq 10 ]]; then
        return 0
    fi
    # 172.16.0.0/12 (172.16.x.x - 172.31.x.x)
    if [[ "$o1" -eq 172 ]] && [[ "$o2" -ge 16 ]] && [[ "$o2" -le 31 ]]; then
        return 0
    fi
    # 192.168.0.0/16
    if [[ "$o1" -eq 192 ]] && [[ "$o2" -eq 168 ]]; then
        return 0
    fi

    # Check link-local (169.254.0.0/16)
    if [[ "$o1" -eq 169 ]] && [[ "$o2" -eq 254 ]]; then
        return 0
    fi

    # Check specific metadata endpoints
    case "$ip" in
        169.254.169.254|169.254.170.2|100.100.100.200)
            return 0
            ;;
    esac

    return 1  # No conflict
}

# Parse a network.conf file (INI-style, one value per line)
# Arguments: $1 = config file path
# Sets global arrays:
#   _CAI_PARSED_PRESETS - array of preset names
#   _CAI_PARSED_ALLOWS - array of allowed domains/IPs
#   _CAI_PARSED_DEFAULT_DENY - "true" or "false"
# Returns: 0=success (or no file), 1=parse error
_cai_parse_network_conf() {
    local config_file="$1"

    # Initialize output arrays
    _CAI_PARSED_PRESETS=()
    _CAI_PARSED_ALLOWS=()
    _CAI_PARSED_DEFAULT_DENY="false"

    if [[ ! -f "$config_file" ]]; then
        return 0  # No config file is valid (means allow-all default)
    fi

    local line key value in_egress_section=false line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip lines that became empty after trimming (whitespace-only lines)
        [[ -z "$line" ]] && continue

        # Check for section headers
        if [[ "$line" =~ ^\[([a-zA-Z_-]+)\]$ ]]; then
            local section="${BASH_REMATCH[1]}"
            if [[ "$section" == "egress" ]]; then
                in_egress_section=true
            else
                in_egress_section=false
                _cai_warn "Unknown section in network.conf line $line_num: [$section]"
            fi
            continue
        fi

        # Skip lines outside [egress] section
        [[ "$in_egress_section" != "true" ]] && continue

        # Parse key = value
        if [[ "$line" =~ ^([a-zA-Z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            # Strip trailing whitespace and comments from value
            value="${value%%#*}"
            value="${value%"${value##*[![:space:]]}"}"

            case "$key" in
                preset)
                    if [[ -n "$value" ]]; then
                        _CAI_PARSED_PRESETS+=("$value")
                    fi
                    ;;
                allow)
                    if [[ -n "$value" ]]; then
                        _CAI_PARSED_ALLOWS+=("$value")
                    fi
                    ;;
                default_deny)
                    if [[ "$value" == "true" ]] || [[ "$value" == "yes" ]] || [[ "$value" == "1" ]]; then
                        _CAI_PARSED_DEFAULT_DENY="true"
                    elif [[ "$value" == "false" ]] || [[ "$value" == "no" ]] || [[ "$value" == "0" ]]; then
                        _CAI_PARSED_DEFAULT_DENY="false"
                    else
                        _cai_warn "Invalid default_deny value in network.conf line $line_num: $value"
                    fi
                    ;;
                *)
                    _cai_warn "Unknown key in network.conf line $line_num: $key"
                    ;;
            esac
        else
            _cai_warn "Invalid syntax in network.conf line $line_num: $line"
        fi
    done < "$config_file"

    return 0
}

# Get container IP address from ContainAI bridge network
# Arguments: $1 = container name, $2 = docker context (optional)
# Outputs: IP address to stdout
# Returns: 0=success, 1=failure
_cai_get_container_ip() {
    local container_name="$1"
    local context="${2:-}"
    local -a docker_cmd=(docker)

    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    local ip=""

    # Try to get IP from ContainAI bridge network first
    # Note: On host, bridge is cai0; in nested containers, it's docker0
    ip=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --format \
        '{{range $k, $v := .NetworkSettings.Networks}}{{if eq $k "bridge"}}{{$v.IPAddress}}{{end}}{{end}}' \
        -- "$container_name" 2>/dev/null) || ip=""

    # Fallback: get first available IP (with delimiter to avoid concatenation issues)
    if [[ -z "$ip" ]]; then
        ip=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --format \
            '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' \
            -- "$container_name" 2>/dev/null | awk '{print $1}') || ip=""
    fi

    if [[ -z "$ip" ]]; then
        _cai_debug "Could not get IP for container: $container_name"
        return 1
    fi

    printf '%s' "$ip"
    return 0
}

# Apply per-container network policy based on .containai/network.conf
# Arguments:
#   $1 = container name
#   $2 = workspace path (where .containai/ lives)
#   $3 = docker context (optional)
#   $4 = template network.conf path (optional, for template-level config)
# Returns: 0=success, 1=failure
# Note: This is called from start/attach paths
_cai_apply_container_network_policy() {
    local container_name="$1"
    local workspace="$2"
    local context="${3:-}"
    local template_conf="${4:-}"

    local workspace_conf="$workspace/.containai/network.conf"

    # Check if either config file exists
    local has_template_conf=false has_workspace_conf=false
    [[ -n "$template_conf" && -f "$template_conf" ]] && has_template_conf=true
    [[ -f "$workspace_conf" ]] && has_workspace_conf=true

    if [[ "$has_template_conf" != "true" && "$has_workspace_conf" != "true" ]]; then
        _cai_debug "No network.conf found for container $container_name - using default allow-all"
        # Remove any existing per-container rules (handles case where config was removed)
        _cai_remove_container_network_rules "$container_name" "$context"
        return 0
    fi

    # Parse template config first (base)
    local -a template_presets=() template_allows=()
    local template_default_deny="false"

    if [[ "$has_template_conf" == "true" ]]; then
        _cai_debug "Parsing template network.conf: $template_conf"
        if _cai_parse_network_conf "$template_conf"; then
            template_presets=("${_CAI_PARSED_PRESETS[@]}")
            template_allows=("${_CAI_PARSED_ALLOWS[@]}")
            template_default_deny="$_CAI_PARSED_DEFAULT_DENY"
        fi
    fi

    # Parse workspace config (extends template)
    local -a workspace_presets=() workspace_allows=()
    local workspace_default_deny="false"

    if [[ "$has_workspace_conf" == "true" ]]; then
        _cai_debug "Parsing workspace network.conf: $workspace_conf"
        if _cai_parse_network_conf "$workspace_conf"; then
            workspace_presets=("${_CAI_PARSED_PRESETS[@]}")
            workspace_allows=("${_CAI_PARSED_ALLOWS[@]}")
            workspace_default_deny="$_CAI_PARSED_DEFAULT_DENY"
        fi
    fi

    # Merge configs: presets and allows are additive, default_deny is OR'd
    local -a all_presets=("${template_presets[@]}" "${workspace_presets[@]}")
    local -a all_allows=("${template_allows[@]}" "${workspace_allows[@]}")
    local default_deny="false"
    [[ "$template_default_deny" == "true" || "$workspace_default_deny" == "true" ]] && default_deny="true"

    # If no default_deny, this is informational only - but we must still remove
    # any existing rules from a previous config that had default_deny=true
    if [[ "$default_deny" != "true" ]]; then
        # Remove any existing per-container rules (handles config changes)
        _cai_remove_container_network_rules "$container_name" "$context"
        if [[ ${#all_presets[@]} -gt 0 || ${#all_allows[@]} -gt 0 ]]; then
            _cai_info "Network policy (informational only, default_deny not set):"
            [[ ${#all_presets[@]} -gt 0 ]] && _cai_info "  Presets: ${all_presets[*]}"
            [[ ${#all_allows[@]} -gt 0 ]] && _cai_info "  Allows: ${all_allows[*]}"
        fi
        return 0
    fi

    _cai_info "Applying network policy for container: $container_name"

    # Get container IP
    local container_ip
    if ! container_ip=$(_cai_get_container_ip "$container_name" "$context"); then
        _cai_warn "Could not get container IP - skipping network policy"
        return 0  # Don't fail start, just skip policy
    fi

    _cai_debug "Container IP: $container_ip"

    # Check iptables availability
    if ! _cai_iptables_available; then
        _cai_warn "iptables not available - cannot apply network policy"
        return 0
    fi

    if ! _cai_iptables_can_run; then
        _cai_warn "Insufficient permissions for iptables - cannot apply network policy"
        return 0
    fi

    # Ensure DOCKER-USER chain exists
    if ! _cai_ensure_docker_user_chain; then
        _cai_warn "Could not ensure DOCKER-USER chain - cannot apply network policy"
        return 0
    fi

    # Collect all allowed IPs
    local -a allowed_ips=()
    local preset domain domains ip ips

    # Expand presets to domains, then resolve to IPs
    for preset in "${all_presets[@]}"; do
        if domains=$(_cai_expand_preset "$preset"); then
            for domain in $domains; do
                if ips=$(_cai_resolve_domain_to_ips "$domain"); then
                    for ip in $ips; do
                        # Check for hard block conflict
                        if _cai_ip_conflicts_with_hard_block "$ip"; then
                            _cai_warn "Ignoring $domain ($ip) - conflicts with hard block (private range/metadata)"
                            continue
                        fi
                        allowed_ips+=("$ip")
                    done
                fi
            done
        fi
    done

    # Resolve allow entries (domains or direct IPs)
    for domain in "${all_allows[@]}"; do
        # Check if it's already an IP
        if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
            local ip_only="${domain%%/*}"
            if _cai_ip_conflicts_with_hard_block "$ip_only"; then
                _cai_warn "Ignoring $domain - conflicts with hard block (private range/metadata)"
                continue
            fi
            allowed_ips+=("$domain")
        else
            # It's a domain, resolve it
            if ips=$(_cai_resolve_domain_to_ips "$domain"); then
                for ip in $ips; do
                    if _cai_ip_conflicts_with_hard_block "$ip"; then
                        _cai_warn "Ignoring $domain ($ip) - conflicts with hard block (private range/metadata)"
                        continue
                    fi
                    allowed_ips+=("$ip")
                done
            fi
        fi
    done

    # Remove duplicates
    local -a unique_ips=()
    local seen_ip
    for ip in "${allowed_ips[@]}"; do
        local found=false
        for seen_ip in "${unique_ips[@]}"; do
            if [[ "$ip" == "$seen_ip" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" != "true" ]]; then
            unique_ips+=("$ip")
        fi
    done

    # Apply iptables rules
    # Comment format: cai:<container_name> for easy cleanup
    local comment="${_CAI_CONTAINER_IPTABLES_COMMENT}:${container_name}"

    # First, remove any existing rules for this container (idempotent)
    _cai_remove_container_network_rules "$container_name" "$context"

    # Add ACCEPT rules for each allowed IP (must be before the DROP and before RETURN)
    # Use _cai_ensure_rule_before_return to position rules correctly
    local rule_count=0
    for ip in "${unique_ips[@]}"; do
        if _cai_ensure_rule_before_return -s "$container_ip" -d "$ip" -j ACCEPT -m comment --comment "$comment"; then
            rule_count=$((rule_count + 1))
            _cai_debug "Added ACCEPT rule: $container_ip -> $ip"
        else
            _cai_warn "Failed to add ACCEPT rule for $ip"
        fi
    done

    # Add final DROP rule for this container (default deny)
    # CRITICAL: Use _cai_ensure_rule_before_return to insert before DOCKER-USER RETURN
    # Using -A (append) would place the rule AFTER RETURN, making it unreachable
    if _cai_ensure_rule_before_return -s "$container_ip" -j DROP -m comment --comment "$comment"; then
        _cai_debug "Added DROP rule for container $container_name"
    else
        _cai_warn "Failed to add DROP rule for container"
    fi

    _cai_info "Network policy applied: $rule_count allowed destinations, default deny enabled"
    return 0
}

# Remove per-container network rules from iptables
# Arguments: $1 = container name, $2 = docker context (optional, unused but for consistency)
# Returns: 0=success
_cai_remove_container_network_rules() {
    local container_name="$1"
    local context="${2:-}"  # Reserved for future use

    # Comment to search for
    local comment="${_CAI_CONTAINER_IPTABLES_COMMENT}:${container_name}"

    # Check iptables availability
    if ! _cai_iptables_available; then
        _cai_debug "iptables not available - skipping rule cleanup"
        return 0
    fi

    if ! _cai_iptables_can_run; then
        _cai_debug "Insufficient permissions for iptables - skipping rule cleanup"
        return 0
    fi

    # Check if DOCKER-USER chain exists
    if ! _cai_iptables -n -L "$_CAI_IPTABLES_CHAIN" >/dev/null 2>&1; then
        return 0
    fi

    # Find and delete all rules with our EXACT comment
    # Use loop since we need to delete multiple rules
    # Note: No hard cap - presets + DNS can create many rules; they must all be cleaned up
    #
    # IMPORTANT: Match exact comment to avoid prefix collisions
    # e.g., "cai:foo" should NOT match "cai:foo2"
    # iptables -S output format: ... -m comment --comment "cai:container-name" ...
    # We match the full quoted comment string to ensure exact match
    local deleted=0
    local max_iterations=1000  # High safety limit (presets * multi-IP DNS answers)
    local iteration=0
    local exact_comment_pattern="--comment \"${comment}\""

    while [[ $iteration -lt $max_iterations ]]; do
        iteration=$((iteration + 1))

        # Find rule number with our EXACT comment (not substring match)
        local rule_num=""
        local line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))
            # Match exact comment pattern including quotes to prevent prefix collision
            if [[ "$line" == *"${exact_comment_pattern}"* ]]; then
                rule_num=$line_num
                break
            fi
        done < <(_cai_iptables -S "$_CAI_IPTABLES_CHAIN" 2>/dev/null | tail -n +2)

        if [[ -z "$rule_num" ]]; then
            break  # No more rules to delete
        fi

        # Delete rule by number
        if _cai_iptables -D "$_CAI_IPTABLES_CHAIN" "$rule_num" 2>/dev/null; then
            deleted=$((deleted + 1))
        else
            break  # Failed to delete, stop
        fi
    done

    if [[ $deleted -gt 0 ]]; then
        _cai_debug "Removed $deleted network policy rules for container: $container_name"
    fi

    return 0
}

# Cleanup helper for stop paths - removes container network rules
# This is the function that all stop paths should call
# Arguments: $1 = container name, $2 = docker context (optional)
# Returns: 0 always (cleanup should not fail stop)
_cai_cleanup_container_network() {
    local container_name="$1"
    local context="${2:-}"

    _cai_debug "Cleaning up network rules for container: $container_name"
    _cai_remove_container_network_rules "$container_name" "$context"
    return 0
}

return 0
