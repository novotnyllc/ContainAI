# fn-10-vep.42 Setup ~/.ssh/containai.d/ with Include directive

## Description
Setup `~/.ssh/containai.d/` directory and add Include directive to SSH config.

**Size:** S
**Files:** lib/ssh.sh

## Approach

1. In `_cai_setup_ssh_config()`:
   - Create `~/.ssh/containai.d/` with 700 permissions
   - Check if `~/.ssh/config` exists, create if not
   - Check if Include directive already present (grep for `containai.d`)
   - If not present, add `Include ~/.ssh/containai.d/*.conf` at TOP of config
   - Check OpenSSH version (7.3p1+ required for Include)

## Key context

- Include directive MUST be at top of ~/.ssh/config (before any Host definitions)
- Use `Match all` trick if user has config that doesn't start with Host
- Pattern from github-scout: ethack/docker-vpn uses this approach
## Acceptance
- [ ] `~/.ssh/containai.d/` directory created with 700 permissions
- [ ] `Include ~/.ssh/containai.d/*.conf` added to `~/.ssh/config`
- [ ] Include directive is at top of config file
- [ ] No duplicate Include directives added on re-run
- [ ] OpenSSH version check warns if < 7.3p1
- [ ] Existing SSH config preserved (not overwritten)
## Done summary
Added `_cai_setup_ssh_config()` to create `~/.ssh/containai.d/` directory and add `Include ~/.ssh/containai.d/*.conf` directive at top of `~/.ssh/config`. Integrated into setup flow with dry-run support. Implementation handles case variants, path variants, whitespace, symlinks, and ensures idempotence with OpenSSH version check.
## Evidence
- Commits: 99bcba9, 1003fb4, 8c88e70, fbd18b2
- Tests: Manual: verified directory creation with 700 perms, Manual: verified Include directive at top of config, Manual: verified idempotence (no duplicates), Manual: verified symlink preservation, Manual: verified case-insensitive detection, Manual: verified absolute path detection, Manual: verified whitespace-tolerant detection
- PRs: