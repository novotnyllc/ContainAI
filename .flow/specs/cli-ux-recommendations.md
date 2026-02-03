# CLI UX Audit Recommendations

## Executive Summary

- **Total recommendations:** 25
- **Quick wins:** 7 (implement now)
- **Medium effort:** 13 (next release)
- **Breaking changes:** 5 (requires RFC/deprecation)

### Top 3 Priorities

1. **REC-001:** Add `template` command to main help (hidden feature, high user impact)
2. **REC-002:** Improve error actionability for "requires a value" messages (127 callsites)
3. **REC-003:** Move `acp` to main subcommand list (editor integration is key feature)

### Overall Assessment

| Audit Area | Score | Summary |
|------------|-------|---------|
| Heuristic Evaluation | 4.2/5 | Most commands well-designed; `template` and `acp` hidden |
| Flag Consistency | 3.8/5 | `--force` semantics vary; `--name` vs `--container` |
| Error Actionability | 3.2/5 | 59% lack remediation guidance |

---

## Quick Wins (implement now)

### REC-001: Add `template` command to main help

**Category:** Quick win
**Priority:** 5 × 4 = 20 (Impact × Frequency)
**Effort:** Low (add one line to `_containai_help()`)
**Breaking:** No
**Owner epic:** fn-36-rb7 | **Status:** new

**Current:** `template` command exists and works but is not listed in `cai help`
**Proposed:** Add to Configuration Commands section in main help
**Rationale:** Users cannot discover container customization feature. Discoverability score 1/5.

**Source:** Heuristic evaluation fn-46.1 - "CRITICAL ISSUE: Template is undocumented in `cai help`"

---

### REC-002: Add examples to "--flag requires a value" errors

**Category:** Quick win
**Priority:** 4 × 5 = 20 (127 callsites, frequent error)
**Effort:** Low (string template change)
**Breaking:** No
**Owner epic:** NEW | **Status:** new

**Current:** `[ERROR] --container requires a value`
**Proposed:** `[ERROR] --container requires a value. Example: --container mycontainer`
**Rationale:** Users don't know what valid values look like. Affects 127 callsites.

**Source:** Error audit fn-46.3 - Rank #1 worst error

---

### REC-003: Move `acp` to main subcommand list

**Category:** Quick win
**Priority:** 4 × 3 = 12 (editor integration is key feature)
**Effort:** Low (reorder help text)
**Breaking:** No
**Owner epic:** fn-36-rb7 | **Status:** new

**Current:** `acp` is buried after "Run Options" section, not with other subcommands
**Proposed:** Move to main "Subcommands" section alongside shell, run, exec
**Rationale:** Editor integration is primary use case for many users. Discoverability score 2/5.

**Source:** Heuristic evaluation fn-46.1 - "Issue: `acp` is a top-level subcommand but not listed with other subcommands"

---

### REC-004: Add `-w` short form to `status` command

**Category:** Quick win
**Priority:** 3 × 3 = 9
**Effort:** Low (add alias)
**Breaking:** No
**Owner epic:** fn-36-rb7 | **Status:** already planned

**Current:** `status` is only command missing `-w` for `--workspace`
**Proposed:** Add `-w` alias to match run, shell, exec, import, export, doctor, config, links
**Rationale:** Consistency across commands; muscle memory works everywhere.

**Source:** Flag audit fn-46.2 - "status missing -w"

---

### REC-005: Add `--container` alias to `cai links`

**Category:** Quick win
**Priority:** 3 × 2 = 6 (affects scripting users)
**Effort:** Low (add alias, keep --name working)
**Breaking:** No (alias first, deprecate later)
**Owner epic:** fn-36-rb7 | **Status:** partially planned

**Current:** `cai links` uses `--name` while all other commands use `--container`
**Proposed:** Add `--container` as alias, keep `--name` working (deprecate in REC-013)
**Rationale:** Consistent flag naming across all commands.

**Source:** Flag audit fn-46.2 - "HIGH Severity: `--name` vs `--container`"

---

### REC-006: Add "Container not found" remediation

**Category:** Quick win
**Priority:** 4 × 3 = 12 (9 callsites)
**Effort:** Low (string template change)
**Breaking:** No
**Owner epic:** NEW | **Status:** new

**Current:** `[ERROR] Container not found: foo`
**Proposed:** `[ERROR] Container not found: foo. Run 'cai status' to list containers, or 'cai run' to create one.`
**Rationale:** Users don't know what to do next. Score 2/5.

**Source:** Error audit fn-46.3 - Rank #3 worst error

---

### REC-007: Standardize build.sh error format

**Category:** Quick win
**Priority:** 2 × 2 = 4
**Effort:** Low (find/replace)
**Breaking:** No
**Owner epic:** NEW | **Status:** new

**Current:** `build.sh` uses `ERROR:` (33 occurrences)
**Proposed:** Use `[ERROR]` to match main CLI format
**Rationale:** Consistent error format aids parsing and recognition.

**Source:** Error audit fn-46.3 - "build.sh uses `ERROR:` instead of `[ERROR]`"

---

## Medium Effort (next release)

### REC-008: Add `cai docker --help` text

**Category:** Medium effort
**Priority:** 3 × 3 = 9
**Effort:** Medium (new help function)
**Breaking:** No
**Owner epic:** fn-36-rb7 | **Status:** new

**Current:** `cai docker --help` shows Docker's own help, not ContainAI's context behavior
**Proposed:** Add `_containai_docker_help()` explaining context injection and `-u agent`
**Rationale:** Experts need to understand how ContainAI wraps docker. Learnability score 3/5.

**Source:** Heuristic evaluation fn-46.1 - "`docker` has no dedicated help"

---

### REC-009: Document exit codes in more command help

**Category:** Medium effort
**Priority:** 3 × 3 = 9 (scripting users need this)
**Effort:** Medium (research + document)
**Breaking:** No
**Owner epic:** fn-45 | **Status:** already planned

**Current:** Only shell, exec, links, doctor document exit codes
**Proposed:** Add exit codes section to all command help
**Rationale:** Scripts need predictable exit code behavior.

**Source:** Heuristic evaluation fn-46.1 - "Exit codes inconsistently documented"

---

### REC-010: Document environment variables in help text

**Category:** Medium effort
**Priority:** 2 × 3 = 6
**Effort:** Medium (research + document)
**Breaking:** No
**Owner epic:** fn-45 | **Status:** already planned

**Current:** Only `update` mentions `CAI_CHANNEL`, `CAI_BRANCH`; `CONTAINAI_VERBOSE` not in command help
**Proposed:** Add "Environment Variables" section to relevant command help
**Rationale:** Power users need to know about env var configuration.

**Source:** Heuristic evaluation fn-46.1 - "Environment variables rarely documented"

---

### REC-011: Add `--json` output to more commands

**Category:** Medium effort
**Priority:** 3 × 3 = 9 (scripting/automation)
**Effort:** Medium (implement per command)
**Breaking:** No
**Owner epic:** fn-42 | **Status:** partially planned

**Current:** Only `doctor`, `status`, `version` support `--json`
**Proposed:** Add `--json` to: gc --dry-run, validate, links, template list
**Rationale:** Machine-parseable output for CI/CD and scripting.

**Source:** Flag audit fn-46.2 - "`--json` Limited Availability"

---

### REC-012: Improve config parse error messages

**Category:** Medium effort
**Priority:** 4 × 2 = 8
**Effort:** Medium (propagate Python parse error)
**Breaking:** No
**Owner epic:** NEW | **Status:** new

**Current:** `[ERROR] Failed to parse config file: /path` (no details)
**Proposed:** Show actual parse error from Python (line number, error type)
**Rationale:** Users can't fix config errors without knowing what's wrong.

**Source:** Error audit fn-46.3 - Rank #7 worst error

---

### REC-013: Deprecate `--name` in `cai links`

**Category:** Medium effort (requires deprecation period)
**Priority:** 3 × 2 = 6
**Effort:** Medium (warning + removal after 2 releases)
**Breaking:** Yes (after deprecation period)
**Owner epic:** fn-36-rb7 | **Status:** new

**Migration path:**
1. Release N: Add `--container` alias (REC-005)
2. Release N+1: Warn when `--name` used
3. Release N+2: Remove `--name`

**Current:** `--name` in links, `--container` everywhere else
**Proposed:** Normalize to `--container` only
**Rationale:** Consistent flag naming; `--name` deprecated elsewhere with "[ERROR] --name is no longer supported. Use --container instead."

**Source:** Flag audit fn-46.2 - "HIGH Severity: `--name` vs `--container`"

---

### REC-014: Deprecate `--restart` alias

**Category:** Medium effort
**Priority:** 2 × 2 = 4
**Effort:** Low (add warning, schedule removal)
**Breaking:** Yes (after deprecation period)
**Owner epic:** fn-36-rb7 | **Status:** new

**Migration path:**
1. Release N: Warn when `--restart` used
2. Release N+2: Remove `--restart`

**Current:** `--restart` and `--fresh` both work (aliases)
**Proposed:** Keep only `--fresh`
**Rationale:** Reduce cognitive load; one clear way to do it.

**Source:** Flag audit fn-46.2 - "`--restart` is Legacy Alias"

---

### REC-015: Add common short forms

**Category:** Medium effort
**Priority:** 2 × 3 = 6
**Effort:** Low per flag (but many flags)
**Breaking:** No
**Owner epic:** fn-36-rb7 | **Status:** partially planned

**Proposed additions:**
- `-c` for `--container`
- `-n` for `--dry-run` (GNU convention)
- `-f` for `--force`

**Note:** `-v` intentionally NOT added (reserved for `--version` per project convention)

**Rationale:** Common CLI conventions improve muscle memory.

**Source:** Flag audit fn-46.2 - "Missing Short Forms for Common Flags"

---

### REC-016: Clarify `validate` vs `doctor` relationship

**Category:** Medium effort
**Priority:** 2 × 2 = 4
**Effort:** Medium (docs + help text)
**Breaking:** No
**Owner epic:** fn-45 | **Status:** new

**Current:** Both commands check system; distinction not obvious
**Proposed:** Add help text: "`validate` checks isolation requirements (read-only); `doctor` diagnoses and fixes issues"
**Rationale:** Users confused about when to use which.

**Source:** Heuristic evaluation fn-46.1 - "Unclear when to use `validate` vs `doctor`"

---

### REC-017: Improve "missing label" container errors

**Category:** Medium effort
**Priority:** 3 × 3 = 9 (10 callsites)
**Effort:** Medium (context-aware error)
**Breaking:** No
**Owner epic:** NEW | **Status:** new

**Current:** `[ERROR] Container test is missing workspace label`
**Proposed:** `[ERROR] Container test is missing workspace label. This container may have been created outside ContainAI. Use 'cai stop && cai run' to recreate, or ignore with --force.`
**Rationale:** Users don't understand why label matters or how to fix.

**Source:** Error audit fn-46.3 - Rank #2 worst error

---

### REC-018: Add install hints for missing dependencies

**Category:** Medium effort
**Priority:** 3 × 2 = 6
**Effort:** Medium (per-dependency hints)
**Breaking:** No
**Owner epic:** NEW | **Status:** new

**Current:**
- `Docker is not installed or not in PATH` (no install link)
- `Python required to parse config` (no install hint)

**Proposed:**
- `Docker is not installed. Install: https://docs.docker.com/get-docker/`
- `Python 3 required. Install: apt install python3 (Linux) or brew install python (macOS)`

**Rationale:** Users can't proceed without knowing how to install.

**Source:** Error audit fn-46.3 - Ranks #8, #9 worst errors

---

### REC-019: Improve help for setup/doctor (add summary mode)

**Category:** Medium effort
**Priority:** 3 × 2 = 6
**Effort:** Medium (add --help-full pattern)
**Breaking:** No
**Owner epic:** fn-36-rb7 | **Status:** new

**Current:** `cai setup --help` shows 100+ lines of platform-specific detail
**Proposed:** Default `--help` shows summary; `--help-full` shows all detail
**Rationale:** Novices overwhelmed; experts still have access to detail.

**Source:** Heuristic evaluation fn-46.1 - "Help text overwhelming for setup/doctor"

---

### REC-020: Add `gc` alias or description for "cleanup"

**Category:** Medium effort
**Priority:** 2 × 2 = 4
**Effort:** Low (add description or alias)
**Breaking:** No
**Owner epic:** fn-45 | **Status:** new

**Current:** `gc` (garbage collection) may be jargon for novices
**Proposed:** Add description in help: "gc - Clean up unused containers and resources"
**Rationale:** "GC" is developer jargon not obvious to AI devs without Docker experience.

**Source:** Heuristic evaluation fn-46.1 - "`gc` jargon not user-friendly"

---

## Breaking Changes (requires RFC)

### REC-021: Rename `--force` in run/shell/exec to `--skip-isolation`

**Category:** Breaking change
**Priority:** 4 × 2 = 8 (semantic clarity)
**Effort:** High (deprecation cycle)
**Breaking:** Yes
**Owner epic:** NEW (requires RFC) | **Status:** new

**Migration path:**
1. Release N: Add `--skip-isolation` alias
2. Release N+1: Warn when `--force` used in run/shell/exec
3. Release N+3: Remove `--force` from run/shell/exec

**Current:** `--force` means different things:
- run/shell/exec: Skip isolation checks (testing only)
- stop/gc/uninstall: Skip confirmation prompts

**Proposed:** Rename to `--skip-isolation` or `--unsafe` in run/shell/exec
**Rationale:** Same flag should mean same thing everywhere. Current usage is confusing.

**Source:** Flag audit fn-46.2 - "HIGH Severity: `--force` Meaning Varies by Command"

---

### REC-022: Document `--acp` flag deprecation

**Category:** Breaking change (documentation of existing state)
**Priority:** 2 × 1 = 2
**Effort:** Low (documentation)
**Breaking:** No (already deprecated in code)
**Owner epic:** fn-45 | **Status:** new

**Current:** `--acp` (flag form) exists alongside `acp` (subcommand); deprecated but undocumented
**Proposed:** Add deprecation note: "Use `cai acp` instead of `cai --acp`"
**Rationale:** Experts may encounter `--acp` in old scripts.

**Source:** Heuristic evaluation fn-46.1 - "Legacy `--acp` vs `acp` subcommand confusing"

---

### REC-023: Clarify unknown command routing behavior

**Category:** Breaking change (behavior documentation, consider fix)
**Priority:** 3 × 2 = 6
**Effort:** Medium (error message improvement)
**Breaking:** Potentially (if behavior changes)
**Owner epic:** NEW | **Status:** new

**Current:** `cai stattus` (typo) produces `[ERROR] Unknown option: stattus` (routes to `run`, fails)
**Proposed:** Either:
  A. Add explicit unknown command check before routing to `run`
  B. Change error message: `[ERROR] Unknown command: stattus. Did you mean: status? Use 'cai --help' for commands.`
**Rationale:** "Unknown option" is confusing when user intended a command.

**Source:** Heuristic evaluation fn-46.1, Error audit fn-46.3 - "Unknown commands route to `run` dispatcher"

---

### REC-024: Consider positional vs flag standardization

**Category:** Breaking change (documentation/guidance)
**Priority:** 2 × 2 = 4
**Effort:** Medium (documentation + deprecation plan)
**Breaking:** Potentially (if positional deprecated)
**Owner epic:** fn-45 | **Status:** new

**Current:** Commands accept workspace as both positional AND flag:
- `cai run /path` OR `cai run --workspace /path`
- `cai shell /path` OR `cai shell --workspace /path`

**Proposed:** Document clearly; prefer flag in docs; consider deprecating positional in v2
**Rationale:** Two ways to do same thing increases cognitive load.

**Source:** Flag audit fn-46.2 - "`--workspace` vs Positional Workspace"

---

### REC-025: Remove legacy security flag parsing

**Category:** Breaking change (cleanup)
**Priority:** 1 × 1 = 1 (internal cleanup)
**Effort:** Low (remove dead code)
**Breaking:** No (flags already rejected at runtime)
**Owner epic:** NEW | **Status:** new

**Current:** Legacy flags parsed but rejected:
- `--mount-docker-socket`
- `--allow-host-credentials`
- `--allow-host-docker-socket`
- `--please-root-my-host`
- `--i-understand-this-exposes-host-credentials`
- `--i-understand-this-grants-root-access`

**Proposed:** Remove parsing entirely (they error anyway)
**Rationale:** Dead code cleanup; flags already rejected with "no longer supported" error.

**Source:** Flag audit fn-46.2 - "LEGACY FLAGS"

---

## Appendix A: Full Audit Data

### Heuristic Scores Table

| Command | Discoverability | Learnability | Efficiency | Error Prevention | Avg |
|---------|-----------------|--------------|------------|------------------|-----|
| run | 5 | 4 | 5 | 4 | 4.5 |
| shell | 5 | 5 | 5 | 5 | 5.0 |
| exec | 5 | 5 | 4 | 4 | 4.5 |
| doctor | 5 | 4 | 4 | 5 | 4.5 |
| setup | 5 | 3 | 5 | 4 | 4.25 |
| validate | 4 | 4 | 5 | 4 | 4.25 |
| docker | 4 | 3 | 5 | 3 | 3.75 |
| import | 4 | 4 | 4 | 4 | 4.0 |
| export | 5 | 5 | 4 | 4 | 4.5 |
| sync | 4 | 4 | 4 | 5 | 4.25 |
| stop | 5 | 5 | 4 | 5 | 4.75 |
| status | 5 | 5 | 5 | 4 | 4.75 |
| gc | 4 | 5 | 4 | 5 | 4.5 |
| ssh | 4 | 4 | 4 | 4 | 4.0 |
| links | 4 | 4 | 4 | 4 | 4.0 |
| config | 4 | 4 | 4 | 3 | 3.75 |
| **template** | **1** | 4 | 4 | 4 | **3.25** |
| completion | 4 | 5 | 5 | 4 | 4.5 |
| update | 5 | 4 | 4 | 5 | 4.5 |
| refresh | 4 | 4 | 5 | 4 | 4.25 |
| uninstall | 5 | 5 | 4 | 5 | 4.75 |
| version | 5 | 5 | 5 | 5 | 5.0 |
| **acp** | **2** | 3 | 4 | 3 | **3.0** |
| sandbox | 3 | 4 | N/A | 4 | 3.67 |

**Lowest scores:** acp (3.0), template (3.25), config (3.75), docker (3.75)

### Flag Consistency Matrix Summary

| Issue | Severity | Status |
|-------|----------|--------|
| `--name` vs `--container` in links | HIGH | REC-005, REC-013 |
| `--force` meaning varies | HIGH | REC-021 |
| `-w` missing from status | MEDIUM | REC-004 |
| Positional vs flag workspace | MEDIUM | REC-024 |
| `--json` limited | MEDIUM | REC-011 |
| `--restart` legacy alias | LOW | REC-014 |
| Missing short forms | LOW | REC-015 |

### Error Message Templates with Scores

**Top 10 Worst (by score × frequency):**

| Rank | Template | Callsites | Score | Recommendation |
|------|----------|-----------|-------|----------------|
| 1 | `--{flag} requires a value` | 127 | 2 | REC-002 |
| 2 | `Container {name} is missing {label} label` | 10 | 2 | REC-017 |
| 3 | `Container not found: {name}` | 9 | 2 | REC-006 |
| 4 | `Failed to resolve data volume` | 8 | 1 | NEW |
| 5 | `Container {name} exists but is not managed` | 8 | 2 | REC-017 |
| 6 | `Failed to determine script directory` | 4 | 1 | Internal error |
| 7 | `Failed to parse config file: {path}` | 4 | 2 | REC-012 |
| 8 | `Docker is not installed or not in PATH` | 1 | 2 | REC-018 |
| 9 | `Python required to parse config: {path}` | 2 | 2 | REC-018 |
| 10 | `Container not found for workspace: {path}` | 2 | 2 | REC-006 |

**Error Categories by Remediation Rate:**

| Category | Count | % with Remediation |
|----------|-------|-------------------|
| Isolation/Setup | 240+ | ~95% (model for others) |
| Flag/Option | 127+ | 38% |
| Docker | 16 | 38% |
| Build | 33 | 32% |
| Container | 42 | 17% |
| Config | 45 | 0% |
| File/Path | 12 | 0% |

---

## Appendix B: Epic Cross-Reference

| Recommendation | Owner Epic | Status |
|----------------|------------|--------|
| REC-001 | fn-36-rb7 | new |
| REC-002 | NEW | new |
| REC-003 | fn-36-rb7 | new |
| REC-004 | fn-36-rb7 | already planned |
| REC-005 | fn-36-rb7 | partially planned |
| REC-006 | NEW | new |
| REC-007 | NEW | new |
| REC-008 | fn-36-rb7 | new |
| REC-009 | fn-45 | already planned |
| REC-010 | fn-45 | already planned |
| REC-011 | fn-42 | partially planned |
| REC-012 | NEW | new |
| REC-013 | fn-36-rb7 | new |
| REC-014 | fn-36-rb7 | new |
| REC-015 | fn-36-rb7 | partially planned |
| REC-016 | fn-45 | new |
| REC-017 | NEW | new |
| REC-018 | NEW | new |
| REC-019 | fn-36-rb7 | new |
| REC-020 | fn-45 | new |
| REC-021 | NEW (RFC) | new |
| REC-022 | fn-45 | new |
| REC-023 | NEW | new |
| REC-024 | fn-45 | new |
| REC-025 | NEW | new |

**Summary by epic:**

| Epic | Recommendations |
|------|-----------------|
| fn-36-rb7 (CLI UX Consistency) | 9 (REC-001, 003, 004, 005, 008, 013, 014, 015, 019) |
| fn-42 (CLI UX Fixes) | 1 (REC-011) |
| fn-45 (Documentation) | 6 (REC-009, 010, 016, 020, 022, 024) |
| NEW epic needed | 9 (REC-002, 006, 007, 012, 017, 018, 021, 023, 025) |

---

## Methodology

This document synthesizes findings from three audit tasks:

1. **fn-46.1 Heuristic Evaluation** (`.flow/specs/cli-ux-heuristic-evaluation.md`)
   - 24 commands evaluated against clig.dev, GNU, POSIX standards
   - Scoring rubric: Discoverability, Learnability, Efficiency, Error Prevention
   - Help text completeness checklist applied

2. **fn-46.2 Flag Consistency Audit** (`.flow/specs/flag-naming-consistency-audit.md`)
   - Comprehensive flag matrix from help text AND source code
   - Identified 7 inconsistencies (2 HIGH, 3 MEDIUM, 2 LOW severity)
   - Convention compliance assessment (POSIX/GNU, clig.dev)

3. **fn-46.3 Error Message Audit** (`docs/reports/fn-46.3-error-message-audit.md`)
   - 620 `_cai_error` calls, 515 direct `[ERROR]` messages, 33 build.sh errors
   - ~85 unique templates identified and scored
   - Overall actionability: 3.2/5 (59% lack remediation)

**Prioritization Formula:** Impact (1-5) × Frequency (1-5) = Priority score
- Impact: How much does this affect user experience?
- Frequency: How often do users encounter this?
- Tie-breaker: Lower effort wins
