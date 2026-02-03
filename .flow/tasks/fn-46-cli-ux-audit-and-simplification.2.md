# fn-46-cli-ux-audit-and-simplification.2 Flag naming consistency audit

## Description
Audit all CLI flags for naming consistency, behavior consistency, and adherence to conventions. Produce a comprehensive flag matrix showing usage across all commands, including subcommand-specific flags. Derive command list from programmatic inventory.

**Size:** M
**Files:** Analysis output only (no code changes)

## Approach

### Step 1: Extract ALL Flags (Expanded Scope)

**Derive command list from programmatic inventory (not hardcoded):**
```bash
# Get all commands from dispatch (same method as task .1)
# Uses POSIX [[:space:]] instead of \s for cross-platform compatibility
COMMANDS=$(awk '/^containai\(\)/,/^}/' src/containai.sh | \
  grep -E '^[[:space:]]+[a-z-]+.*\)' | \
  sed 's/).*//; s/[[:space:]]//g' | \
  tr '|' '\n' | \
  sed 's/^--//' | \
  grep -E '^[a-z]+$' | \
  sort -u)

echo "$COMMANDS"
```

**Extract flags from help text for ALL discovered commands:**
```bash
source src/containai.sh
for cmd in $COMMANDS; do
  echo "=== $cmd ==="
  cai $cmd --help 2>&1 | grep -E '^[[:space:]]+--' || echo "(no flags in help)"
done
```

**Extract flags from case statements in source:**
```bash
# Main CLI case statements
grep -n '\-\-[a-z]' src/containai.sh | grep -E '\)$|--[a-z]' | head -50

# Library modules (CRITICAL - many flags here)
grep -rn '\-\-[a-z]' src/lib/*.sh | grep -E '\)$|--[a-z]' | head -100
```

**Key library files to audit:**
- `src/lib/setup.sh` - setup/validate flags
- `src/lib/update.sh` - update/refresh flags
- `src/lib/uninstall.sh` - uninstall flags
- `src/lib/container.sh` - run/shell/exec flags (--workspace, --container, etc.)
- `src/lib/sync.sh` - import/export/sync flags
- `src/lib/config.sh` - config flags

### Step 2: Build Comprehensive Flag Matrix

| Flag | Short | Long | Command(s) | Subcommand | Behavior | Notes |
|------|-------|------|------------|------------|----------|-------|
| (example) | -n | --name | links | - | Container name | Inconsistent with --container |
| (example) | -w | --workspace | run, shell | - | Workspace path | Also positional arg |

**Include ALL discovered commands** (including deprecated):
- Mark deprecated commands in the matrix
- Treat subcommands as separate rows when flags differ

**Include flag-based routes:**
- `--refresh` (routes to refresh command)

### Step 3: Check for Inconsistencies

Categories to flag:
- **Same concept, different names**: `--name` vs `--container` (HIGH severity)
- **Same flag, different behavior**: `--force` meaning varies (HIGH severity)
- **Missing short forms**: common flags without `-x` shortcut (LOW severity)
- **Non-standard naming**: snake_case instead of kebab-case (MEDIUM severity)
- **Positional + flag overlap**: `--workspace` AND positional workspace (MEDIUM severity)

### Step 4: Document Known Issues

Investigate these known inconsistencies:
- `--name` in `cai links` vs `--container` elsewhere
- `--workspace` vs positional workspace argument (two ways to do same thing)
- `--volume/-v` rejection in `cai run` (explain why clearly)
- `-v` reserved for version (not verbose) per project conventions
- `--json` availability (which commands support it?)

## Key context

Reference files:
- Main CLI: `src/containai.sh` case statements
- **Library modules: `src/lib/*.sh`** (expanded scope)
- Completion flags: `src/containai.sh` COMPREPLY sections
- Conventions: `.flow/memory/conventions.md` (no `-v` for verbose)

Flag categories to analyze:
- Global flags (--verbose, --quiet, --help, --version)
- Resource flags (--container, --workspace, --data-volume)
- Behavior flags (--force, --dry-run, --fresh, --restart)
- Output flags (--json, --quiet)

## Acceptance
- [x] Command list derived from programmatic inventory (not hardcoded)
- [x] Complete flag matrix from `src/containai.sh` AND `src/lib/*.sh`
- [x] All discovered commands included (including deprecated, marked as such)
- [x] Subcommands treated as separate entries where flags differ
- [x] Flag-based routes (--refresh) included
- [x] Inconsistencies documented with severity rating (HIGH/MEDIUM/LOW)
- [x] Convention violations identified (vs POSIX/GNU/clig.dev)
- [x] Recommendations for standardization
- [x] Impact assessment for any breaking changes

## Done summary

Comprehensive flag consistency audit completed for ContainAI CLI. Identified 24 commands via programmatic extraction from the `containai()` dispatch function. Created a full flag matrix covering:

- **Global flags**: --help, --verbose, --quiet, --dry-run
- **Resource flags**: --workspace, --container, --data-volume, --config, etc.
- **Behavior flags**: --force, --fresh, --restart, --reset, --detached
- **Output flags**: --json (limited availability)

### Inconsistencies Found (7 total)

**HIGH Severity (2):**
1. `--name` vs `--container` in `cai links` - should use `--container` for consistency
2. `--force` semantic inconsistency - means different things across 6 commands (skip checks vs skip prompts)

**MEDIUM Severity (3):**
1. `-w` short form missing from `status` command (only one without it)
2. `--workspace` accepts both positional and flag forms (two ways to do same thing)
3. `--json` only available on 3 commands (doctor, status, version)

**LOW Severity (2):**
1. Missing common short forms (-c, -n, -f)
2. `--restart` is documented legacy alias for `--fresh` (adds cognitive load)

### Additional Findings

- **Legacy/rejected flags**: 6 flags parsed but rejected at runtime (`--mount-docker-socket`, `--allow-host-*`, acknowledgment aliases)
- **Intentional rejection**: `--volume/-v` not supported by design (security isolation)
- **Undocumented flags**: `doctor --workspace/-w` works but not in `--help`

### Recommendations

**Quick wins (4):** Add `-w` to `status` (only missing one), add `-c`/`-n`/`-f` shorts, document workspace args
**Medium effort (3):** Deprecate `--name` in links, deprecate `--restart`, add deprecation framework
**Breaking changes (2):** Rename `--force` in run/shell/exec, standardize `--force` semantics

Full analysis in `.flow/specs/flag-naming-consistency-audit.md`
## Evidence
- Commits:
- Tests:
- PRs:
