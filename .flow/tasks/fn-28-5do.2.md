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

- [ ] `cai update` prompts interactively when containers running
- [ ] Prompt shows container names/IDs
- [ ] "y" response stops containers and proceeds with update
- [ ] "n" or Enter aborts cleanly
- [ ] Non-interactive (no TTY) still aborts with message
- [ ] `--stop-containers` flag still works for scripted use
- [ ] shellcheck passes
