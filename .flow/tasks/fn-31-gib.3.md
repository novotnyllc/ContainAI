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
Fixed "claude: command not found" in SSH sessions by adding PATH configuration to /etc/profile.d/containai-agent-path.sh. This ensures ~/.local/bin and ~/.bun/bin are on PATH for login shells regardless of user shell config. Added comprehensive troubleshooting documentation explaining cai shell connection pathway (SSH -> login shell -> /etc/profile sourcing).
## Evidence
- Commits: a9b08426fc4c3866e5f86f83f4ad6e6e7d70d49d, e8986e756cbaa0084ae7a0af0f7ef6bc90f1a0d9, 924ec43ca9e200c0df9c4a009c6c5500a7249525
- Tests: shellcheck (pre-commit), codex impl-review SHIP
- PRs:
