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
        # Use machine-parseable format to check VM status
        # Match specific VM name and Running status to avoid false positives
        local vm_status
        vm_status=$(limactl list --format '{{.Name}}\t{{.Status}}' 2>/dev/null | awk -F'\t' -v name="$vm_name" '$1 == name {print $2}') || vm_status=""
        if [[ "$vm_status" != "Running" ]]; then
            return 1
        fi
        # Check if iptables is available inside the VM
        limactl shell "$vm_name" -- command -v iptables >/dev/null 2>&1
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
        # Construct iptables command for Lima shell
        # Use sudo -n (non-interactive) to avoid blocking on password prompt
        # Lima VMs typically have passwordless sudo for the default user
        limactl shell "$vm_name" -- sudo -n iptables "$@"
        return $?
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

    # Get network configuration
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

    # Get network configuration
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

    # Get network configuration
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

    # Get network configuration
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

return 0
