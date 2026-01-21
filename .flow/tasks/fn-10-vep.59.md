# fn-10-vep.59 Implement cai import for hot-reload of config

## Description
Implement `cai import` for hot-reload of config into running container.

**Size:** M
**Files:** lib/import.sh (new or extend existing)

## Approach

1. `cai import /path/to/workspace` reloads config into running container
2. Hot-reload targets:
   - Environment variables from .env
   - Credentials (SSH keys, API tokens)
   - Git config
3. Uses SSH to inject changes (not docker exec)
4. Does NOT restart container

## Key context

- This is the "hot reload" mechanism - no need for `--fresh`
- Re-runs credential sync that normally happens at container start
- Validates container is running first
## Acceptance
- [ ] `cai import /path/to/workspace` command works
- [ ] Reloads .env variables into container
- [ ] Reloads credentials (SSH agent keys, tokens)
- [ ] Reloads git config
- [ ] Uses SSH (not docker exec)
- [ ] Clear output showing what was imported
- [ ] Errors if container not running
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
