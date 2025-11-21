#!/usr/bin/env bash
# Strict security enforcement helpers (privileged path).
# Requires common-functions.sh to be sourced beforehand.
set -euo pipefail

# Enforce existence and loading of security profiles at the installed root.
# Arguments:
#   1: install root (release directory that already contains host/profiles)
enforce_security_profiles_strict() {
    local install_root="$1"
    local profile_dir="$install_root/host/profiles"
    local seccomp_agent="$profile_dir/seccomp-containai-agent.json"
    local apparmor_agent="$profile_dir/apparmor-containai-agent.profile"
    local seccomp_proxy="$profile_dir/seccomp-containai-proxy.json"
    local apparmor_proxy="$profile_dir/apparmor-containai-proxy.profile"
    local seccomp_fwd="$profile_dir/seccomp-containai-log-forwarder.json"
    local apparmor_fwd="$profile_dir/apparmor-containai-log-forwarder.profile"

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
apparmor-containai-agent.profile $apparmor_hash
seccomp-containai-proxy.json $seccomp_proxy_hash
apparmor-containai-proxy.profile $apparmor_proxy_hash
seccomp-containai-log-forwarder.json $seccomp_fwd_hash
apparmor-containai-log-forwarder.profile $apparmor_fwd_hash
EOF

    # AppArmor is mandatory; require parser and enabled kernel flag.
    if ! command -v apparmor_parser >/dev/null 2>&1; then
        die "AppArmor tools missing; install apparmor-utils and retry."
    fi
    local enabled_flag="/sys/module/apparmor/parameters/enabled"
    if [[ ! -r "$enabled_flag" ]] || ! grep -qi '^y' "$enabled_flag" 2>/dev/null; then
        die "AppArmor is disabled; enable AppArmor to continue."
    fi
    if ! apparmor_parser -r "$apparmor_agent"; then
        die "Failed to load AppArmor profile 'containai' via apparmor_parser."
    fi
    if ! apparmor_parser -r "$apparmor_proxy"; then
        die "Failed to load AppArmor profile 'containai-proxy' via apparmor_parser."
    fi
    if ! apparmor_parser -r "$apparmor_fwd"; then
        die "Failed to load AppArmor profile 'containai-log-forwarder' via apparmor_parser."
    fi
}

if [[ "${1:-}" == "--verify" ]]; then
    enforce_security_profiles_strict "${2:-}"
fi
