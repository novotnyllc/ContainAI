# fn-36-rb7.9 Implement shell completion for cai docker

## Description
Add completion for `cai docker` that delegates to docker completion if available, setting `DOCKER_CONTEXT=containai-docker` and falling back gracefully.

## Acceptance
- [ ] `cai docker <TAB>` completes docker subcommands
- [ ] `cai docker ps <TAB>` works
- [ ] Sets `DOCKER_CONTEXT=containai-docker` before calling docker completion
- [ ] Graceful fallback if docker completion is unavailable
- [ ] Does not filter `--context` or `-u`

## Verification
- [ ] `cai docker <TAB>`
- [ ] `cai docker exec <TAB>` shows container names

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
