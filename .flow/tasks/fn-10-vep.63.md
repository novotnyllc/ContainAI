# fn-10-vep.63 Implement cai doctor --fix for auto-remediation

## Description
Implement `cai doctor --fix` for auto-remediation of common issues.

**Size:** M
**Files:** lib/doctor.sh

## Approach

1. Add `--fix` flag to `cai doctor`
2. For each check, define fix action:
   - Missing SSH key → regenerate
   - Missing config dir → create with proper permissions
   - Missing Include directive → add to ssh config
   - Invalid context → recreate context
   - Broken permissions → fix with chmod

3. Output format:
   ```
   [FIXED] SSH key regenerated
   [FIXED] ~/.ssh/containai.d/ created
   [SKIP]  Context already valid
   [FAIL]  Cannot fix: Sysbox not installed (manual action required)
   ```

4. Return non-zero if any FAIL remains

## Key context

- Not all issues can be auto-fixed (e.g., sysbox installation)
- For unfixable issues, provide clear manual instructions
- Should be idempotent (running twice doesn't break anything)
## Acceptance
- [ ] `--fix` flag added to `cai doctor`
- [ ] Auto-regenerates missing SSH key
- [ ] Auto-creates missing directories with correct permissions
- [ ] Auto-adds Include directive if missing
- [ ] Auto-recreates Docker context if invalid
- [ ] Auto-fixes permission issues
- [ ] Clear output showing FIXED/SKIP/FAIL for each item
- [ ] Manual instructions for unfixable issues
- [ ] Returns non-zero if unfixable issues remain
- [ ] Idempotent (safe to run multiple times)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
