# fn-10-vep.51 Add [ssh] config section for agent forwarding and tunneling

## Description
Add [ssh] config section for agent forwarding and port tunneling.

**Size:** S
**Files:** lib/config.sh, lib/ssh.sh

## Approach

1. Add `[ssh]` section to config.toml schema:
   ```toml
   [ssh]
   forward_agent = true       # ForwardAgent yes
   local_forward = ["8080:localhost:8080"]  # LocalForward
   port_range_start = 2300
   port_range_end = 2500
   ```

2. Update `_cai_write_ssh_host_config()`:
   - Read config values
   - Include ForwardAgent directive if enabled
   - Include LocalForward directives from config

3. Document VS Code Remote-SSH compatibility

## Key context

- ForwardAgent has security implications - document clearly
- LocalForward format: "localport:remotehost:remoteport"
## Acceptance
- [ ] `[ssh]` section documented in config.toml schema
- [ ] `forward_agent` setting controls ForwardAgent
- [ ] `local_forward` array creates LocalForward entries
- [ ] Port range configurable via config
- [ ] Generated SSH config includes user settings
- [ ] VS Code Remote-SSH can connect using containai config
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
