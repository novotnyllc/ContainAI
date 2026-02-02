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
#
# Dependencies:
#   - Requires lib/core.sh for logging functions
#   - Requires lib/platform.sh for _cai_is_container()
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
# Network Configuration Detection
# ==============================================================================

# Get network configuration for iptables rules
# Outputs: bridge_name gateway_ip subnet to stdout (space-separated)
# Returns: 0=success, 1=failure
# Note: Returns different values depending on environment:
#   - Host (standard): cai0, 172.30.0.1, 172.30.0.0/16
#   - Nested container: docker0 or detected bridge, detected gateway, detected subnet
_cai_get_network_config() {
    local bridge_name gateway_ip subnet cidr_suffix

    if _cai_is_container; then
        # Nested container - detect inner Docker bridge configuration
        # Inner Docker uses docker0 or a custom bridge
        bridge_name=$(docker network inspect bridge -f '{{.Options.com.docker.network.bridge.name}}' 2>/dev/null) || bridge_name=""
        if [[ -z "$bridge_name" ]]; then
            bridge_name="docker0"
        fi

        # Get gateway from Docker network inspect
        gateway_ip=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null) || gateway_ip=""
        if [[ -z "$gateway_ip" ]]; then
            # Fallback: try to detect from bridge interface
            gateway_ip=$(ip -4 addr show dev "$bridge_name" 2>/dev/null | awk '/inet / {print $2}' | cut -d'/' -f1) || gateway_ip=""
        fi

        # Get subnet from Docker network inspect
        subnet=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null) || subnet=""
        if [[ -z "$subnet" ]]; then
            # Fallback: common Docker default
            subnet="172.17.0.0/16"
        fi
    else
        # Standard host - use ContainAI bridge constants
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
        _cai_error "Failed to detect network configuration"
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
_cai_iptables_available() {
    command -v iptables >/dev/null 2>&1
}

# Check if we have permissions to run iptables
# Returns: 0=have permissions, 1=no permissions
_cai_iptables_can_run() {
    # Try a read-only command - use -S which just lists rules
    # Avoid -L with rule numbers since empty chains fail
    iptables -S >/dev/null 2>&1
}

# Ensure DOCKER-USER chain exists
# Docker creates this chain, but we ensure it exists for robustness
# Returns: 0=chain exists or created, 1=failure
_cai_ensure_docker_user_chain() {
    # Check if chain exists
    if iptables -n -L "$_CAI_IPTABLES_CHAIN" >/dev/null 2>&1; then
        return 0
    fi

    # Chain doesn't exist - this is unusual (Docker should create it)
    # Create it and add jump from FORWARD
    _cai_warn "DOCKER-USER chain does not exist (Docker not running?)"

    if ! iptables -N "$_CAI_IPTABLES_CHAIN" 2>/dev/null; then
        _cai_error "Failed to create DOCKER-USER chain"
        return 1
    fi

    # Add jump from FORWARD to DOCKER-USER at the beginning
    if ! iptables -I FORWARD -j "$_CAI_IPTABLES_CHAIN"; then
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
    done < <(iptables -S "$_CAI_IPTABLES_CHAIN" 2>/dev/null | tail -n +2)
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
    local rule_pattern=""
    local arg

    # Build a pattern to match this rule in iptables -S output
    # We need to match the key parts: -i bridge -d dest -j ACTION
    for arg in "$@"; do
        rule_pattern="$rule_pattern.*$arg"
    done

    # Find positions of our rule and RETURN
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        case "$line" in
            *" -j RETURN"*)
                return_pos=$line_num
                ;;
        esac
        # Check if this line matches our rule pattern
        if [[ "$line" =~ $_CAI_IPTABLES_COMMENT ]] && [[ "$line" =~ $rule_pattern ]]; then
            rule_pos=$line_num
        fi
    done < <(iptables -S "$_CAI_IPTABLES_CHAIN" 2>/dev/null | tail -n +2)

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
    while iptables -C "$_CAI_IPTABLES_CHAIN" "$@" 2>/dev/null; do
        iptables -D "$_CAI_IPTABLES_CHAIN" "$@" 2>/dev/null || break
    done

    # Find position of RETURN rule and insert before it
    if return_pos=$(_cai_find_return_position); then
        # Insert at the position where RETURN is (pushes RETURN down)
        if ! iptables -I "$_CAI_IPTABLES_CHAIN" "$return_pos" "$@"; then
            return 1
        fi
    else
        # No RETURN found, just append
        if ! iptables -A "$_CAI_IPTABLES_CHAIN" "$@"; then
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
_cai_apply_network_rules() {
    local dry_run="${1:-false}"
    local bridge_name gateway_ip subnet
    local config endpoint range

    # Get network configuration
    if ! config=$(_cai_get_network_config); then
        return 1
    fi

    # Parse config
    bridge_name="${config%% *}"
    config="${config#* }"
    gateway_ip="${config%% *}"
    subnet="${config#* }"

    _cai_info "Applying network security rules for bridge: $bridge_name"

    # Check iptables availability
    if ! _cai_iptables_available; then
        _cai_error "iptables is not installed"
        return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_dryrun "Would apply network security rules to bridge $bridge_name"
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
    if ! ip link show "$bridge_name" >/dev/null 2>&1; then
        _cai_warn "Bridge $bridge_name does not exist yet (will be created by Docker)"
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
    if ! iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$gateway_ip" -j ACCEPT -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; then
        if ! iptables -I "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$gateway_ip" -j ACCEPT -m comment --comment "$_CAI_IPTABLES_COMMENT"; then
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
_cai_remove_network_rules() {
    local dry_run="${1:-false}"
    local bridge_name gateway_ip subnet
    local config endpoint range
    local had_rules=false

    # Get network configuration
    if ! config=$(_cai_get_network_config); then
        return 1
    fi

    # Parse config
    bridge_name="${config%% *}"
    config="${config#* }"
    gateway_ip="${config%% *}"
    subnet="${config#* }"

    _cai_info "Removing network security rules from bridge: $bridge_name"

    # Check iptables availability
    if ! _cai_iptables_available; then
        _cai_warn "iptables is not installed, no rules to remove"
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_dryrun "Would remove network security rules from bridge $bridge_name"
        return 0
    fi

    # Check permissions
    if ! _cai_iptables_can_run; then
        _cai_error "Insufficient permissions to run iptables (need root or CAP_NET_ADMIN)"
        return 1
    fi

    # Check if DOCKER-USER chain exists
    if ! iptables -n -L "$_CAI_IPTABLES_CHAIN" >/dev/null 2>&1; then
        _cai_info "DOCKER-USER chain does not exist, no rules to remove"
        return 0
    fi

    # Remove gateway allow rule
    while iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$gateway_ip" -j ACCEPT -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; do
        if iptables -D "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$gateway_ip" -j ACCEPT -m comment --comment "$_CAI_IPTABLES_COMMENT"; then
            _cai_step "Removed gateway allow rule: $gateway_ip"
            had_rules=true
        fi
    done

    # Remove metadata block rules
    for endpoint in $_CAI_METADATA_ENDPOINTS; do
        while iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$endpoint" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; do
            if iptables -D "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$endpoint" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT"; then
                _cai_step "Removed metadata block rule: $endpoint"
                had_rules=true
            fi
        done
    done

    # Remove private range block rules
    for range in $_CAI_PRIVATE_RANGES; do
        while iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$range" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; do
            if iptables -D "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$range" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT"; then
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
            _cai_warn "iptables is not installed"
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
    if ! iptables -n -L "$_CAI_IPTABLES_CHAIN" >/dev/null 2>&1; then
        _CAI_NETWORK_RULES_STATUS="no_chain"
        if [[ "$verbose" == "true" ]]; then
            _cai_warn "DOCKER-USER chain does not exist"
        fi
        return 1
    fi

    # Check gateway allow rule
    total_rules=$((total_rules + 1))
    if iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$gateway_ip" -j ACCEPT -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; then
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
        if iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$endpoint" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; then
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
        if iptables -C "$_CAI_IPTABLES_CHAIN" -i "$bridge_name" -d "$range" -j DROP -m comment --comment "$_CAI_IPTABLES_COMMENT" 2>/dev/null; then
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
# Returns: status string ("ok", "missing", "partial", "error") via stdout
# Outputs: Sets _CAI_NETWORK_DOCTOR_DETAIL with human-readable detail
_cai_network_doctor_status() {
    local config bridge_name

    _CAI_NETWORK_DOCTOR_DETAIL=""

    # Get network configuration
    if ! config=$(_cai_get_network_config 2>/dev/null); then
        _CAI_NETWORK_DOCTOR_DETAIL="Failed to detect network configuration"
        printf '%s' "error"
        return 0
    fi

    bridge_name="${config%% *}"

    # Check iptables
    if ! _cai_iptables_available; then
        _CAI_NETWORK_DOCTOR_DETAIL="iptables not installed"
        printf '%s' "error"
        return 0
    fi

    if ! _cai_iptables_can_run; then
        _CAI_NETWORK_DOCTOR_DETAIL="Cannot check iptables (permission denied)"
        printf '%s' "error"
        return 0
    fi

    # Check if bridge exists
    if ! ip link show "$bridge_name" >/dev/null 2>&1; then
        _CAI_NETWORK_DOCTOR_DETAIL="Bridge $bridge_name not present (containai-docker not running?)"
        printf '%s' "missing"
        return 0
    fi

    # Check rules
    if _cai_check_network_rules "false"; then
        _CAI_NETWORK_DOCTOR_DETAIL="All rules present on $bridge_name"
        printf '%s' "ok"
    else
        case "${_CAI_NETWORK_RULES_STATUS:-}" in
            partial)
                _CAI_NETWORK_DOCTOR_DETAIL="Some rules missing on $bridge_name (run cai setup to fix)"
                printf '%s' "partial"
                ;;
            none | no_chain)
                _CAI_NETWORK_DOCTOR_DETAIL="No rules on $bridge_name (run cai setup)"
                printf '%s' "missing"
                ;;
            *)
                _CAI_NETWORK_DOCTOR_DETAIL="Unknown status on $bridge_name"
                printf '%s' "error"
                ;;
        esac
    fi

    return 0
}

return 0
