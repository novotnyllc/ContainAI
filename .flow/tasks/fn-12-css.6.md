# fn-12-css.6 Implement cai config command

## Description

Add a new `cai config` subcommand for managing ContainAI configuration without manually editing TOML files.

**Subcommands:**

```
cai config get <key>                        # Get value
cai config set <key> <value>                # Set global config
cai config set --workspace <key> <value>    # Set workspace config
cai config list                             # Show all config
cai config unset <key>                      # Remove key
cai config unset --workspace <key>          # Remove workspace key
```

**Supported keys:**

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ssh.forward_agent` | bool | false | Enable SSH agent forwarding |
| `ssh.allow_tunnel` | bool | false | Allow SSH tunneling |
| `ssh.port_range_start` | int | 2300 | SSH port range start |
| `ssh.port_range_end` | int | 2500 | SSH port range end |
| `ssh.local_forward` | array | [] | Local port forward entries |
| `import.auto_prompt` | bool | true | Prompt for import on new volume |
| `import.exclude_priv` | bool | true | Exclude *.priv.* from .bashrc.d |
| `container.memory` | string | "" | Default memory limit |
| `container.cpus` | string | "" | Default CPU limit |
| `agent.default` | string | "claude" | Default agent |
| `agent.data_volume` | string | "sandbox-agent-data" | Default data volume |
| `secure_engine.context_name` | string | "" | Docker context |

**Implementation:**

1. **`cai config get <key>`**
   - Read from config file(s) using existing `_containai_parse_config()`
   - Show source (user config, workspace config, or default)
   - Exit 1 if key not found

2. **`cai config set <key> <value>`**
   - Call `parse-toml.py set` (from task 5)
   - Validate key is known
   - Validate value type matches expected type
   - Default target: user config (`~/.config/containai/config.toml`)

3. **`cai config set --workspace <key> <value>`**
   - Set in `[workspace."<cwd>"]` section
   - Only workspace-overridable keys allowed (data_volume, excludes)

4. **`cai config list`**
   - Show all config in table format
   - Columns: Key, Value, Source (default/user/workspace)
   - Include effective values (after precedence)

5. **`cai config unset <key>`**
   - Remove key from user config
   - Call `parse-toml.py unset`

**Validation:**
- Unknown keys: error with list of valid keys
- Type mismatch: error with expected type
- Invalid values: error with constraints (e.g., port range)

## Acceptance

- [ ] `cai config get ssh.forward_agent` shows value and source
- [ ] `cai config set ssh.forward_agent true` updates user config
- [ ] `cai config set --workspace data_volume myvolume` updates workspace section
- [ ] `cai config list` shows all keys with values and sources
- [ ] `cai config unset ssh.forward_agent` removes from config
- [ ] Unknown keys produce helpful error
- [ ] Type validation for bool/int/string/array

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
