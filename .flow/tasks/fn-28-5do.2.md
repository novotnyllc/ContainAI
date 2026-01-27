# fn-28-5do.2 Update prompts to stop containers instead of aborting

## Description

Change `cai update` behavior when containers are running. Currently it aborts with a message suggesting `--stop-containers`. Instead, it should interactively prompt the user to confirm stopping containers and then proceed.

**Size:** S
**Files:** `src/lib/update.sh`

## Approach

1. Find the container-running detection logic in `_cai_update_linux_wsl2()`
2. When containers detected and update needed:
   - Show which containers are running (current behavior, keep)
   - Add interactive prompt: "Stop containers and continue? [y/N]"
   - On "y", call the container stop function and proceed with update
   - On "n"/timeout/non-interactive, abort as current
3. Keep `--stop-containers` flag for CI/non-interactive use

## Key context

- Current abort logic added in fn-27-hbi.1
- Uses `_containai_list_containers_for_context()` to detect running containers
- Uses `_containai_stop_all()` to stop containers (from `src/lib/container.sh:2352`)
- Need to check if stdin is a TTY for interactive prompt (`[[ -t 0 ]]`)

## Acceptance

- [x] `cai update` prompts interactively when containers running
- [x] Prompt shows container names/IDs
- [x] "y" response stops containers and proceeds with update
- [x] "n" or Enter aborts cleanly
- [x] Non-interactive (no TTY) still aborts with message
- [x] `--stop-containers` flag still works for scripted use
- [x] shellcheck passes

## Done summary
Added interactive prompt "Stop containers and continue? [y/N]" when cai update detects running containers during updates, replacing the hard abort. Prompt honors --force and --stop-containers flags for non-interactive use.
## Evidence
- Commits: bbf7fbf704b169fb44fceeb25f5e5a8c5d09ed74
- Tests: shellcheck -x src/lib/update.sh, bash -n src/lib/update.sh
- PRs:
