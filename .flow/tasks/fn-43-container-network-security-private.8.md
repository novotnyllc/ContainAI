# fn-43-container-network-security-private.8 Add network verification to cai doctor

## Description
TBD

## Acceptance
- [ ] TBD

## Done summary
Added network security verification to cai doctor, including text output, JSON output, and fix capability via doctor fix command.
## Evidence
- Commits: 759ed3b112d9a44e956dc744fa16546efa01a4ed
- Tests: shellcheck -x src/lib/doctor.sh, shellcheck -x src/lib/network.sh, cai doctor, cai doctor --json, cai doctor fix --all
- PRs:
