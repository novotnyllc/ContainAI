# fn-43 Container Network Security

## Overview

Secure container networking: block private IP ranges and cloud metadata while allowing host and internet access. Uses ContainAI's dedicated `cai0` bridge for scoped iptables rules.

## Scope

### In Scope
- Block cloud metadata endpoints (169.254.169.254, etc.)
- Block private IP ranges (10/8, 172.16/12, 192.168/16)
- Allow host gateway access
- Allow internet access
- Platform support: Linux, macOS/Lima, WSL2
- **Nested container support** (running inside a cai container)
- sshd hardening (no remote forwards, no tunnels)
- Setup/doctor/uninstall integration

### Out of Scope
- VPN/tunnel configuration
- Custom firewall rules per-workspace

## Approach

### Network Policy

**Allow:**
- Host gateway (bridge gateway IP, `host.docker.internal`)
- Internet (default route)

**Block:**
- Cloud metadata: `169.254.169.254`, `169.254.170.2`, `100.100.100.200`
- Private ranges: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
- Link-local: `169.254.0.0/16`

### Standard Host Implementation (cai0 bridge)

```bash
# Allow host gateway first
iptables -I FORWARD -i cai0 -d 172.30.0.1 -j ACCEPT

# Block private/link-local ranges
iptables -A FORWARD -i cai0 -d 10.0.0.0/8 -j DROP
iptables -A FORWARD -i cai0 -d 172.16.0.0/12 -j DROP
iptables -A FORWARD -i cai0 -d 192.168.0.0/16 -j DROP
iptables -A FORWARD -i cai0 -d 169.254.0.0/16 -j DROP
```

### Nested Container Considerations

When running inside a cai container (`_cai_is_container` returns true):

1. **Different bridge**: Inner Docker uses `docker0` or custom bridge, not `cai0`
2. **Different subnet**: May use default 172.17.0.0/16 or other range
3. **Different gateway**: Need to detect actual bridge gateway IP
4. **iptables access**: May need `--cap-add=NET_ADMIN` or use runc instead of sysbox-runc

**Detection:**
```bash
if _cai_is_container; then
    # Get inner Docker bridge info
    bridge_name=$(docker network inspect bridge -f '{{.Options.com.docker.network.bridge.name}}' 2>/dev/null || echo "docker0")
    gateway_ip=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)
    subnet=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
fi
```

**Rules adjustment:**
- Use detected `$bridge_name` instead of hardcoded `cai0`
- Allow detected `$gateway_ip` instead of `172.30.0.1`
- Ensure our own subnet is allowed for container-to-container within the inner Docker

### Platform Notes

| Platform | Bridge | Gateway | Notes |
|----------|--------|---------|-------|
| Linux host | cai0 | 172.30.0.1 | Standard setup |
| Lima/macOS | cai0 (in VM) | 172.30.0.1 | Rules inside Lima VM |
| WSL2 | cai0 | 172.30.0.1 | Rules inside WSL |
| Nested (in cai) | docker0 | varies | Detect dynamically |

## Quick commands

```bash
# Check if nested
_cai_is_container && echo "nested" || echo "host"

# Verify rules (adjust bridge name)
sudo iptables -L FORWARD -n | grep cai0

# Test metadata blocked
cai shell
curl -s --connect-timeout 2 http://169.254.169.254/ && echo "FAIL" || echo "OK"
```

## Acceptance

- [ ] Container can reach internet
- [ ] Container can reach host via gateway
- [ ] Private ranges blocked
- [ ] Cloud metadata blocked
- [ ] Works on Linux, macOS/Lima, WSL2
- [ ] **Works when nested inside a cai container**
- [ ] Dynamically detects bridge/gateway when nested
- [ ] `cai setup` adds rules
- [ ] `cai doctor` verifies rules
- [ ] `cai uninstall` removes rules
- [ ] sshd hardened

## References

- Bridge: `cai0` at `src/lib/docker.sh:317`
- Nested detection: `_cai_is_container()` in `src/lib/docker.sh`
- Inner Docker uses runc (not sysbox) per `src/lib/container.sh:1301-1304`
