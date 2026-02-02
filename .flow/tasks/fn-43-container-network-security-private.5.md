# fn-43-container-network-security-private.5 Implement cai0 bridge iptables rules for blocking

## Description

Create `src/lib/network.sh` with iptables management functions to block private IP ranges and cloud metadata endpoints on the ContainAI Docker bridge. The implementation must:

1. Block cloud metadata endpoints (AWS, ECS, Alibaba)
2. Block private IP ranges (RFC 1918 + link-local)
3. Allow host gateway for container-to-host communication
4. Support both standard host (cai0 bridge) and nested container (docker0) environments
5. Use comment markers for rule identification and cleanup

## Acceptance

- [x] `_cai_get_network_config()` returns bridge/gateway/subnet dynamically
- [x] `_cai_apply_network_rules()` adds iptables rules to block private ranges/metadata
- [x] `_cai_remove_network_rules()` removes the rules cleanly
- [x] `_cai_check_network_rules()` verifies rules are present
- [x] Works on host (cai0 / 172.30.0.1)
- [x] Designed for nested support (docker0 / varies)
- [x] Gateway allowed before blocks (rule order matters)
- [x] Alibaba metadata (100.100.100.200) also blocked
- [x] Uses iptables comment marker for rule identification

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
