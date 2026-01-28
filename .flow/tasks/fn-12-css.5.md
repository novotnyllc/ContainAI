# fn-12-css.5 Add TOML writer to parse-toml.py

## Description

Extend `src/parse-toml.py` to support writing/updating TOML config files, not just reading them. This enables `cai config set` to modify config files programmatically.

**New operations:**

1. **Set a value:**
   ```bash
   parse-toml.py set --file config.toml --key "ssh.forward_agent" --value "true" --type bool
   ```
   - Creates section if doesn't exist
   - Updates value if key exists
   - Preserves comments and formatting where possible

2. **Unset a value:**
   ```bash
   parse-toml.py unset --file config.toml --key "ssh.forward_agent"
   ```
   - Removes key from config
   - Removes empty sections (optional: `--prune-empty`)

3. **Set workspace value:**
   ```bash
   parse-toml.py set --file config.toml --workspace "/path/to/project" --key "data_volume" --value "myvolume"
   ```
   - Creates `[workspace."/path/to/project"]` section if needed
   - Sets key within that section

**Type handling:**
- `--type bool`: Convert "true"/"false" to TOML boolean
- `--type int`: Convert to TOML integer
- `--type string` (default): Keep as quoted string
- `--type array`: Parse as JSON array → TOML array

**Implementation notes:**
- Use Python's `tomllib` for reading (stdlib in 3.11+)
- Use `tomli_w` or manual string manipulation for writing (no stdlib writer)
- Preserve existing file structure where possible
- Handle edge cases: missing file (create new), invalid TOML (error)

**Output:**
- Success: exit 0, no output
- Error: exit 1, error message to stderr

## Acceptance

- [ ] `parse-toml.py set --file f.toml --key "ssh.forward_agent" --value "true" --type bool` sets boolean
- [ ] `parse-toml.py set --file f.toml --key "container.memory" --value "4096" --type int` sets integer
- [ ] `parse-toml.py set --file f.toml --workspace "/path" --key "data_volume" --value "vol"` sets workspace key
- [ ] `parse-toml.py unset --file f.toml --key "ssh.forward_agent"` removes key
- [ ] Missing file is created with specified key
- [ ] Existing content is preserved when adding keys
- [ ] Exit code 1 on errors with message to stderr

## Done summary
Superseded by fn-36-rb7 or fn-31-gib
## Evidence
- Commits:
- Tests:
- PRs:
