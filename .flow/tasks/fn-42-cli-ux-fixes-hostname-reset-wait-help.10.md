# fn-42-cli-ux-fixes-hostname-reset-wait-help.10 Add hostname flag to container creation

## Description
TBD

## Acceptance
- [ ] TBD

## Done summary
Added --hostname flag to docker run command in container creation, with RFC 1123 sanitization to handle container names that may contain underscores or other hostname-invalid characters.
## Evidence
- Commits: ebe7b53, 9642ade
- Tests: shellcheck -x src/lib/container.sh
- PRs:
