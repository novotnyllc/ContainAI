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
    local seccomp_profile="$profile_dir/seccomp-containai-agent.json"
    local apparmor_profile="$profile_dir/apparmor-containai-agent.profile"

    [[ -f "$seccomp_profile" ]] || die "Seccomp profile missing at $seccomp_profile"
    [[ -f "$apparmor_profile" ]] || die "AppArmor profile missing at $apparmor_profile"

    # Write manifest for runtime freshness checks
    local seccomp_hash apparmor_hash
    seccomp_hash=$(sha256sum "$seccomp_profile" | awk '{print $1}')
    apparmor_hash=$(sha256sum "$apparmor_profile" | awk '{print $1}')
    printf "seccomp-containai-agent.json %s\napparmor-containai-agent.profile %s\n" \
        "$seccomp_hash" "$apparmor_hash" > "$profile_dir/containai-profiles.sha256"

    # AppArmor is mandatory; require parser and enabled kernel flag.
    if ! command -v apparmor_parser >/dev/null 2>&1; then
        die "AppArmor tools missing; install apparmor-utils and retry."
    fi
    local enabled_flag="/sys/module/apparmor/parameters/enabled"
    if [[ ! -r "$enabled_flag" ]] || ! grep -qi '^y' "$enabled_flag" 2>/dev/null; then
        die "AppArmor is disabled; enable AppArmor to continue."
    fi
    if ! apparmor_parser -r "$apparmor_profile"; then
        die "Failed to load AppArmor profile 'containai' via apparmor_parser."
    fi
}
