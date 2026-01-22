# fn-10-vep.53 Add cgroup limits (memory, CPU) to container creation

## Description
Add cgroup limits (memory, CPU) to container creation.

**Size:** S
**Files:** lib/container.sh, lib/config.sh

## Approach

1. Add default limits to container creation:
   - `--memory=4g --memory-swap=4g` (no swap)
   - `--cpus=2`

2. Make limits configurable via config.toml:
   ```toml
   [container]
   memory = "4g"
   cpus = 2
   ```

3. Add `--stop-timeout 100` for systemd graceful shutdown

## Key context

- Practice-scout: Set memory-swap equal to memory to disable swap
- Practice-scout: 100s timeout needed for systemd shutdown
- Default 4GB/2CPU is reasonable for dev workloads
## Acceptance
- [ ] `--memory=4g --memory-swap=4g` added to docker run
- [ ] `--cpus=2` added to docker run
- [ ] `--stop-timeout 100` added to docker run
- [ ] Limits configurable via `[container]` config section
- [ ] `docker stats` shows limits applied
- [ ] Container stops gracefully (no SIGKILL)
## Done summary
Added cgroup resource limits to container creation: --memory=4g --memory-swap=4g --cpus=2 --stop-timeout=100. Limits are configurable via [container] config section (memory and cpus fields).
## Evidence
- Commits: 3fa10c5867d857056bf16794e3122deb4e73fe86
- Tests: manual verification of docker run args
- PRs: