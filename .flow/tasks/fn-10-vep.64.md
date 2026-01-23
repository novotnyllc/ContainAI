# fn-10-vep.64 Implement cai ssh cleanup command

## Description
Implement `cai ssh cleanup` command to remove stale SSH configurations and known_hosts entries for containers that no longer exist.

**Size:** S
**Files:** lib/ssh.sh, containai.sh

## Approach

1. `cai ssh cleanup` command:
   - Scan `~/.ssh/containai.d/*.conf` for all containai SSH configs
   - For each config, check if corresponding container exists
   - Remove configs for non-existent containers
   - Clean corresponding known_hosts entries

2. Auto-cleanup integration:
   - Call cleanup logic when container is removed
   - Call cleanup logic on `cai stop --remove`
   - Optionally run on `cai doctor --fix`

3. Output:
   - List configs being removed
   - Show before/after count
   - Dry-run mode with `--dry-run`

## Key context

- SSH configs are in `~/.ssh/containai.d/containai-*.conf`
- known_hosts entries are in `~/.config/containai/known_hosts`
- Container names follow pattern `containai-<hash>`
## Acceptance
- [ ] `cai ssh cleanup` removes stale SSH configs
- [ ] Removes known_hosts entries for non-existent containers
- [ ] Shows what was cleaned
- [ ] `--dry-run` shows what would be cleaned without doing it
- [ ] Auto-cleanup on container removal
- [ ] No errors if nothing to clean
## Done summary
Implemented `cai ssh cleanup` command to remove stale SSH configs for non-existent containers, with --dry-run support. Also added `cai stop --remove` flag for auto-cleanup during container removal.
## Evidence
- Commits: 695cb6e, fe5f660, 637811a, 2fecdd7, 2855b0a
- Tests: shellcheck -x src/lib/ssh.sh src/containai.sh src/lib/container.sh, bash -c 'source src/containai.sh && cai ssh --help', bash -c 'source src/containai.sh && cai ssh cleanup --help', bash -c 'source src/containai.sh && cai ssh cleanup --dry-run', bash -c 'source src/containai.sh && cai stop --help'
- PRs:
