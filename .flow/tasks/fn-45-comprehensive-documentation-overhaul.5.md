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
- [ ] docs/examples/ directory created
- [ ] README.md index listing all examples with descriptions
- [ ] At least 5 example configs covering different scenarios
- [ ] Each example has explanation comments
- [ ] Examples validated against actual TOML schema
- [ ] Cross-references from configuration.md to examples
- [ ] No secrets or real credentials in examples
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
