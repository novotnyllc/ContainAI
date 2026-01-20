# fn-7-j5o.4 Create config reference

## Description
Create comprehensive documentation of the config.toml schema and all configuration options.

**Size:** M
**Files:** `docs/configuration.md`

## Approach

- Document all config.toml keys with types, defaults, and examples
- Explain config file discovery hierarchy (workspace → user → system)
- Include complete example config.toml files for common scenarios
- Document environment variable overrides if any
- Reference implementation in `agent-sandbox/lib/config.sh`

## Key Context

- Config discovery stops at git root (not above)
- Workspace matching uses longest path prefix
- Volume names, agent selection, exclude patterns are configurable
- Config locations: `.containai/config.toml`, `~/.config/containai/config.toml`
- Parse via `agent-sandbox/parse-toml.py`
## Acceptance
- [ ] docs/configuration.md exists
- [ ] Documents all config.toml keys with types and defaults
- [ ] Explains config file discovery hierarchy
- [ ] Includes example configs for: single workspace, multi-workspace, multi-agent
- [ ] Documents workspace matching behavior
- [ ] Documents volume naming conventions
- [ ] Documents exclude patterns syntax
- [ ] Links to lib/config.sh for implementation details
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
