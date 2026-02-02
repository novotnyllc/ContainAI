# fn-43-container-network-security-private.11 Add integration tests for network blocking

## Description
Add integration test suite for network security features including iptables rule verification, connectivity testing, and blocking validation. Tests run inside sysbox containers to verify the complete network security stack.

## Acceptance
- [x] Test script created at tests/integration/test-network-blocking.sh
- [x] Verifies iptables rules are present
- [x] Tests container can reach internet
- [x] Tests container can reach host gateway
- [x] Tests cloud metadata endpoints are blocked
- [x] Tests private IP ranges are blocked
- [x] Tests link-local range is blocked
- [x] Tests sshd hardening is applied
- [x] Follows existing integration test patterns
- [x] Uses shellcheck-clean bash

## Done summary
Created comprehensive integration test suite for network security at tests/integration/test-network-blocking.sh

## Evidence
- Commits:
- Tests: tests/integration/test-network-blocking.sh
- PRs:
