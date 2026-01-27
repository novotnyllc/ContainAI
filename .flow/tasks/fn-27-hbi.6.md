# fn-27-hbi.6 Documentation updates for reliability features

## Description
Update documentation for all reliability features added in this epic.

**Size:** S
**Files:** `docs/setup-guide.md`, `docs/troubleshooting.md`, `CHANGELOG.md`, `README.md`

## Approach

1. **docs/setup-guide.md** - Add "Updating ContainAI" section:
   - `cai update` workflow across platforms
   - `--dry-run`, `--stop-containers`, `--force` flags
   - Platform-specific behavior (WSL2, Linux, macOS)

2. **docs/troubleshooting.md** - Add repair documentation:
   - `cai doctor --repair` subcommands
   - When to use repair vs recreate container
   - id-mapped ownership symptoms and fixes

3. **CHANGELOG.md** - Add entries for:
   - Safe update flow with container management
   - Doctor repair subcommands
   - SSH/shell reliability fixes
   - Cross-platform sysbox updates
   - fuse3 packaging fix

4. **README.md** - Add `cai update` to common commands section (line 87-96)

## Key context

- Follow existing doc patterns in troubleshooting.md (Quick Reference table, Diagnostic Commands format)
- CHANGELOG uses keep-a-changelog format with date-based versioning
## Acceptance
- [ ] docs/setup-guide.md has "Updating ContainAI" section
- [ ] docs/troubleshooting.md documents `cai doctor --repair` subcommands
- [ ] CHANGELOG.md has entries for all reliability features
- [ ] README.md common commands includes `cai update`
- [ ] Documentation follows existing patterns and formatting
## Done summary
Added documentation for all reliability features: "Updating ContainAI" section in setup-guide.md with platform-specific behavior and container safety, "Volume Ownership Repair" section in troubleshooting.md with cai doctor --repair commands, CHANGELOG entries for safe update flow/repair/SSH fixes/sysbox updates/fuse3, and cai update in README common commands.
## Evidence
- Commits: a7aa1e5, bd88cb8
- Tests: shellcheck -x (passed via pre-commit)
- PRs:
