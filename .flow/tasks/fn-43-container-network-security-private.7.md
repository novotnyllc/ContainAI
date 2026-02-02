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
Integrated network security rules with `cai setup` for all platforms:
- Linux: Calls `_cai_apply_network_rules()` as step 12 after Docker is verified
- WSL2: Calls `_cai_apply_network_rules()` as step 14 after Docker is verified
- macOS/Lima: Runs inline script via `limactl shell` to apply rules inside the VM
- Nested containers: Calls `_cai_apply_network_rules()` which gracefully skips for Sysbox containers (outer provides isolation)

All integrations are non-fatal (warnings only) to avoid blocking setup if rules fail to apply. Dry-run mode is fully supported.

## Evidence
- Commits: (pending)
- Tests: shellcheck -x src/lib/setup.sh, bash -n src/lib/setup.sh
- PRs:
