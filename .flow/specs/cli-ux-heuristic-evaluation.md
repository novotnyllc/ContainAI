# CLI UX Heuristic Evaluation - Task fn-46.1

## Command Inventory (Programmatically Derived)

### Case Arm Commands (dispatch case statement)
Extracted via: `awk '/^containai\(\)/,/^}/' src/containai.sh | grep -E '^[[:space:]]+[a-z-]+.*\)' | ...`
Note: Uses POSIX `[[:space:]]` instead of `\s` for cross-platform compatibility.

| Command | Case Pattern | Route |
|---------|-------------|-------|
| completion | `completion)` | `_containai_completion_cmd` |
| config | `config)` | `_containai_config_cmd` |
| docker | `docker)` | `_containai_docker_cmd` |
| doctor | `doctor)` | `_containai_doctor_cmd` |
| exec | `exec)` | `_containai_exec_cmd` |
| export | `export)` | `_containai_export_cmd` |
| gc | `gc)` | `_containai_gc_cmd` |
| help | `help \| -h \| --help)` | `_containai_help` |
| import | `import)` | `_containai_import_cmd` |
| links | `links)` | `_containai_links_cmd` |
| refresh | `refresh)` + `--refresh)` | `_cai_refresh` |
| run | `run)` | `_containai_run_cmd` |
| sandbox | `sandbox)` | `_containai_sandbox_cmd` (deprecated) |
| setup | `setup)` | `_cai_setup` |
| shell | `shell)` | `_containai_shell_cmd` |
| ssh | `ssh)` | `_containai_ssh_cmd` |
| status | `status)` | `_containai_status_cmd` |
| stop | `stop)` | `_containai_stop_cmd` |
| sync | `sync)` | `_cai_sync_cmd` |
| template | `template)` | `_containai_template_cmd` |
| uninstall | `uninstall)` | `_cai_uninstall` |
| update | `update)` | `_cai_update` |
| validate | `validate)` | `_cai_secure_engine_validate` |
| version | `version \| --version \| -v)` | `_cai_version` |

**Total: 24 commands** (including deprecated `sandbox`)

### Pre-Case If-Routes
Extracted via: `grep -E '== "[a-z-]+"'` in containai() (matches both `acp` and `--acp`)

| Route | Pattern | Handler |
|-------|---------|---------|
| `acp` | `$subcommand == "acp"` | `_containai_acp_cmd` |
| `--acp` | `$subcommand == "--acp"` | `_containai_acp_proxy` (legacy) |

### Flag-Based Case Arms
| Flag | Command | Note |
|------|---------|------|
| `--refresh` | refresh | Alias in case statement |
| `--version`, `-v` | version | Multi-pattern case arm |
| `--help`, `-h` | help | Multi-pattern case arm |

### Discrepancies: Dispatch vs Help

| Command | In Dispatch | In `cai help` | Issue |
|---------|------------|---------------|-------|
| `template` | Yes | No | **Not documented** in main help |
| `acp` | Yes (pre-case) | Yes (buried under "Subcommands" after "Run Options") | Listed but not in main list |
| `sandbox` | Yes | Yes (marked deprecated) | OK |
| `--refresh` | Yes | Yes ("also available as --refresh") | OK |

**Finding: `template` command is hidden from `cai help` output but is fully functional.**

---

## Evaluation Framework

### Heuristics Applied
Based on clig.dev, GNU coding standards, and POSIX utility conventions:

1. **Discoverability** - Can users find the command?
2. **Learnability** - Can users understand how to use it?
3. **Efficiency** - How many steps for common tasks?
4. **Error Prevention** - Does it prevent mistakes?

### Scoring Rubric (1-5)

| Score | Discoverability | Learnability | Efficiency | Error Prevention |
|-------|-----------------|--------------|------------|------------------|
| 1 | Can't find from help | Help text confusing | Many steps for simple task | Easy to make mistakes |
| 2 | Buried in help | Help text incomplete | Unnecessary flags required | Some footguns |
| 3 | Findable with effort | Help text adequate | Reasonable workflow | Warns on common errors |
| 4 | Easily findable | Help text good | Streamlined workflow | Prevents common errors |
| 5 | Obvious/intuitive | Help text excellent | Minimal user effort | Fail-safe design |

---

## Heuristic Evaluation by Command

### Core Commands (Happy Path)

#### `run` (default command)
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 5 | Default when no subcommand; prominently documented |
| Learnability | 4 | Comprehensive help; many options may overwhelm novices |
| Efficiency | 5 | `cai` alone starts container; positional path arg supported |
| Error Prevention | 4 | Auto-creates container; --dry-run available; --force required for risky ops |

**Persona A (Alex)**: Excellent - `cai` just works. May be confused by many advanced options.
**Persona B (Dana)**: Good - All options documented; could use better option grouping.

#### `shell`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 5 | Listed in main help |
| Learnability | 5 | Excellent help with exit codes, connection handling, examples |
| Efficiency | 5 | `cai shell` - two words |
| Error Prevention | 5 | Auto-retry on transient failures; clear exit codes |

**Persona A**: Excellent - "Open shell in container" is exactly what novices expect.
**Persona B**: Excellent - Exit codes documented; SSH direct access noted.

#### `exec`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 5 | Listed in main help |
| Learnability | 5 | Clear usage, -- separator explained, TTY handling noted |
| Efficiency | 4 | Requires command; `-w` short form available |
| Error Prevention | 4 | Exit codes documented; login shell behavior noted |

**Persona A**: Good - May not need often; clear when needed.
**Persona B**: Excellent - Scripting-friendly with clear exit codes.

#### `doctor`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 5 | Listed in main help |
| Learnability | 4 | Comprehensive but very long help (platform-conditional) |
| Efficiency | 4 | `cai doctor fix --all` for one-shot fix |
| Error Prevention | 5 | `fix` subcommand with targets; dry-run supported |

**Persona A**: Good - "Check system" is intuitive; fix targets may be confusing.
**Persona B**: Excellent - JSON output; granular fix targets.

#### `setup`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 5 | Listed in main help |
| Learnability | 3 | Very long help (100+ lines); lots of platform-specific detail |
| Efficiency | 5 | Single command handles everything |
| Error Prevention | 4 | --dry-run available; platform auto-detected |

**Persona A**: Overwhelming help text; but command itself is simple.
**Persona B**: Appreciates detail but could use --help summary vs --help-full.

#### `import`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 4 | Listed but "Sync host configs" less intuitive than "import secrets" |
| Learnability | 4 | Good help; two modes (hot-reload vs volume-only) may confuse |
| Efficiency | 4 | Hot-reload is automatic with workspace; good |
| Error Prevention | 4 | --no-secrets flag; warnings about additional_paths |

**Persona A**: May not understand difference between modes.
**Persona B**: Appreciates granular control.

### Container Lifecycle Commands

#### `stop`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 5 | Listed in main help |
| Learnability | 5 | Clear options; session warning explained |
| Efficiency | 4 | Interactive selection; --all for batch |
| Error Prevention | 5 | Session detection; --export before stop; --force required |

**Persona A**: Simple and safe.
**Persona B**: Appreciates --export workflow.

#### `status`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 5 | Listed in main help |
| Learnability | 5 | Clear output fields; JSON available |
| Efficiency | 5 | Defaults to current workspace |
| Error Prevention | 4 | Graceful timeout handling |

**Persona A**: Excellent - just shows status.
**Persona B**: JSON output for scripting.

#### `gc`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 4 | Listed but "GC" may be jargon for novices |
| Learnability | 5 | Excellent help with protection rules |
| Efficiency | 4 | --force for non-interactive |
| Error Prevention | 5 | Protection rules; --dry-run; confirmation prompt |

**Persona A**: May not understand "garbage collection".
**Persona B**: Excellent safeguards.

### Configuration Commands

#### `config`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 4 | Listed in main help |
| Learnability | 4 | Subcommands (list/get/set/unset) clear; scoping may confuse |
| Efficiency | 4 | Reasonable for config management |
| Error Prevention | 3 | Scoping rules complex; easy to set in wrong scope |

**Persona A**: May not need; if needed, `list` is discoverable.
**Persona B**: Good but scoping precedence takes learning.

#### `template`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 1 | **NOT in main help output** |
| Learnability | 4 | Good help when found |
| Efficiency | 4 | `upgrade` subcommand is intuitive |
| Error Prevention | 4 | --dry-run available |

**CRITICAL ISSUE: Template is undocumented in `cai help`.**

**Persona A**: Won't find it.
**Persona B**: Power users might grep source; still problematic.

### Maintenance Commands

#### `update`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 5 | Listed in main help |
| Learnability | 4 | Comprehensive; channel/branch options complex |
| Efficiency | 4 | Single command; container handling clear |
| Error Prevention | 5 | Prompts for container stop; --dry-run |

**Persona A**: May be confused by channel options.
**Persona B**: Good control over update process.

#### `refresh`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 4 | Listed; also `--refresh` |
| Learnability | 4 | Clear what it does |
| Efficiency | 5 | Simple action |
| Error Prevention | 4 | Warns about template upgrade |

**Note**: Dual syntax (`refresh` and `--refresh`) may confuse.

#### `uninstall`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 5 | Listed in main help |
| Learnability | 5 | Clear what's preserved vs removed |
| Efficiency | 4 | Options for containers/volumes |
| Error Prevention | 5 | Confirmation prompts; --dry-run |

**Both personas**: Well-designed for risky operation.

### Advanced/Utility Commands

#### `validate`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 4 | Listed but purpose less clear than "doctor" |
| Learnability | 4 | Clear validation checks |
| Efficiency | 5 | Single command |
| Error Prevention | 4 | Read-only checks |

**Overlap with doctor**: Users may not understand when to use validate vs doctor.

#### `docker`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 4 | Listed in main help |
| Learnability | 3 | **No dedicated help function** - no `cai docker --help` |
| Efficiency | 5 | Pass-through to docker |
| Error Prevention | 3 | Silently uses context; may surprise users |

**Missing: Dedicated help text for `cai docker`.**

#### `ssh`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 4 | Listed in main help |
| Learnability | 4 | Good help for cleanup subcommand |
| Efficiency | 4 | `ssh cleanup` is clear |
| Error Prevention | 4 | --dry-run available |

**Only has `cleanup` subcommand; name may suggest more.**

#### `links`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 4 | Listed in main help |
| Learnability | 4 | Clear subcommands (check/fix) |
| Efficiency | 4 | Reasonable |
| Error Prevention | 4 | --dry-run for fix |

**Persona A**: Won't need; internal detail.
**Persona B**: Useful for troubleshooting.

#### `export`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 5 | Listed in main help |
| Learnability | 5 | Clear options; auto-naming |
| Efficiency | 4 | Simple export; good defaults |
| Error Prevention | 4 | Directory must exist |

Good complement to `import`.

#### `sync`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 4 | Listed but noted "(In-container)" |
| Learnability | 4 | Good help; security notes |
| Efficiency | 4 | Single command |
| Error Prevention | 5 | Container detection; path validation |

**Persona A**: Won't run directly; runs inside container.
**Persona B**: Understands use case.

#### `completion`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 4 | Listed in main help |
| Learnability | 5 | Installation instructions included |
| Efficiency | 5 | Standard pattern |
| Error Prevention | 4 | N/A |

Standard and well-documented.

#### `acp`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 2 | Listed but **buried** after "Run Options" section |
| Learnability | 3 | Minimal help; relies on binary --help |
| Efficiency | 4 | `cai acp proxy claude` is clear |
| Error Prevention | 3 | Usage message on error |

**Issue: `acp` is a top-level subcommand but not listed with other subcommands.**

#### `sandbox` (deprecated)
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 3 | Listed as deprecated |
| Learnability | 4 | Clear migration guidance |
| Efficiency | N/A | Deprecated |
| Error Prevention | 4 | Shows deprecation message |

Handled correctly for deprecation.

#### `version`
| Criterion | Score | Notes |
|-----------|-------|-------|
| Discoverability | 5 | Listed; --version/-v work |
| Learnability | 5 | Simple; JSON available |
| Efficiency | 5 | Standard |
| Error Prevention | N/A | Read-only |

Standard and correct.

---

## Help Text Completeness Checklist

| Command | Synopsis | Description | Options | Grouping | Examples (2+) | Exit Codes | Env Vars | Stdout/Stderr | Related Cmds | Deprecation |
|---------|----------|-------------|---------|----------|---------------|------------|----------|---------------|--------------|-------------|
| run | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| shell | [x] | [x] | [x] | [ ] | [x] | [x] | [ ] | [ ] | [x] (ssh) | N/A |
| exec | [x] | [x] | [x] | [ ] | [x] | [x] | [ ] | [x] | [ ] | N/A |
| doctor | [x] | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | [x] (setup) | N/A |
| setup | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| validate | [x] | [x] | [x] | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| docker | [ ] | [x] | [ ] | N/A | [ ] | [ ] | [ ] | [ ] | [ ] | N/A |
| import | [x] | [x] | [x] | [ ] | [x] | [ ] | [ ] | [ ] | [x] (export) | N/A |
| export | [x] | [x] | [x] | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| sync | [x] | [x] | [x] | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| stop | [x] | [x] | [x] | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| status | [x] | [x] | [x] | [ ] | [x] | [ ] | [ ] | [x] | [ ] | N/A |
| gc | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| ssh | [x] | [x] | [x] | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| links | [x] | [x] | [x] | [ ] | [x] | [x] | [ ] | [ ] | [ ] | N/A |
| config | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| template | [x] | [x] | [x] | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| completion | [x] | [x] | [ ] | N/A | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| update | [x] | [x] | [x] | [x] | [x] | [ ] | [x] | [ ] | [x] (doctor) | N/A |
| refresh | [x] | [x] | [x] | [ ] | [x] | [ ] | [ ] | [ ] | [x] (template) | N/A |
| uninstall | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | [ ] | [x] (setup) | N/A |
| version | [x] | [x] | [x] | N/A | [x] | [ ] | [ ] | [ ] | [ ] | N/A |
| acp | [ ] | [ ] | [ ] | N/A | [ ] | [ ] | [ ] | [ ] | [ ] | N/A |
| sandbox | [x] | [x] | N/A | N/A | [ ] | [ ] | [ ] | [ ] | [x] | [x] |

**Summary**: Most commands have synopsis, description, options, and examples. Gaps:
- Exit codes rarely documented (only shell, exec, links, doctor)
- Environment variables rarely mentioned (only update)
- Related commands rarely cross-linked
- `acp` and `docker` lack dedicated help text

---

## Top 5 Usability Issues by Persona

### Persona A: "Alex the AI Dev" (Novice)

1. **`template` command is undiscoverable** (P1)
   - Not listed in `cai help`
   - Novices wanting to customize containers can't find it
   - Impact: High (blocks customization journey)
   - Fix: Add to main help under appropriate section

2. **Help text overwhelming for setup/doctor** (P2)
   - 100+ lines of platform-specific detail
   - Novices just want "did it work?"
   - Impact: Medium (cognitive overload)
   - Fix: Consider `--help` summary vs `--help-full` pattern

3. **`acp` buried in help output** (P3)
   - Listed after "Run Options" section, not with other subcommands
   - Editor integration is a key feature
   - Impact: Medium (feature hidden)
   - Fix: Move to main subcommand list

4. **`gc` jargon not user-friendly** (P4)
   - "Garbage collection" is developer jargon
   - Novices may not understand purpose
   - Impact: Low (rarely needed by novices)
   - Fix: Consider alias like `cleanup` or better description

5. **Unclear when to use `validate` vs `doctor`** (P5)
   - Both check system; distinction not obvious
   - Impact: Low (both work; just confusing)
   - Fix: Clarify relationship in help text

### Persona B: "Dana the DevOps Engineer" (Expert)

1. **`docker` has no dedicated help** (P1)
   - `cai docker --help` shows docker's help, not cai's context behavior
   - Experts want to know how cai wraps docker
   - Impact: Medium (undocumented behavior)
   - Fix: Add `_containai_docker_help` function

2. **Exit codes inconsistently documented** (P2)
   - Only shell/exec/links/doctor document exit codes
   - Experts need for scripting
   - Impact: Medium (scripting reliability)
   - Fix: Document exit codes for all commands

3. **Environment variables rarely documented** (P3)
   - Only `update` mentions `CAI_CHANNEL`, `CAI_BRANCH`
   - `CONTAINAI_VERBOSE` not documented in command help
   - Impact: Medium (advanced config hidden)
   - Fix: Add "Environment Variables" section to relevant commands

4. **No `--json` for import/export operations** (P4)
   - Experts want machine-parseable output
   - Only status, doctor, version have `--json`
   - Impact: Low (can work around)
   - Fix: Add `--json` to import/export for scripting

5. **Legacy `--acp` vs `acp` subcommand confusing** (P5)
   - Both exist; `--acp` is deprecated but undocumented
   - Experts may encounter in old scripts
   - Impact: Low (works; just confusing)
   - Fix: Document deprecation of `--acp` flag

---

## Quick Wins (Easy Fixes)

| Issue | Fix | Effort | Impact |
|-------|-----|--------|--------|
| `template` not in help | Add to `_containai_help()` | Low | High |
| `acp` buried in help | Move to main subcommand list | Low | Medium |
| `docker` no help text | Add `_containai_docker_help()` | Medium | Medium |
| Exit codes undocumented | Add to each help function | Medium | Medium |
| `--acp` deprecation | Add note in main help | Low | Low |

---

## Flag Consistency Observations

### Global Flags (should be consistent)
| Flag | Pattern | Status |
|------|---------|--------|
| `--verbose` | Long form only | Consistent |
| `--quiet`, `-q` | Long and short | Consistent |
| `--dry-run` | Long form only | Consistent |
| `--help`, `-h` | Long and short | Consistent |
| `--force` | Long form only | Consistent |
| `--workspace`, `-w` | Long and short | Mostly consistent (only `status` missing `-w`) |
| `--container` | Long form only | Consistent |
| `--config` | Long form only | Consistent |

### Flag Naming Conventions
| Pattern | Examples | Issue |
|---------|----------|-------|
| `--data-volume` | import, export, shell, run | Hyphenated, good |
| `--no-excludes` | import, export | `--no-` prefix for negation, good |
| `--no-secrets` | import | Consistent |
| `--skip-templates` | setup | Uses `--skip-` instead of `--no-`, minor inconsistency |
| `--build-templates` | doctor | Matches naming |

**Minor Issue**: `--skip-templates` vs potential `--no-templates` pattern inconsistency.

---

## Unknown Command Routing

**Finding**: Unknown subcommands are delegated to `run`; if the token matches an existing directory it is treated as a workspace, otherwise `run` errors with "Unknown option: {token}".

```bash
cai unknowncommand  # Routes to run, fails with "[ERROR] Unknown option: unknowncommand"
cai ./mydir         # Routes to run, treats ./mydir as workspace path if it exists
```

**Impact**: Typos produce "Unknown option" error (not "Unknown command"), which can be confusing. However, the error does include help suggestions.
**Recommendation**: Consider adding explicit unknown command validation before routing to run, or at least emitting "Unknown command" instead of "Unknown option" for non-directory tokens.

---

## Summary Scores

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

**Lowest Scores**: `acp` (3.0), `template` (3.25), `config` (3.75), `docker` (3.75)

---

## Next Steps (for fn-46.2+)

This evaluation feeds into:
- **fn-46.2**: Flag consistency audit (detailed flag matrix)
- **fn-46.3**: Error message audit (actionability scoring)
- **fn-46.4**: Simplification opportunities
- **fn-46.5**: Final recommendations document
