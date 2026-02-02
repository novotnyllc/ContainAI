# fn-43-container-network-security-private.10 Harden sshd configuration

## Description
TBD

## Acceptance
- [ ] TBD

## Done summary
Hardened sshd configuration to prevent network security bypass via SSH tunneling. Added DisableForwarding yes to container sshd_config which comprehensively blocks TCP forwarding, X11 forwarding, agent forwarding, and tunnel devices.
## Evidence
- Commits: 94eba93, 50f7f4f, e4c0450
- Tests:
- PRs:
