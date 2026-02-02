# fn-43-container-network-security-private.3 Harden sshd config

## Description
Harden the sshd configuration in the container to prevent network security bypass via SSH port forwarding.

**Note:** This task is a duplicate of fn-43-container-network-security-private.10, which has already been completed.

## Acceptance
- [x] sshd config includes DisableForwarding yes (blocks TCP, X11, agent forwarding, and tunnel devices)
- [x] Changes are present in Dockerfile.base

## Done summary
This task is a duplicate of fn-43-container-network-security-private.10. The sshd hardening work was already completed in task 10, which added `DisableForwarding yes` to the container's sshd_config in `src/container/Dockerfile.base`. This setting comprehensively blocks TCP forwarding, X11 forwarding, agent forwarding, and tunnel devices, preventing network security bypass via SSH tunneling.
## Evidence
- Commits: 94eba93, 50f7f4f, e4c0450
- Tests: tests/integration/test-network-blocking.sh
- PRs:
