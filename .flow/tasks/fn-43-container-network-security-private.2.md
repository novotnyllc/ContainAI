# fn-43-container-network-security-private.2 Platform support: Lima/macOS and WSL2

## Description
Ensure network rules work across all platforms including nested execution.

**Size:** M
**Files:** `src/lib/network.sh`, `src/lib/setup.sh`

## Approach

### Platform Matrix

| Platform        | Bridge  | Where rules apply      | Notes                   |
|-----------------|---------|------------------------|-------------------------|
| Linux host      | cai0    | Host iptables          | Standard                |
| Lima/macOS      | cai0    | Inside Lima VM         | Run via `limactl shell` |
| WSL2            | cai0    | Inside WSL             | Direct iptables         |
| Docker Desktop  | cai0    | Inside VM              | May need VM access      |
| Nested (in cai) | docker0 | Inside outer container | Use detected config     |

### Lima/macOS Implementation

```bash
if _cai_is_macos; then
    # Apply rules inside Lima VM
    limactl shell "$_CAI_LIMA_VM_NAME" -- sudo iptables ...
fi
```

### WSL2 Implementation

```bash
if _cai_is_wsl; then
    # Direct iptables in WSL (has its own network namespace)
    sudo iptables ...
fi
```

### Nested Detection

```bash
if _cai_is_container; then
    # We're inside a cai container
    # iptables applies to inner Docker's bridge
    # May need NET_ADMIN capability
fi
```

## Key context

- Lima VM name: `$_CAI_LIMA_VM_NAME` (usually `containai-docker`)
- WSL detection: `_cai_is_wsl()`
- Nested detection: `_cai_is_container()`
## Acceptance
- [ ] Works on native Linux
- [ ] Works on macOS via Lima (rules inside VM)
- [ ] Works on WSL2
- [ ] Works when nested inside cai container
- [ ] Correct bridge/gateway used per platform
- [ ] iptables accessible on all platforms
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
