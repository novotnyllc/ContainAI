#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
# verify-sysbox.sh - Kernel-level sysbox verification
#
# Threat model: Defense-in-depth. The wrapper enforces --runtime=sysbox-runc
# at launch, and this script verifies kernel-level sysbox indicators.
# The sysboxfs check is MANDATORY (sysbox-unique, cannot be faked).
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

verify_sysbox() {
    local passed=0
    local sysboxfs_found=false

    printf 'ContainAI Sysbox Verification\n'
    printf '═══════════════════════════════\n'

    # MANDATORY CHECK: Sysbox-fs mounts (sysbox-unique, cannot be faked)
    # This check MUST pass - it's the definitive sysbox indicator
    if grep -qE 'sysboxfs|fuse\.sysbox' /proc/mounts 2>/dev/null; then
        sysboxfs_found=true
        ((passed++))
        printf '  ✓ Sysboxfs: mounted (REQUIRED)\n'
    else
        printf '  ✗ Sysboxfs: not found (REQUIRED)\n'
    fi

    # Check 2: UID mapping (sysbox maps 0 → high UID)
    if [[ -f /proc/self/uid_map ]]; then
        if ! grep -qE '^[[:space:]]*0[[:space:]]+0[[:space:]]' /proc/self/uid_map; then
            ((passed++))
            printf '  ✓ UID mapping: sysbox user namespace\n'
        else
            printf '  ✗ UID mapping: 0→0 (not sysbox)\n'
        fi
    fi

    # Check 3: Nested user namespace (sysbox allows, docker blocks)
    if unshare --user --map-root-user true 2>/dev/null; then
        ((passed++))
        printf '  ✓ Nested userns: allowed\n'
    else
        printf '  ✗ Nested userns: blocked\n'
    fi

    # Check 4: CAP_SYS_ADMIN works (sysbox userns)
    local testdir
    testdir=$(mktemp -d)
    if mount -t tmpfs none "$testdir" 2>/dev/null; then
        umount "$testdir" 2>/dev/null
        ((passed++))
        printf '  ✓ Capabilities: CAP_SYS_ADMIN works\n'
    else
        printf '  ✗ Capabilities: mount denied\n'
    fi
    rmdir "$testdir" 2>/dev/null || true

    printf '\nPassed: %d checks\n' "$passed"

    # HARD REQUIREMENT: sysboxfs MUST be present
    # This is the sysbox-unique predicate that cannot be faked
    if [[ "$sysboxfs_found" != "true" ]]; then
        printf 'FAIL: sysboxfs not detected (mandatory for sysbox)\n' >&2
        return 1
    fi

    # Also require at least 2 other checks for defense-in-depth
    [[ $passed -ge 3 ]]
}

if ! verify_sysbox; then
    cat >&2 <<'ERROR'

╔═══════════════════════════════════════════════════════════════════╗
║  ContainAI: NOT running in sysbox                                 ║
║                                                                   ║
║  The wrapper should enforce --runtime=sysbox-runc at launch.      ║
║  If you see this, the devcontainer was started incorrectly.       ║
║                                                                   ║
║  To fix:                                                          ║
║    1. Install ContainAI: curl -fsSL https://containai.dev | sh    ║
║    2. Run: cai setup                                              ║
║    3. Ensure VS Code uses cai-docker wrapper                      ║
║    4. Reopen this devcontainer                                    ║
╚═══════════════════════════════════════════════════════════════════╝
ERROR
    exit 1
fi
printf '✓ Running in sysbox sandbox\n'
