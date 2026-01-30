# fn-31-gib.3 Fix "claude: command not found" on fresh container

## Description
Investigate PATH availability via `cai shell` SSH session pathway. The Dockerfile sets `ENV PATH="/home/agent/.local/bin:${PATH}"`, but this may not propagate to SSH sessions.

**Investigation areas:**
1. How does `cai shell` enter the container (SSH vs docker exec)?
2. Which shell init file is sourced? (`~/.bashrc` vs `~/.profile` vs `~/.bash_profile`)
3. Is PATH correctly set in the SSH session environment?

## Acceptance
- [ ] Documented exact pathway `cai shell` uses (SSH to port X, or docker exec)
- [ ] Documented which init file is sourced on entry
- [ ] PATH includes `/home/agent/.local/bin` in SSH session
- [ ] Test case: `cai shell` then `which claude` returns `/home/agent/.local/bin/claude`
- [ ] Test case: `cai shell` then `claude --version` succeeds

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
