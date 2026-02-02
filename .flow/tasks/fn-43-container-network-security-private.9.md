# fn-43-container-network-security-private.9 Add rule cleanup to cai uninstall

## Description
TBD

## Acceptance
- [ ] TBD

## Done summary
Added network security iptables rule cleanup to cai uninstall. Rules are removed from DOCKER-USER chain during uninstall, with proper sudo credential priming for non-root users on interactive terminals.
## Evidence
- Commits: 98e813f259d40914751c95283e57de2a4bedf264
- Tests: shellcheck -x src/lib/uninstall.sh, shellcheck -x src/lib/network.sh
- PRs:
