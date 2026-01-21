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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
