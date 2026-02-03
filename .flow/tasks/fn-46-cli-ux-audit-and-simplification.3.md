# fn-46-cli-ux-audit-and-simplification.3 Error message actionability audit

## Description
Audit all error messages for actionability, consistency, and helpfulness. Users should know what went wrong AND how to fix it. Uses comprehensive extraction methodology with **strictly non-destructive testing only**.

**Size:** M
**Files:** Analysis output only (no code changes)

## Approach

### Step 1: Comprehensive Error Extraction

**a) Static extraction (all patterns):**
```bash
# _cai_error calls (primary)
grep -rn '_cai_error' src/*.sh src/lib/*.sh

# printf to stderr
grep -rn "printf.*>&2" src/*.sh src/lib/*.sh

# echo [ERROR] pattern
grep -rn '\[ERROR\]' src/*.sh src/lib/*.sh

# echo to stderr without [ERROR]
grep -rn "echo.*>&2" src/*.sh src/lib/*.sh | grep -v '\[ERROR\]'
```

**b) Dynamic/runtime errors (STRICTLY NON-DESTRUCTIVE scenarios):**

**SAFETY CONSTRAINT**: Only use `--help`, `--dry-run`, `status`, `validate`, or read-only commands.
**FORBIDDEN**: `cai shell`, `cai run`, `cai update`, `cai uninstall` (can create/modify state)
**NOTE**: `cai setup --dry-run` is safe (preview only) and included in test scenarios below.

| Scenario | Safe Test Command | Expected Error |
|----------|-------------------|----------------|
| Invalid container name | `cai status --container nonexistent` | Container not found |
| Invalid path | `cai validate --config /nonexistent/config.toml` | File not found |
| Unknown option | `cai status --badoption` | Unknown option |
| Missing flag value | `cai status --container` | Flag needs value |
| Config validation | `cai validate` (with broken config) | Config parse error |
| Dry-run mode | `cai setup --dry-run` | Preview only, no mutations |
| Version check | `cai version --json` | JSON output (verify format) |

**Note**: Unknown commands route to `run` (not "unknown command" error). Document this as a UX finding - it may cause confusion when users typo a command name.

**c) Upstream tool errors (from code review, not live execution):**

Review error handling in code to categorize:
- **Raw upstream**: Docker/SSH errors passed through unchanged
- **Wrapped with remediation**: Error caught and user guidance added

```bash
# Find error handling patterns for external commands
grep -rn 'docker.*||' src/*.sh src/lib/*.sh | head -20
grep -rn 'ssh.*||' src/*.sh src/lib/*.sh | head -20
```

### Step 2: Dedupe Strategy

**Group by normalized message template:**
- Strip variable parts: container names, paths, numbers
- Template: `"Container '{}' not found"` with example instances

**Track unique templates + callsites:**
| Template | Callsites | Example | Score |
|----------|-----------|---------|-------|
| Container '{}' not found | 5 | Container 'foo' not found | 2 |

### Step 3: Score Each Message (1-5)

| Score | Description | Example |
|-------|-------------|---------|
| 1 | Cryptic/unhelpful | "Error" |
| 2 | Explains problem, no solution | "Container not found" |
| 3 | Explains problem, vague solution | "Container not found. Check name." |
| 4 | Clear problem and solution | "Container 'foo' not found. Run 'cai run' to create it." |
| 5 | Clear problem, solution, and prevention | "Container 'foo' not found. Run 'cai run' to create, or 'cai status' to list existing." |

### Step 4: Categorize Findings

**By error type:**
- User input errors (typos, wrong flags)
- State errors (container not running, not found)
- Environment errors (Docker not installed, permissions)
- External errors (network, Docker daemon, SSH)

**By actionability gap:**
- No action suggested (score 1-2)
- Vague action (score 3)
- Specific action but no alternatives (score 4)

### Step 5: Audit Priority Areas

Focus on high-frequency error scenarios (from static analysis):
- Container not found errors
- Configuration parse errors
- Docker/Sysbox not available
- SSH connection failures
- Volume mount failures
- Permission denied errors
- Missing dependencies

## Key context

Error message patterns from conventions:
```bash
# Standard format
_cai_error "Message here"  # Uses [ERROR] prefix

# Good: actionable
"[ERROR] Container 'foo' not found. Run 'cai run' to create it."

# Bad: not actionable
"[ERROR] Container not found"
```

**UX Finding to Document**: Unknown commands silently route to `run` instead of showing an error. This can cause confusion when users typo command names (e.g., `cai stattus` tries to run a container named `stattus`).

## Acceptance
- [ ] All error patterns extracted via static analysis
- [ ] Strictly non-destructive misuse scenarios tested (status, validate, --help, --dry-run)
- [ ] Unknown command routing behavior documented as UX finding
- [ ] Upstream errors categorized (raw vs wrapped) from code review
- [ ] Dedupe strategy applied (templates with examples)
- [ ] Each template scored for actionability (1-5)
- [ ] Inconsistent format errors flagged
- [ ] Top 10 worst error messages identified (lowest scores, highest frequency)
- [ ] Suggested improvements for low-scoring messages
- [ ] Raw upstream errors flagged for wrapping consideration

## Done summary
Completed comprehensive error message actionability audit. Analyzed 620 _cai_error calls, 515 direct [ERROR] messages, and 33 build.sh ERROR: patterns. Identified ~85 unique message templates with overall actionability score of 3.2/5.

Key findings:
1. 59% of messages lack remediation guidance
2. build.sh uses inconsistent 'ERROR:' format vs '[ERROR]'
3. Isolation/Setup errors have highest remediation rate (~95%)
4. Top 10 worst messages identified with specific improvement recommendations
5. Unknown commands route to `run` dispatcher and fail as "Unknown option: {typo}" (UX issue documented)

All testing was strictly non-destructive (--help, --dry-run, status, validate only). Report saved to docs/reports/fn-46.3-error-message-audit.md
## Evidence
- Commits: e94a5c5
- Tests: Non-destructive runtime tests only (status, validate, --help, --dry-run)
- PRs:
