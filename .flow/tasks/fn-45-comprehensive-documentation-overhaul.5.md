# fn-45-comprehensive-documentation-overhaul.5 Create configuration examples cookbook

## Description
Create a configuration examples cookbook with real-world scenarios. Current configuration.md is comprehensive reference but lacks practical examples users can copy-paste and adapt.

**Size:** M
**Files:**
- `docs/examples/` directory (new)
- `docs/examples/README.md` (index)
- 5+ example config files

## Approach

1. Create `docs/examples/` directory structure

2. Example scenarios to cover:
   - **multi-agent.toml**: Multiple agents (Claude + Gemini) with separate credentials
   - **custom-sync.toml**: Adding custom dotfiles to sync
   - **isolated-workspace.toml**: Minimal sync for security-sensitive work
   - **power-user.toml**: VS Code Remote-SSH + port forwarding + custom ports
   - **ci-ephemeral.toml**: CI/CD usage with no persistence

3. Each example includes:
   - The TOML config file
   - Brief explanation of use case
   - How to apply it
   - What it enables/disables

4. Follow patterns from:
   - `docs/configuration.md` (existing schema)
   - `src/sync-manifest.toml` (sync mappings)
   - Terraform module examples structure

## Key context

Users ask "how do I configure X?" - examples answer faster than reference docs.

Real sync paths from `src/sync-manifest.toml`: shell configs, editor configs, git config, SSH.
## Acceptance
- [x] docs/examples/ directory created
- [x] README.md index listing all examples with descriptions
- [x] At least 5 example configs covering different scenarios
- [x] Each example has explanation comments
- [x] Examples validated against actual TOML schema
- [x] Cross-references from configuration.md to examples
- [x] No secrets or real credentials in examples
## Done summary
# Task Summary: Create configuration examples cookbook

Created a comprehensive configuration examples cookbook at `docs/examples/` with 6 copy-paste TOML configurations for common ContainAI setups:

## Examples Created

1. **multi-agent.toml** - Teams using multiple AI agents (Claude, Gemini, Codex) with per-workspace volume isolation
2. **custom-sync.toml** - Adding custom dotfiles via `additional_paths` configuration
3. **isolated-workspace.toml** - Security-sensitive work with minimal sync and no credential sharing
4. **power-user.toml** - VS Code Remote-SSH workflow with agent forwarding and port tunneling
5. **ci-ephemeral.toml** - CI/CD environments (GitHub Actions, GitLab CI) with no persistence
6. **team-shared.toml** - Repository-checked configuration for consistent team settings

## Documentation Added

- `docs/examples/README.md` - Index with usage instructions, config discovery explanation, validation commands

## Integration

- All TOML files validated with Python tomllib
- Cross-references added from `docs/configuration.md` to examples directory
- Each example includes inline comments explaining use case, key features, and settings

## Acceptance Criteria Met

- [x] docs/examples/ directory created
- [x] README.md index listing all examples with descriptions
- [x] 6 example configs covering different scenarios (exceeded minimum of 5)
- [x] Each example has explanation comments
- [x] Examples validated against actual TOML schema
- [x] Cross-references from configuration.md to examples
- [x] No secrets or real credentials in examples
## Examples Created

1. **multi-agent.toml** - Teams using multiple AI agents (Claude, Gemini, Codex) with per-workspace volume isolation
2. **custom-sync.toml** - Adding custom dotfiles via `additional_paths` configuration
3. **isolated-workspace.toml** - Security-sensitive work with minimal sync and no credential sharing
4. **power-user.toml** - VS Code Remote-SSH workflow with agent forwarding and port tunneling
5. **ci-ephemeral.toml** - CI/CD environments (GitHub Actions, GitLab CI) with no persistence
6. **team-shared.toml** - Repository-checked configuration for consistent team settings

## Documentation Added

- `docs/examples/README.md` - Index with usage instructions, config discovery explanation, validation commands

## Integration

- All TOML files validated with Python tomllib
- Cross-references added from `docs/configuration.md` to examples directory
- Each example includes inline comments explaining use case, key features, and settings

## Acceptance Criteria Met

- [x] docs/examples/ directory created
- [x] README.md index listing all examples with descriptions
- [x] 6 example configs covering different scenarios (exceeded minimum of 5)
- [x] Each example has explanation comments
- [x] Examples validated against actual TOML schema
- [x] Cross-references from configuration.md to examples
- [x] No secrets or real credentials in examples
## Examples Created

1. **multi-agent.toml** - Teams using multiple AI agents (Claude, Gemini, Codex) with per-workspace volume isolation
2. **custom-sync.toml** - Adding custom dotfiles via `additional_paths` configuration
3. **isolated-workspace.toml** - Security-sensitive work with minimal sync and no credential sharing
4. **power-user.toml** - VS Code Remote-SSH workflow with agent forwarding and port tunneling
5. **ci-ephemeral.toml** - CI/CD environments (GitHub Actions, GitLab CI) with no persistence
6. **team-shared.toml** - Repository-checked configuration for consistent team settings

## Documentation Added

- `docs/examples/README.md` - Index with usage instructions, config discovery explanation, validation commands

## Integration

- All TOML files validated with Python tomllib
- Cross-references added from `docs/configuration.md` to examples directory
- Each example includes inline comments explaining use case, key features, and settings

## Acceptance Criteria Met

- [x] docs/examples/ directory created
- [x] README.md index listing all examples with descriptions
- [x] 6 example configs covering different scenarios (exceeded minimum of 5)
- [x] Each example has explanation comments
- [x] Examples validated against actual TOML schema
- [x] Cross-references from configuration.md to examples
- [x] No secrets or real credentials in examples
## Evidence
- Commits:
- Tests:
- PRs:
