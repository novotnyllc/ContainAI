# Flag Naming Consistency Audit

## Overview

This document audits primary CLI flags across ContainAI commands for naming consistency, identifying inconsistencies, convention violations, and recommendations for standardization.

**Scope**: Comprehensive audit of ALL flags from both help text AND source code parsing. Includes undocumented flags (marked with †). Includes legacy/rejected flags (marked as LEGACY).

**Audit Date:** 2026-02-03
**Epic:** fn-46-cli-ux-audit-and-simplification
**Task:** fn-46.2

## Command Inventory

Commands derived programmatically from `containai()` dispatch:

```
completion  config  docker  doctor  exec  export  gc  help
import  links  refresh  run  sandbox  setup  shell  ssh
status  stop  sync  template  uninstall  update  validate  version
```

**Total:** 24 commands (including deprecated `sandbox`)

**Flag-based routes:** `--refresh` in main dispatch routes to `refresh` command

---

## Comprehensive Flag Matrix

### Legend

- **SHORT**: Single-letter short form (e.g., `-q`)
- **LONG**: Long form (e.g., `--quiet`)
- **Commands**: Which commands support this flag
- **Behavior**: What the flag does
- **Severity**: HIGH/MEDIUM/LOW for issues

### Global Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| `-h` | `--help` | ALL | Show help text | Consistent |
| `-v` | `--version` | version | Show version info | `-v` reserved for version, not verbose |
| - | `--verbose` | import, export, gc, config, status, stop, run, shell, exec, links, refresh, setup, uninstall, update, validate | Enable verbose output | **No `-v` short form per project convention** |
| `-q` | `--quiet` | run, shell, exec, links | Suppress verbose output | Limited availability |
| - | `--dry-run` | run, shell, import, gc, links, setup, sync, template, uninstall, update | Preview without executing | Consistent |

### Resource/Container Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| - | `--workspace` | run, shell, exec, import, export, status, doctor†, config, links | Workspace path | †undocumented in doctor |
| `-w` | `--workspace` | run, shell, exec, import, export, doctor†, config (list/get/set/unset), links | Short form | **status missing -w**; †undocumented |
| - | `--container` | run, shell, exec, import, export, status, stop | Target container by name | Consistent |
| - | `--name` | links | Container name | **INCONSISTENT: should be --container** |
| - | `--data-volume` | run, shell, exec, import, export | Data volume name | Consistent |
| - | `--config` | run, shell, exec, import, export, links | Config file path | Consistent |
| - | `--template` | run, shell, exec | Template name | Consistent |
| - | `--channel` | run, shell, exec | Release channel | Consistent |
| - | `--image-tag` | run, shell | Image tag (advanced) | Consistent |

**† Note on undocumented flags:** `doctor --workspace/-w` is parsed in source (`src/containai.sh:2548-2560`) and works at runtime, but is NOT shown in `cai doctor --help`. Consider documenting it or removing the code.

### Behavior Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| - | `--force` | run, shell, exec, stop, gc, setup, uninstall, update | **VARIES BY COMMAND** | **HIGH SEVERITY - see below** |
| - | `--fresh` | run, shell, exec | Recreate container | Consistent |
| - | `--restart` | run, shell | Alias for --fresh | Legacy alias |
| - | `--reset` | run, shell | Reset workspace state | Consistent |
| `-d` | `--detached` | run | Run in background | Only run command |
| - | `--remove` | stop | Also remove containers | Consistent |
| - | `--all` | stop, doctor fix | Stop all containers / fix all items | Consistent |
| - | `--export` | stop | Export before stop | Consistent |

### Output Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| - | `--json` | doctor, status, version | JSON output | **Limited availability** |
| - | `--build-templates` | doctor | Heavy template validation | Command-specific |
| - | `--reset-lima` | doctor | Delete Lima VM (macOS only) | Platform-specific, undocumented on non-macOS |

### Import/Export Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| - | `--from` | import | Import source path | Consistent |
| `-o` | `--output` | export | Output path (file or dir) | Export-specific |
| - | `--no-excludes` | import, export | Skip exclude patterns | Consistent |
| - | `--no-secrets` | import | Skip secret entries | Consistent |

### Refresh Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| - | `--rebuild` | refresh | Rebuild template after pull | Command-specific |

### Uninstall Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| - | `--containers` | uninstall | Stop/remove all containers | Command-specific |
| - | `--volumes` | uninstall | Also remove volumes | Requires --containers |

### SSH Subcommand Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| - | `--dry-run` | ssh cleanup | Preview cleanup | Subcommand-specific |
| - | `--verbose` | ssh cleanup | Verbose output | Subcommand-specific |

### Environment/Volume Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| `-e` | `--env` | run | Set environment variable | Only run command |
| - | `--memory` | run, shell | Memory limit | Consistent |
| - | `--cpus` | run, shell | CPU limit | Consistent |

### Config Subcommand Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| `-g` | `--global` | config set, config unset | Force global scope | Consistent |

### Setup/Update Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| - | `--skip-templates` | setup | Skip template install | Consistent |
| - | `--stop-containers` | update | Stop containers first | Consistent |
| - | `--lima-recreate` | update | Force Lima recreation | Platform-specific |

### GC Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| - | `--age` | gc | Minimum age for pruning | Consistent |
| - | `--images` | gc | Also prune images | Consistent |

### Links Subcommand Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| - | `--name` | links | Container name | **Should be --container** |

### Security/Advanced Flags

| Short | Long | Commands | Behavior | Notes |
|-------|------|----------|----------|-------|
| `-D` | `--debug` | run, shell, exec | Debug mode | Consistent |
| - | `--credentials` | run | Credentials mode | Advanced use |
| - | `--acknowledge-credential-risk` | run | Acknowledge credential risk | Parsed but currently no effect (no-op) |
| - | `--mount-docker-socket` | run (rejected), shell (rejected) | ~~Mount Docker socket~~ | **LEGACY**: Parsed then rejected at runtime |
| - | `--allow-host-credentials` | run (rejected), shell (rejected) | ~~Allow host credentials~~ | **LEGACY**: Parsed then rejected at runtime |
| - | `--allow-host-docker-socket` | run (rejected), shell (rejected) | ~~Allow host Docker socket~~ | **LEGACY**: Parsed then rejected at runtime |
| - | `--please-root-my-host` | run (no-op), shell (rejected) | ~~Alias for risky flags~~ | **LEGACY**: Parsed but no effect |
| - | `--i-understand-this-exposes-host-credentials` | run (no-op), shell (rejected) | ~~Acknowledgment~~ | **LEGACY**: Parsed but no effect |
| - | `--i-understand-this-grants-root-access` | run (no-op), shell (rejected) | ~~Acknowledgment~~ | **LEGACY**: Parsed but no effect |

**Note:** Security flags are intentionally undocumented in main help to discourage casual use.

**LEGACY FLAGS:** `--mount-docker-socket`, `--allow-host-credentials`, and `--allow-host-docker-socket` are parsed in `containai.sh` but rejected at runtime in `container.sh:1730-1750` with "no longer supported" error. These flags exist for backward-compatible error messaging only - they do not enable any functionality.

**INTENTIONALLY REJECTED:** `--volume/-v` is NOT supported in `cai run` by design. ContainAI intentionally limits volume mounts to workspace and data-volume only, as arbitrary host mounts would bypass the security isolation model. Users expecting Docker-style `-v` will receive a clear error explaining the security rationale.

---

## Inconsistencies Identified

### HIGH Severity

#### 1. `--name` vs `--container` (Naming Inconsistency)

**Issue:** `cai links` uses `--name` while all other commands use `--container` for the same concept.

**Current Behavior:**
- `cai links --name my-container` - works
- `cai links --container my-container` - does NOT work (not recognized)
- `cai status --container my-container` - works
- `cai stop --container my-container` - works

**Locations:**
- `src/containai.sh:888` - help text shows `--name`
- `src/containai.sh:3248-3259` - parses `--name`
- `src/containai.sh:3391-3402` - parses `--name` in fix subcommand

**Deprecation in other commands:**
- `src/containai.sh:1616-1617` shows `--name` is explicitly deprecated elsewhere:
  ```bash
  --name | --name=*)
      echo "[ERROR] --name is no longer supported. Use --container instead." >&2
  ```

**Recommendation:** Deprecate `--name` in `cai links`, add `--container` alias, emit warning.

**Impact:** Breaking change (requires deprecation period).

**Owner Epic:** fn-36-rb7 or new epic.

---

#### 2. `--force` Meaning Varies by Command (Semantic Inconsistency)

**Issue:** The `--force` flag has different meanings across commands, violating the principle of consistent behavior.

| Command | `--force` Behavior |
|---------|-------------------|
| `run`, `shell`, `exec` | Skip isolation checks (for testing only) |
| `stop` | Skip session warning prompt |
| `gc` | Skip confirmation prompt |
| `setup` | Bypass seccomp compatibility warning (WSL2) |
| `uninstall` | Skip confirmation prompts |
| `update` | Skip all confirmation prompts + stop containers |

**Semantic categories:**
1. **Skip prompts/confirmations:** stop, gc, uninstall, update (most common)
2. **Skip safety checks:** run, shell, exec (different meaning)
3. **Platform workaround:** setup (different meaning)

**Recommendation:**
- Rename `--force` in run/shell/exec to `--skip-isolation-check` or `--unsafe`
- Keep `--force` for "skip confirmations" semantic
- Document clearly in help text

**Impact:** Breaking change for run/shell/exec power users.

**Owner Epic:** fn-36-rb7 or new epic.

---

### MEDIUM Severity

#### 3. `-w` Short Form Coverage

**Status:** Largely consistent after source review.

Most commands that accept `--workspace` also accept `-w`:
- run, shell, exec, import, export, doctor, config subcommands, links

| Has `-w` | No `-w` |
|----------|---------|
| run, shell, exec, import, export, doctor, config, links | status |

**Recommendation:** Add `-w` to `status` command for full consistency.

**Impact:** Non-breaking (additive).

**Owner Epic:** fn-36-rb7.

---

#### 4. `--workspace` vs Positional Workspace

**Issue:** Some commands accept workspace as both positional AND flag, creating two ways to do the same thing.

**Commands with dual behavior:**
- `cai run /path` or `cai run --workspace /path`
- `cai shell /path` or `cai shell --workspace /path`
- `cai links /path` or `cai links --workspace /path`
- `cai import /path` or `cai import --workspace /path`

**Recommendation:** Document clearly; consider deprecating positional form in favor of flags for consistency. Keep positional for convenience but prefer flag in docs.

**Impact:** Documentation/guidance change.

**Owner Epic:** fn-45 (documentation).

---

#### 5. `--json` Limited Availability

**Issue:** Only 3 commands support `--json` output: `doctor`, `status`, `version`.

**Commands that should arguably support `--json`:**
- `gc --dry-run` (currently text output)
- `validate` (check results)
- `links` (symlink status)
- `template list` (template listing)

**Recommendation:** Prioritize `--json` for commands commonly used in scripts.

**Impact:** Non-breaking (additive).

**Owner Epic:** fn-42 or new epic.

---

### LOW Severity

#### 6. Missing Short Forms for Common Flags

**Flags without short forms:**
- `--verbose` (no `-v` per project convention - intentional)
- `--container` (could be `-c`)
- `--template` (could be `-t`)
- `--force` (could be `-f`)
- `--dry-run` (could be `-n` per GNU convention)

**Recommendation:** Consider adding:
- `-c` for `--container` (common pattern)
- `-n` for `--dry-run` (GNU convention)
- `-f` for `--force` (common pattern)

**Note:** `-v` is intentionally NOT used for `--verbose` (project convention: reserved for `--version`).

**Impact:** Non-breaking (additive).

**Owner Epic:** fn-36-rb7.

---

#### 7. `--restart` is Legacy Alias

**Issue:** `--restart` is documented as "Alias for --fresh" in run/shell but adds cognitive load.

**Current behavior:**
- `cai run --fresh` and `cai run --restart` do the same thing
- Both documented in help

**Recommendation:** Deprecate `--restart` with warning, eventually remove.

**Impact:** Breaking change (requires deprecation period).

**Owner Epic:** fn-36-rb7.

---

## Convention Compliance

### POSIX/GNU Compliance

| Convention | Status | Notes |
|------------|--------|-------|
| Long options with `--` prefix | PASS | All long options use `--` |
| Short options with `-` prefix | PASS | All short options use `-` |
| `--` to separate options from args | PASS | Supported in run/exec |
| `=` for long option values | PASS | Both `--flag value` and `--flag=value` supported |
| Case sensitivity | PASS | All options lowercase |

### clig.dev Compliance

| Guideline | Status | Notes |
|-----------|--------|-------|
| Use `--help` not `-help` | PASS | |
| Support `--version` | PASS | |
| Keep flags consistent across commands | PARTIAL | `--force` varies, `--name` vs `--container` |
| Prefer flags to positional args for clarity | PARTIAL | Dual support creates ambiguity |
| Make destructive actions require confirmation | PASS | `--force` skips, default is safe |

### Project Conventions

| Convention | Status | Notes |
|-----------|--------|-------|
| No `-v` for verbose | PASS | Uses `--verbose` only |
| `--quiet` overrides `--verbose` | PASS | Documented precedence |
| `CONTAINAI_VERBOSE=1` env support | PASS | Alternative to flag |

---

## Impact Assessment for Breaking Changes

### High Risk (Requires Deprecation)

1. **`--name` → `--container` in links**
   - Users of `cai links --name` will break
   - Migration: Accept both, warn on `--name`, remove after 2 releases

2. **`--force` rename in run/shell/exec**
   - Power users bypassing isolation will break
   - Migration: Accept both, warn on `--force`, remove after 2 releases

3. **`--restart` removal**
   - Users of `--restart` will break
   - Migration: Warn on usage, remove after 2 releases

### Low Risk (Additive)

1. Adding `-w` to `status` command (others already have it)
2. Adding `-c`, `-n`, `-f` short forms
3. Adding `--json` to more commands

---

## Recommendations Summary

### Quick Wins (Low Effort, No Breaking Changes)

| Rec | Description | Owner Epic |
|-----|-------------|------------|
| Q1 | Add `-w` short form to `status` (others already have it) | fn-36-rb7 |
| Q2 | Add `-c` for `--container` | fn-36-rb7 |
| Q3 | Add `-n` for `--dry-run` | fn-36-rb7 |
| Q4 | Document workspace positional vs flag in help | fn-45 |

### Medium Effort (Deprecation Required)

| Rec | Description | Owner Epic |
|-----|-------------|------------|
| M1 | Deprecate `--name` in links, add `--container` | fn-36-rb7 |
| M2 | Deprecate `--restart`, keep `--fresh` only | fn-36-rb7 |
| M3 | Add deprecation warning framework | fn-36-rb7 |

### Breaking Changes (Requires Planning)

| Rec | Description | Owner Epic |
|-----|-------------|------------|
| B1 | Rename `--force` in run/shell/exec to `--skip-isolation` | new epic |
| B2 | Standardize `--force` to always mean "skip confirmations" | new epic |

---

## Appendix: Flag Extraction Method

### Command Inventory Derivation

```bash
# Extract commands from containai() dispatch (POSIX-portable)
# Note: Uses [[:space:]] instead of \s for cross-platform compatibility
awk '/^containai\(\)/,/^}/' src/containai.sh | \
  grep -E '^[[:space:]]+[a-z-]+.*\)' | \
  sed 's/).*//; s/[[:space:]]//g' | \
  tr '|' '\n' | \
  sed 's/^--//' | \
  grep -E '^[a-z]+$' | \
  sort -u
```

### Flag Extraction from Help

```bash
source src/containai.sh
for cmd in $COMMANDS; do
  echo "=== $cmd ==="
  cai $cmd --help 2>&1 | grep -E '^[[:space:]]+--'
done
```

### Flag Extraction from Source

```bash
# Case statement flags (POSIX-portable grep)
grep -rn -- '--[a-z]' src/containai.sh src/lib/*.sh | grep -E '\)$'
```

### Pre-Case Route Extraction

```bash
# Find if-routes before the case statement (both with and without -- prefix)
awk '/^containai\(\)/,/^}/' src/containai.sh | \
  grep -E '== "[a-z-]+"' | \
  sed 's/.*== "\([a-z-]*\)".*/\1/' | \
  sort -u
```
