# fn-45-comprehensive-documentation-overhaul.2 Create CLI reference documentation

## Description
Create comprehensive CLI reference documentation covering all `cai` subcommands, flags, environment variables, and exit codes. Currently this info is scattered across README.md, lifecycle.md, and --help output.

**Size:** M
**Files:** `docs/cli-reference.md` (new)

## Approach

1. Extract commands from:
   - `src/containai.sh` (main CLI entry point)
   - `src/lib/*.sh` (command implementations)
   - Existing `--help` output

2. Document for each command:
   - Synopsis
   - Description
   - Options/flags
   - Environment variables
   - Exit codes
   - Examples

3. Follow patterns from:
   - `docs/configuration.md` (table-based reference style)
   - shellcheck README (CLI tool reference structure)
   - Docker CLI reference

4. Structure:
   ```
   # CLI Reference
   ## Quick Reference (table of all commands)
   ## Command Hierarchy (mermaid diagram)
   ## Commands
   ### cai
   ### cai shell
   ### cai import
   ### cai export
   ...
   ## Environment Variables
   ## Exit Codes
   ```

5. **Add Mermaid diagram** showing command hierarchy/relationships:
   - Main `cai` command as root
   - Subcommands branching from root
   - Show which commands relate to container lifecycle vs data sync vs diagnostics

## Key context

Known commands from codebase:
- `cai` (main entry, starts container)
- `cai shell` (attach to running container)
- `cai import` / `cai export` (data sync)
- `cai update` (update check)
- `cai doctor` (health check)
- `cai stop` (stop container)
- `cai exec` (run command in container)
- `--acp` mode (Agent Client Protocol)

Key flags: `--restart`, `--agent`, `--credentials`, `--config`, `--data-volume`, `--force`, `--verbose`, `--quiet`, `--fresh`, `--reset`

Key env vars: `CONTAINAI_VERBOSE`, `CONTAINAI_DATA_VOLUME`, `CAI_NO_UPDATE_CHECK`
## Approach

1. Extract commands from:
   - `src/containai.sh` (main CLI entry point)
   - `src/lib/*.sh` (command implementations)
   - Existing `--help` output

2. Document for each command:
   - Synopsis
   - Description
   - Options/flags
   - Environment variables
   - Exit codes
   - Examples

3. Follow patterns from:
   - `docs/configuration.md` (table-based reference style)
   - shellcheck README (CLI tool reference structure)
   - Docker CLI reference

4. Structure:
   ```
   # CLI Reference
   ## Quick Reference (table of all commands)
   ## Commands
   ### cai
   ### cai shell
   ### cai import
   ### cai export
   ...
   ## Environment Variables
   ## Exit Codes
   ```

## Key context

Known commands from codebase:
- `cai` (main entry, starts container)
- `cai shell` (attach to running container)
- `cai import` / `cai export` (data sync)
- `cai update` (update check)
- `cai doctor` (health check)
- `cai stop` (stop container)
- `cai exec` (run command in container)
- `--acp` mode (Agent Client Protocol)

Key flags: `--restart`, `--agent`, `--credentials`, `--config`, `--data-volume`, `--force`, `--verbose`, `--quiet`, `--fresh`, `--reset`

Key env vars: `CONTAINAI_VERBOSE`, `CONTAINAI_DATA_VOLUME`, `CAI_NO_UPDATE_CHECK`
## Acceptance
- [ ] All cai subcommands documented with synopsis
- [ ] All flags documented with descriptions and defaults
- [ ] Environment variables table with precedence notes
- [ ] Exit codes documented with meanings
- [ ] At least 2 examples per major command
- [ ] Cross-references to related docs (configuration.md, lifecycle.md)
- [ ] Quick reference table at top for fast lookup
- [ ] **Mermaid diagram showing command hierarchy/categories** (use standard dark theme)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
