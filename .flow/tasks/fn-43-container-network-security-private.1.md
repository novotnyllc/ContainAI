# fn-43-container-network-security-private.1 Implement iptables rules for cai0 bridge

## Description
Implement iptables rules to block private ranges and metadata, with dynamic detection for nested containers.

**Size:** M
**Files:** `src/lib/network.sh` (new), `src/lib/setup.sh`

## Approach

### 1. Create network helper functions

```bash
# Detect bridge name and gateway
_cai_get_network_config() {
    local bridge gateway subnet

    if _cai_is_container; then
        # Nested: use inner Docker's bridge
        bridge=$(docker network inspect bridge -f '{{.Options.com.docker.network.bridge.name}}' 2>/dev/null || echo "docker0")
        gateway=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)
        subnet=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
    else
        # Host: use cai0
        bridge="cai0"
        gateway="172.30.0.1"
        subnet="172.30.0.0/16"
    fi

    printf '%s %s %s' "$bridge" "$gateway" "$subnet"
}
```

### 2. Apply rules dynamically

```bash
_cai_apply_network_rules() {
    read -r bridge gateway subnet <<< "$(_cai_get_network_config)"

    # Allow gateway
    iptables -I FORWARD -i "$bridge" -d "$gateway" -j ACCEPT

    # Block private ranges
    iptables -A FORWARD -i "$bridge" -d 10.0.0.0/8 -j DROP
    iptables -A FORWARD -i "$bridge" -d 172.16.0.0/12 -j DROP
    iptables -A FORWARD -i "$bridge" -d 192.168.0.0/16 -j DROP
    iptables -A FORWARD -i "$bridge" -d 169.254.0.0/16 -j DROP
}
```

### 3. Remove rules (for uninstall)

```bash
_cai_remove_network_rules() {
    read -r bridge gateway subnet <<< "$(_cai_get_network_config)"

    iptables -D FORWARD -i "$bridge" -d "$gateway" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$bridge" -d 10.0.0.0/8 -j DROP 2>/dev/null || true
    # ... etc
}
```

## Key context

- `_cai_is_container()` detects nested execution
- Inner Docker uses runc (not sysbox)
- Bridge name varies: `cai0` on host, `docker0` when nested
## Acceptance
- [ ] Network config detected dynamically (bridge, gateway, subnet)
- [ ] Works on host (cai0 / 172.30.0.1)
- [ ] Works when nested (docker0 / varies)
- [ ] Private ranges blocked (10/8, 172.16/12, 192.168/16)
- [ ] Link-local/metadata blocked (169.254.0.0/16)
- [ ] Gateway allowed
- [ ] Rules removable for uninstall
## Done summary
Task already completed by tasks fn-43-container-network-security-private.5 and fn-43-container-network-security-private.6. The src/lib/network.sh file implements all acceptance criteria: dynamic bridge/gateway/subnet detection via _cai_get_network_config(), host mode (cai0), nested mode (docker0), private range blocking, metadata blocking, gateway allow rules, and rule removal for uninstall.
## Evidence
- Commits: f34dd75a7f2fa1613fcc40a457d3ca50f58ca53f, 428430fb10f4bcfc0df1b94ba6d08e6c9acb1be0, 32108ab5f69083ecc350dd3de993cc0de260c8c8
- Tests: shellcheck -x src/lib/network.sh
- PRs:
