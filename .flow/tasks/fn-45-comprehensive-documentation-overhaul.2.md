# fn-45-comprehensive-documentation-overhaul.2 Create CLI reference documentation

## Description
Create comprehensive CLI reference documentation covering ALL `cai` subcommands, flags, environment variables, and exit codes. Currently this info is scattered across README.md, lifecycle.md, and --help output.

**Size:** L (upgraded from M due to comprehensive scope)
**Files:** `docs/cli-reference.md` (new)

## Approach

1. Extract commands from:
   - `cai --help` (authoritative source)
   - `cai <subcommand> --help` for each subcommand
   - `src/containai.sh` (main CLI entry point)
   - `src/lib/*.sh` (command implementations)

2. Document for each command:
   - Synopsis
   - Description
   - Options/flags
   - Environment variables
   - Exit codes
   - Examples (at least 2 per major command)

3. Follow patterns from:
   - `docs/configuration.md` (table-based reference style)
   - shellcheck README (CLI tool reference structure)
   - Docker CLI reference

4. Structure:
   ```
   # CLI Reference
   ## Maintenance Policy (document how to keep in sync with --help)
   ## Quick Reference (table of all commands)
   ## Command Hierarchy (mermaid diagram with accTitle/accDescr)
   ## Commands (alphabetical)
   ### cai (main entry)
   ### cai acp (+ proxy subcommand)
   ### cai completion
   ### cai config (+ list/get/set/unset subcommands)
   ### cai docker
   ### cai doctor (+ fix subcommand)
   ### cai exec
   ### cai export
   ### cai gc
   ### cai help
   ### cai import
   ### cai links (+ check/fix subcommands)
   ### cai refresh
   ### cai run
   ### cai sandbox (DEPRECATED - document migration path)
   ### cai setup
   ### cai shell
   ### cai ssh (+ cleanup subcommand)
   ### cai status
   ### cai stop
   ### cai sync
   ### cai template (+ upgrade subcommand)
   ### cai uninstall
   ### cai update
   ### cai validate
   ### cai version
   ## Environment Variables
   ## Exit Codes
   ## Deprecated Commands
   ```

5. **Add Mermaid diagram** showing command hierarchy/relationships:
   - Main `cai` command as root
   - Subcommands grouped by category (lifecycle, data, diagnostics, config)
   - Include `accTitle` and `accDescr` for accessibility

6. **Maintenance Policy section** (top of file):
   - State that `cai --help` is the authoritative source
   - Docs provide extended examples and cross-references
   - Document when to update (after any CLI change)
   - Suggest: "Run `cai --help` to verify current options"

7. **Deprecated Commands section**:
   - Document `sandbox` as deprecated
   - Provide migration path: "Use `cai stop && cai --restart` instead"
   - Mark clearly in quick reference table

## Key context

**Complete command list from `cai --help`:**
- run, shell, exec, doctor, setup, validate, docker, import, export, sync, stop, status, gc, ssh, links, config, completion, version, update, refresh, uninstall, help, acp, template, **sandbox (deprecated)**

**Commands with subcommands:**
- `cai acp proxy` (editor integration)
- `cai doctor fix` (container, volume, template)
- `cai ssh cleanup`
- `cai config list/get/set/unset`
- `cai links check/fix`
- `cai template upgrade`

**Key flags:** `--restart`, `--agent`, `--credentials`, `--config`, `--data-volume`, `--force`, `--verbose`, `--quiet`, `--fresh`, `--reset`, `--template`, `--channel`, `--memory`, `--cpus`, `--detached`, `--dry-run`, `-e/--env`

**Key env vars:** `CONTAINAI_VERBOSE`, `CONTAINAI_DATA_VOLUME`, `CAI_NO_UPDATE_CHECK`

## Acceptance
- [ ] ALL cai subcommands documented (25 commands from --help including deprecated)
- [ ] `cai acp` and `cai acp proxy` documented
- [ ] `cai template` and `cai template upgrade` documented
- [ ] **`cai sandbox` documented as DEPRECATED with migration path**
- [ ] Commands with subcommands fully documented (doctor fix, ssh cleanup, config *, links *)
- [ ] All flags documented with descriptions and defaults
- [ ] Environment variables table with precedence notes
- [ ] Exit codes documented with meanings
- [ ] At least 2 examples per major command
- [ ] Cross-references to related docs (configuration.md, lifecycle.md)
- [ ] Quick reference table at top for fast lookup
- [ ] **Maintenance policy section** explaining sync with --help
- [ ] **Mermaid diagram showing command hierarchy/categories** (include `accTitle`/`accDescr`)
- [ ] **Deprecated Commands section** with migration paths

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
