# fn-46-cli-ux-audit-and-simplification.2 Flag naming consistency audit

## Description
Audit all CLI flags for naming consistency, behavior consistency, and adherence to conventions. Produce a flag matrix showing usage across all commands.

**Size:** M
**Files:** Analysis output only (no code changes)

## Approach

1. Extract all flags from:
   - `src/containai.sh` case statements
   - Shell completion definitions (lines 5997-6022)
   - Help text for each command

2. Build flag matrix:
   | Flag | Short | Long | Commands | Behavior | Notes |
   |------|-------|------|----------|----------|-------|

3. Check for inconsistencies:
   - Same concept, different names (`--name` vs `--container`)
   - Same flag, different behavior across commands
   - Missing short forms for common flags
   - Non-standard naming (kebab-case vs snake_case)

4. Known issues to investigate:
   - `--name` in `cai links` vs `--container` elsewhere
   - `--workspace` vs positional workspace argument
   - `--volume/-v` rejection in `cai run`
   - `-v` for version (not verbose) per project conventions

## Key context

Reference files:
- Flag parsing: `src/containai.sh` case statements throughout
- Completion flags: `src/containai.sh:5997-6022`
- Conventions: `.flow/memory/conventions.md` (no `-v` for verbose)

Flag categories to analyze:
- Global flags (--verbose, --quiet, --help, --version)
- Resource flags (--container, --workspace, --data-volume)
- Behavior flags (--force, --dry-run, --fresh, --restart)
- Output flags (--json, --quiet)
## Acceptance
- [ ] Complete flag matrix with all flags across all commands
- [ ] Inconsistencies documented with severity rating
- [ ] Convention violations identified (vs POSIX/GNU/clig.dev)
- [ ] Recommendations for standardization
- [ ] Impact assessment for any breaking changes
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
