# fn-6-aaz.4 Integrate env import with cai import command

## Description
Wire up env var import into `cai import` with full context plumbing for ALL docker commands.

**Size:** M  
**Files:** `agent-sandbox/lib/import.sh`, `agent-sandbox/containai.sh`

## Approach

- Source `lib/env.sh` in containai.sh
- **Add context selection to _containai_import_cmd** (mirror lib/container.sh's _cai_select_context)
- **Create docker_cmd or pass ctx** to ALL docker invocations in lib/import.sh
- Apply context to: volume ops, rsync, transforms, orphan cleanup, AND .env helper
- Neutralize DOCKER_CONTEXT/DOCKER_HOST when default context intended
- Call dedicated `_containai_resolve_env_config()` (independent of volume/excludes)
## Approach

- Source `lib/env.sh` in containai.sh alongside other libs
- **CRITICAL: Make context selection first-class for cai import**
  - Reuse context-selection logic from `lib/container.sh`
  - Explicitly neutralize `DOCKER_CONTEXT`/`DOCKER_HOST` when default context intended
  - Pass context to ALL docker commands: volume ops, rsync, transforms, orphan cleanup, .env helper
- Call env import after dotfile sync with context parameter
- Dry-run: print keys only, no volume write
## Approach

- Source `lib/env.sh` in containai.sh alongside other libs
- Call `_containai_resolve_env_config()` in import flow
- Call `_containai_import_env()` after dotfile sync
- **Use correct Docker context** for volume operations:
  - Reuse context-selection logic from `lib/container.sh`
  - Pass context to env import function
  - Run `docker --context "$ctx"` for all volume ops
- **Dry-run support**: Print what would be imported, no volume write
## Approach

- Source `lib/env.sh` in containai.sh alongside other libs
- Call `_containai_resolve_env_config()` in import flow
- Call `_containai_import_env()` after dotfile sync
- Pass volume name and workspace to env import function
- Use rsync container pattern (network=none) for writing to volume
## Acceptance
- [ ] `lib/env.sh` sourced in containai.sh
- [ ] **Context selection added to _containai_import_cmd** (mirrors container.sh)
- [ ] **docker_cmd or ctx parameter passed to ALL docker calls in import.sh**
- [ ] Context applied to: volume inspect/create, rsync, transforms, orphan cleanup
- [ ] Context applied to: new .env helper
- [ ] DOCKER_CONTEXT/DOCKER_HOST neutralized for default context
- [ ] Env config resolved via dedicated `_containai_resolve_env_config()`
- [ ] Env config resolved even with `--data-volume` or `--no-excludes`
- [ ] `.env` written to correct volume (same daemon as container will use)
- [ ] Import summary includes env var count (keys only)
- [ ] `--dry-run` prints keys only, no volume write/modification
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
