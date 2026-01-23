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
Added [ssh] config section with forward_agent and local_forward settings. ForwardAgent is explicitly controlled (defaults to no for security), LocalForward entries are validated for format and port ranges. Updated both SSH host config generation and CLI SSH connection to respect these settings. Documented VS Code Remote-SSH compatibility.
## Evidence
- Commits: 8972f20, 7afba0d, 5bbea0d
- Tests: bash -n config.sh, bash -n ssh.sh, manual config parsing test, manual SSH config generation test
- PRs:
