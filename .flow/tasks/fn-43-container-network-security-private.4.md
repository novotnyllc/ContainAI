# fn-43-container-network-security-private.4 Integrate with setup/doctor/uninstall

## Description
Integrate network rules with setup, doctor, and uninstall flows.

**Size:** M
**Files:** `src/lib/setup.sh`, `src/lib/doctor.sh`, `src/lib/uninstall.sh`, `src/lib/network.sh`

## Approach

### Setup Integration

Add to `cai setup`:
```bash
_cai_setup_network_rules() {
    _cai_step "Configuring network security rules"

    if _cai_is_macos; then
        limactl shell "$_CAI_LIMA_VM_NAME" -- sudo bash -c "$(_cai_network_rules_script apply)"
    else
        sudo bash -c "$(_cai_network_rules_script apply)"
    fi
}
```

### Doctor Integration

Add network rules check to `cai doctor`:
```bash
_cai_doctor_network_rules() {
    local bridge gateway
    read -r bridge gateway _ <<< "$(_cai_get_network_config)"

    # Check if rules exist
    if iptables -C FORWARD -i "$bridge" -d 169.254.0.0/16 -j DROP 2>/dev/null; then
        printf '  %-50s %s\n' "Network security rules" "[OK]"
    else
        printf '  %-50s %s\n' "Network security rules" "[WARN] missing"
    fi
}
```

### Uninstall Integration

Add to `cai uninstall` - **remove all rules on all platforms**:
```bash
_cai_uninstall_network_rules() {
    _cai_step "Removing network security rules"

    read -r bridge gateway _ <<< "$(_cai_get_network_config)"

    local rules=(
        "-D FORWARD -i $bridge -d $gateway -j ACCEPT"
        "-D FORWARD -i $bridge -d 10.0.0.0/8 -j DROP"
        "-D FORWARD -i $bridge -d 172.16.0.0/12 -j DROP"
        "-D FORWARD -i $bridge -d 192.168.0.0/16 -j DROP"
        "-D FORWARD -i $bridge -d 169.254.0.0/16 -j DROP"
        "-D FORWARD -i $bridge -d 100.100.100.200 -j DROP"
    )

    for rule in "${rules[@]}"; do
        if _cai_is_macos; then
            limactl shell "$_CAI_LIMA_VM_NAME" -- sudo iptables $rule 2>/dev/null || true
        else
            sudo iptables $rule 2>/dev/null || true
        fi
    done

    _cai_ok "Network security rules removed"
}
```

### Platform-aware cleanup

| Platform | Cleanup location |
|----------|------------------|
| Linux | Host iptables |
| Lima/macOS | Inside Lima VM |
| WSL2 | Inside WSL |
| Nested | Inside outer container |

## Key context

- Uninstall already cleans up bridge, socket, service
- Rules must be removed even if bridge is already down
- Use `-D` (delete) not `-F` (flush) to avoid affecting other rules
- Ignore errors (rule may not exist)
## Acceptance
- [ ] `cai setup` adds network rules
- [ ] `cai doctor` checks rules present
- [ ] `cai doctor` shows warning if missing
- [ ] `cai uninstall` removes ALL iptables rules
- [ ] Uninstall works on Linux host
- [ ] Uninstall works on Lima/macOS (removes from VM)
- [ ] Uninstall works on WSL2
- [ ] Uninstall works when nested
- [ ] No errors if rules don't exist
- [ ] No leftover rules after uninstall
## Done summary
Integrated network security rules with setup, doctor, and uninstall flows across all platforms (Linux, WSL2, macOS/Lima). Doctor now checks iptables rules on all platforms with appropriate recommendations. Uninstall properly removes rules from Lima VM with actionable warnings if VM is not running.
## Evidence
- Commits: 93ca8409c7f4d58bc6f2a33e7cfc380ad424ce70, ebc12e4c5b5c3c6e15dd03b97dc74ad5ffc94c98, d4a48291850428c13dd8dd30d8b6531d2b496ba0
- Tests: bash -n src/lib/uninstall.sh, bash -n src/lib/doctor.sh, bash -n src/lib/network.sh, shellcheck -x src/lib/*.sh
- PRs:
