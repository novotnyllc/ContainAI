# fn-43-container-network-security-private.6 Add nested container detection and dynamic bridge handling

## Description

Enhance `src/lib/network.sh` to properly handle nested container environments (running ContainAI inside a ContainAI sandbox or other container). The implementation:

1. Detects nested container environments and distinguishes host vs nested mode
2. Checks if iptables is functional in nested environments (Sysbox vs runc)
3. Skips network rules gracefully in Sysbox containers (where isolation is at outer level)
4. Verifies CAP_NET_ADMIN capability before attempting iptables operations
5. Improves error messages with context-specific guidance
6. Enhances bridge detection with fallbacks when Docker isn't running yet

## Acceptance

- [x] `_cai_is_nested_container()` detects nested container environment
- [x] `_cai_nested_iptables_supported()` checks iptables capability in nested env
- [x] Sysbox containers gracefully skip network rules (isolation at outer level)
- [x] runc containers without CAP_NET_ADMIN get clear error message
- [x] `_cai_get_network_config()` sets `_CAI_NETWORK_CONFIG_ENV` for caller awareness
- [x] `_cai_apply_network_rules()` handles nested environment scenarios
- [x] `_cai_remove_network_rules()` handles nested environment scenarios
- [x] `_cai_network_doctor_status()` returns "skipped" for Sysbox containers
- [x] Error messages include nested-specific guidance (e.g., "systemctl start docker")
- [x] shellcheck passes

## Done summary
Enhanced src/lib/network.sh with nested container detection and dynamic bridge handling. Added _cai_is_nested_container() and _cai_nested_iptables_supported() functions to detect nested environments and check iptables capability. Sysbox containers gracefully skip network rules (outer isolation), runc containers verify CAP_NET_ADMIN capability, and error messages provide environment-specific guidance. Fixed IP parsing to handle multiple addresses correctly.
## Evidence
- Commits: 428430fb10f4bcfc0df1b94ba6d08e6c9acb1be0, 32108ab5f69083ecc350dd3de993cc0de260c8c8
- Tests: shellcheck -x src/lib/network.sh, bash -n src/lib/network.sh
- PRs:
