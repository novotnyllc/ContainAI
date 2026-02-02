# fn-46-cli-ux-audit-and-simplification.3 Error message actionability audit

## Description
Audit all error messages for actionability, consistency, and helpfulness. Users should know what went wrong AND how to fix it.

**Size:** M
**Files:** Analysis output only (no code changes)

## Approach

1. Extract error messages from:
   - `grep -n '\[ERROR\]' src/*.sh src/lib/*.sh`
   - `grep -n 'echo.*>&2' src/*.sh src/lib/*.sh`
   - `grep -n '_cai_error' src/*.sh src/lib/*.sh`

2. Evaluate each error message:
   - **Clarity**: Does it explain what went wrong?
   - **Actionability**: Does it tell user how to fix it?
   - **Consistency**: Does it follow `[ERROR]` format per conventions?
   - **Context**: Does it include relevant details (file, flag, value)?

3. Score each message:
   - 1 = Cryptic/unhelpful
   - 2 = Explains problem, no solution
   - 3 = Explains problem, vague solution
   - 4 = Clear problem and solution
   - 5 = Clear problem, solution, and prevention

4. Known areas to audit:
   - Container not found errors
   - Configuration parse errors
   - Docker/Sysbox not available
   - SSH connection failures
   - Volume mount failures

## Key context

Error message patterns from conventions:
```bash
# Standard format
_cai_error "Message here"  # Uses [ERROR] prefix
echo "[ERROR] message" >&2  # Direct stderr

# Good: actionable
"[ERROR] Container 'foo' not found. Run 'cai run' to create it."

# Bad: not actionable
"[ERROR] Container not found"
```
## Acceptance
- [ ] All error messages catalogued with locations
- [ ] Each message scored for actionability (1-5)
- [ ] Inconsistent format errors flagged
- [ ] Top 10 worst error messages identified
- [ ] Suggested improvements for low-scoring messages
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
