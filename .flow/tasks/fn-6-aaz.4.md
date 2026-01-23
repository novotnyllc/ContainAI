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
- Call `_containai_import_env "$ctx" "$volume" "$workspace" "$explicit_config" "$dry_run"` (config resolution is internal)
<!-- Updated by plan-sync: fn-6-aaz.3 implemented _containai_import_env with 5 params, handles config resolution internally -->
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
- [ ] Calls `_containai_import_env "$ctx" "$volume" "$workspace" "$explicit_config" "$dry_run"` (config resolved internally)
- [ ] Env import works even with `--data-volume` or `--no-excludes`
- [ ] `.env` written to correct volume (same daemon as container will use)
- [ ] Import summary includes env var count (keys only)
- [ ] `--dry-run` prints keys only, no volume write/modification
## Done summary
## Done Summary

Integrated env import with cai import command by:

1. **Sourced lib/env.sh** in containai.sh alongside other libs
2. **Added context selection to _containai_import_cmd** mirroring lib/container.sh's pattern:
   - Call `_containai_resolve_secure_engine_context` for config override
   - Call `_cai_select_context` with `DOCKER_CONTEXT= DOCKER_HOST=` prefix
   - Fall back to default context on failure with warning
3. **Created _containai_docker_cmd helper** that wraps docker with context and env neutralization
4. **Applied context to ALL docker operations in lib/import.sh**:
   - Volume inspect/create
   - Rsync containers
   - Transform containers
   - Orphan cleanup
   - New .env helper via `_containai_import_env`
5. **Called _containai_import_env** after dotfile sync with 5 params: ctx, volume, workspace, explicit_config, dry_run
6. **Dry-run support**: prints selected context and keys that would be imported
## Evidence
- Commits: c2cb874
- Tests: Manual verification of context flow
- PRs:
