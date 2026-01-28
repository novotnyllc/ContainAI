# fn-36-rb7.14 Fix cai docker passthrough for all commands

## Description
Ensure `cai docker` consistently injects the ContainAI context and handles exec user defaults, while allowing user overrides.

## Acceptance
- [ ] `cai docker ps` works
- [ ] `cai docker logs <container>` works
- [ ] `cai docker exec <container> <cmd>` works and injects `-u agent` for containai containers
- [ ] `cai docker inspect <container>` works
- [ ] `cai docker rm <container>` works
- [ ] User-supplied `--context` overrides auto-injection
- [ ] User-supplied `-u` overrides exec user injection

## Verification
- [ ] `cai docker logs containai-*`
- [ ] `cai docker exec containai-* whoami`

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
