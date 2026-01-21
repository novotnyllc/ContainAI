# fn-10-vep.50 Update cai run to use SSH instead of docker exec

## Description
Update `cai run` to use SSH instead of docker exec.

**Size:** M
**Files:** lib/container.sh, lib/ssh.sh

## Approach

1. Update `_containai_run()`:
   - Find/create container for workspace
   - Ensure SSH setup (key injection, host config)
   - Run command via: `ssh {container-name} {command}`

2. Handle all CLI modes:
   - `cai run <ws>`: Run default agent via SSH
   - `cai run <ws> -- <cmd>`: Run arbitrary command via SSH
   - `cai run --detached <ws> -- <cmd>`: Run command in background

3. Environment handling:
   - `--env` flags passed via SSH `-o SendEnv=`
   - Or: construct command as `VAR=value command`

## Key context

- SSH command execution: `ssh host 'command args'`
- For interactive: `ssh -t host 'command'` (allocate TTY)
- For detached: `ssh host 'nohup command &'`
## Acceptance
- [ ] `cai run /path/to/workspace` launches agent via SSH
- [ ] `cai run /path -- bash` runs bash via SSH
- [ ] `cai run --detached /path -- cmd` runs in background
- [ ] `--env` flags work (env vars passed to command)
- [ ] Interactive commands get TTY allocation
- [ ] Exit codes propagated correctly
- [ ] Command arguments properly quoted/escaped
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
