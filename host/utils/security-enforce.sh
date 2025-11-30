#!/usr/bin/env bash
# Strict security enforcement helpers (privileged path).
# Requires common-functions.sh to be sourced beforehand.
set -euo pipefail

# Enforce existence and loading of security profiles at the installed root.
# Expects pre-generated channel-specific profiles (from prepare-profiles.sh).
# Arguments:
#   1: install root (release directory that already contains host/profiles)
enforce_security_profiles_strict() {
    local install_root="$1"
    local profile_dir="$install_root/host/profiles"
    
    # Detect channel from the generated channel file
    local channel_file="$profile_dir/channel"
    local channel="prod"
    if [[ -f "$channel_file" ]]; then
        channel="$(cat "$channel_file")"
    fi
    
    # Expected pre-generated profile filenames (channel-specific)
    local apparmor_agent="$profile_dir/apparmor-containai-agent-${channel}.profile"
    local apparmor_proxy="$profile_dir/apparmor-containai-proxy-${channel}.profile"
    local apparmor_fwd="$profile_dir/apparmor-containai-log-forwarder-${channel}.profile"
    local seccomp_agent="$profile_dir/seccomp-containai-agent.json"
    local seccomp_proxy="$profile_dir/seccomp-containai-proxy.json"
    local seccomp_fwd="$profile_dir/seccomp-containai-log-forwarder.json"

    [[ -f "$seccomp_agent" ]] || die "Seccomp profile missing at $seccomp_agent"
    [[ -f "$apparmor_agent" ]] || die "AppArmor profile missing at $apparmor_agent"
    [[ -f "$seccomp_proxy" ]] || die "Seccomp proxy profile missing at $seccomp_proxy"
    [[ -f "$apparmor_proxy" ]] || die "AppArmor proxy profile missing at $apparmor_proxy"
    [[ -f "$seccomp_fwd" ]] || die "Seccomp log-forwarder profile missing at $seccomp_fwd"
    [[ -f "$apparmor_fwd" ]] || die "AppArmor log-forwarder profile missing at $apparmor_fwd"

    # Write manifest for runtime freshness checks
    local seccomp_hash apparmor_hash seccomp_proxy_hash apparmor_proxy_hash seccomp_fwd_hash apparmor_fwd_hash
    seccomp_hash=$(sha256sum "$seccomp_agent" | awk '{print $1}')
    apparmor_hash=$(sha256sum "$apparmor_agent" | awk '{print $1}')
    seccomp_proxy_hash=$(sha256sum "$seccomp_proxy" | awk '{print $1}')
    apparmor_proxy_hash=$(sha256sum "$apparmor_proxy" | awk '{print $1}')
    seccomp_fwd_hash=$(sha256sum "$seccomp_fwd" | awk '{print $1}')
    apparmor_fwd_hash=$(sha256sum "$apparmor_fwd" | awk '{print $1}')
    cat > "$profile_dir/containai-profiles.sha256" <<EOF
seccomp-containai-agent.json $seccomp_hash
apparmor-containai-agent-${channel}.profile $apparmor_hash
seccomp-containai-proxy.json $seccomp_proxy_hash
apparmor-containai-proxy-${channel}.profile $apparmor_proxy_hash
seccomp-containai-log-forwarder.json $seccomp_fwd_hash
apparmor-containai-log-forwarder-${channel}.profile $apparmor_fwd_hash
EOF

    if ! command -v apparmor_parser >/dev/null 2>&1; then
        die "AppArmor tools missing; install apparmor-utils and retry."
    fi
    local enabled_flag="/sys/module/apparmor/parameters/enabled"
    if [[ ! -r "$enabled_flag" ]] || ! grep -qi '^y' "$enabled_flag" 2>/dev/null; then
        die "AppArmor is disabled; enable AppArmor to continue."
    fi
    
    # Load pre-generated profiles directly (no runtime rendering needed)
    echo "Loading AppArmor profiles (channel: $channel)..."
    if ! apparmor_parser -r "$apparmor_agent"; then
        die "Failed to load AppArmor profile from $apparmor_agent"
    fi
    echo "  ✓ Loaded containai-agent-${channel}"
    
    if ! apparmor_parser -r "$apparmor_proxy"; then
        die "Failed to load AppArmor profile from $apparmor_proxy"
    fi
    echo "  ✓ Loaded containai-proxy-${channel}"
    
    if ! apparmor_parser -r "$apparmor_fwd"; then
        die "Failed to load AppArmor profile from $apparmor_fwd"
    fi
    echo "  ✓ Loaded containai-log-forwarder-${channel}"
}

if [[ "${1:-}" == "--verify" ]]; then
    enforce_security_profiles_strict "${2:-}"
fi
