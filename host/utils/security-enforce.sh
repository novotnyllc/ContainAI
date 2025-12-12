#!/usr/bin/env bash
# Strict security enforcement helpers (privileged path).
# Requires common-functions.sh to be sourced beforehand.
set -euo pipefail

# Enforce existence and loading of security profiles at the installed root.
# Expects pre-generated channel-specific profiles (from prepare-profiles.sh).
# Arguments:
#   1: install root (release directory that already contains host/profiles)
#   2: channel (dev|nightly|prod) - required
enforce_security_profiles_strict() {
    local install_root="$1"
    local channel="${2:-}"
    local profile_dir="$install_root/host/profiles"
    
    if [[ -z "$channel" ]]; then
        die "Channel is required for security profile enforcement"
    fi
    
    # Expected pre-generated profile filenames (channel-specific)
    local apparmor_agent="$profile_dir/apparmor-containai-agent-${channel}.profile"
    local apparmor_proxy="$profile_dir/apparmor-containai-proxy-${channel}.profile"
    local apparmor_fwd="$profile_dir/apparmor-containai-log-forwarder-${channel}.profile"
    local seccomp_agent="$profile_dir/seccomp-containai-agent-${channel}.json"
    local seccomp_proxy="$profile_dir/seccomp-containai-proxy-${channel}.json"
    local seccomp_fwd="$profile_dir/seccomp-containai-log-forwarder-${channel}.json"

    [[ -f "$seccomp_agent" ]] || die "Seccomp profile missing at $seccomp_agent"
    [[ -f "$apparmor_agent" ]] || die "AppArmor profile missing at $apparmor_agent"
    [[ -f "$seccomp_proxy" ]] || die "Seccomp proxy profile missing at $seccomp_proxy"
    [[ -f "$apparmor_proxy" ]] || die "AppArmor proxy profile missing at $apparmor_proxy"
    [[ -f "$seccomp_fwd" ]] || die "Seccomp log-forwarder profile missing at $seccomp_fwd"
    [[ -f "$apparmor_fwd" ]] || die "AppArmor log-forwarder profile missing at $apparmor_fwd"

    # Write manifest for runtime freshness checks (uses _sha256_file from common-functions.sh)
    local seccomp_hash apparmor_hash seccomp_proxy_hash apparmor_proxy_hash seccomp_fwd_hash apparmor_fwd_hash
    seccomp_hash=$(_sha256_file "$seccomp_agent")
    apparmor_hash=$(_sha256_file "$apparmor_agent")
    seccomp_proxy_hash=$(_sha256_file "$seccomp_proxy")
    apparmor_proxy_hash=$(_sha256_file "$apparmor_proxy")
    seccomp_fwd_hash=$(_sha256_file "$seccomp_fwd")
    apparmor_fwd_hash=$(_sha256_file "$apparmor_fwd")
    cat > "$profile_dir/containai-profiles-${channel}.sha256" <<EOF
seccomp-containai-agent-${channel}.json $seccomp_hash
apparmor-containai-agent-${channel}.profile $apparmor_hash
seccomp-containai-proxy-${channel}.json $seccomp_proxy_hash
apparmor-containai-proxy-${channel}.profile $apparmor_proxy_hash
seccomp-containai-log-forwarder-${channel}.json $seccomp_fwd_hash
apparmor-containai-log-forwarder-${channel}.profile $apparmor_fwd_hash
EOF

    # Use shared prereq checks from common-functions.sh
    require_apparmor_tools || die "AppArmor tools missing; install apparmor-utils and retry."
    require_apparmor_enabled || die "AppArmor is disabled; enable AppArmor to continue."
    
    # Load pre-generated profiles using shared loader
    echo "Loading AppArmor profiles (channel: $channel)..."
    load_apparmor_profile "$apparmor_agent" "Agent AppArmor profile" || die "Failed to load agent profile"
    load_apparmor_profile "$apparmor_proxy" "Proxy AppArmor profile" || die "Failed to load proxy profile"
    load_apparmor_profile "$apparmor_fwd" "Log-forwarder AppArmor profile" || die "Failed to load log-forwarder profile"
}

if [[ "${1:-}" == "--verify" ]]; then
    enforce_security_profiles_strict "${2:-}" "${3:-}"
fi
