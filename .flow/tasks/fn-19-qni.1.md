# fn-19-qni.1 Implement cai gc command

## Description
Create a new `cai gc` command to prune stale ContainAI-managed containers and images. This provides a way to reclaim disk space from old development environments without affecting active work.

**Size:** M
**Files:** `src/lib/gc.sh` (new), `src/containai.sh` (wire command)

## Approach

1. Create `src/lib/gc.sh` following the pattern of other lib modules (guard re-sourcing, local variables, return codes)
2. Implement `_containai_gc_cmd()` main entry point
3. Add `gc` subcommand handling in `src/containai.sh` (follow `stop` command pattern at line 2065)

### Core logic

- Query containers with `docker ps -a --filter label=containai.managed=true`
- Filter by age using container created timestamp vs current time
- Exclude running containers (status != exited)
- Exclude containers with `containai.keep=true` label
- For `--images`: Also prune images with `docker image prune --filter label=containai.managed=true`

### Reuse points

- Use `_cai_get_docker_command()` from `src/lib/container.sh:186-234` for context-aware Docker
- Use `_cai_info`, `_cai_warn`, `_cai_error` from `src/lib/core.sh` for logging
- Follow container removal pattern from `_cai_uninstall_containers()` at `src/lib/uninstall.sh:226-375`

## Key context

Docker filter syntax for age: `--filter "until=168h"` (7 days = 168 hours). Docker uses Go duration strings.

To get container age in bash:
```bash
created=$(docker inspect -f '{{.Created}}' "$container")
created_epoch=$(date -d "$created" +%s)
age_hours=$(( ($(date +%s) - created_epoch) / 3600 ))
```
## Acceptance
- [ ] `cai gc` shows candidates and prompts for confirmation
- [ ] `cai gc --dry-run` lists candidates without removing
- [ ] `cai gc --force` skips confirmation
- [ ] `cai gc --age 7d` only prunes containers older than 7 days
- [ ] `cai gc --images` also prunes unused images
- [ ] Running containers are never pruned
- [ ] Containers with `containai.keep=true` label are protected
- [ ] Only ContainAI-managed resources (label) are affected
- [ ] Passes `shellcheck -x src/lib/gc.sh`
## Done summary
Superseded - merged into fn-34-fk5
## Evidence
- Commits:
- Tests:
- PRs:
