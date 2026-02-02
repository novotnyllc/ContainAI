# fn-43-container-network-security-private.7 Integrate network rules with cai setup

## Description

Integrate `_cai_apply_network_rules()` into the `cai setup` flow for all platforms. After Docker is running and the bridge is ready, setup should apply iptables rules to block private IP ranges and cloud metadata endpoints.

Platform-specific integration:
- `_cai_setup_linux()`: Call after isolated Docker is verified running
- `_cai_setup_wsl2()`: Call after isolated Docker is verified running
- `_cai_setup_macos()`: For Lima VMs, network rules are applied inside the VM (if needed)
- `_cai_setup_nested()`: Call `_cai_apply_network_rules()` which handles Sysbox detection and skips gracefully

The network.sh module already handles:
- Nested container detection (Sysbox skips rules, outer provides isolation)
- CAP_NET_ADMIN capability checks
- Dry-run mode support

## Acceptance
- [x] `_cai_setup_linux()` calls `_cai_apply_network_rules()` after Docker is running
- [x] `_cai_setup_wsl2()` calls `_cai_apply_network_rules()` after Docker is running
- [x] `_cai_setup_nested()` calls `_cai_apply_network_rules()` (Sysbox containers skip gracefully)
- [x] Dry-run mode shows what rules would be applied
- [x] Setup continues even if network rules fail (non-fatal warning)
- [x] shellcheck passes

## Done summary
Integrated network security rules with cai setup for all platforms:
- Linux: Calls _cai_apply_network_rules() after Docker is verified (step 12)
- WSL2: Calls _cai_apply_network_rules() after Docker is verified (step 14)
- macOS/Lima: Runs inline script via limactl shell to apply rules in VM (step 8)
- Nested containers: Calls _cai_apply_network_rules() which skips gracefully for Sysbox containers

All integrations are non-fatal warnings and support dry-run mode.
## Evidence
- Commits: 3946d9d41784325b63a5aab60a32ac5d4ba55520
- Tests: shellcheck -x src/lib/setup.sh, bash -n src/lib/setup.sh
- PRs:
