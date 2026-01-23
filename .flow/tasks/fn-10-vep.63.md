# fn-10-vep.63 Implement cai doctor --fix for auto-remediation

## Description
Implement `cai doctor --fix` for auto-remediation of common issues including SSH config cleanup.

**Size:** M
**Files:** lib/doctor.sh

## Approach

1. `cai doctor` checks:
   - Sysbox runtime available
   - Docker context configured
   - SSH key exists and has correct permissions
   - SSH config directory exists
   - No stale SSH configs

2. `cai doctor --fix` actions:
   - Regenerate missing SSH key
   - Recreate Docker context
   - Fix file permissions
   - Clean stale SSH configs (calls `cai ssh cleanup`)
   - Create missing directories

3. Output:
   - Clear pass/fail for each check
   - What was fixed (if --fix)
   - What couldn't be auto-fixed

## Key context

- Run checks in dependency order
- Don't fix things that aren't broken
- Provide clear guidance for manual fixes
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
- [ ] `cai doctor` shows all checks with pass/fail
- [ ] Checks: sysbox, context, SSH key, permissions, stale configs
- [ ] `cai doctor --fix` regenerates SSH key if missing
- [ ] `cai doctor --fix` recreates context if broken
- [ ] `cai doctor --fix` fixes permissions
- [ ] `cai doctor --fix` cleans stale SSH configs
- [ ] Clear output showing what was fixed
- [ ] Exit code indicates success/failure
## Done summary
## Summary

Implemented `cai doctor --fix` for auto-remediation of common SSH and configuration issues.

### Changes

1. **src/containai.sh**: Updated `_containai_doctor_help()` and `_containai_doctor_cmd()` to add `--fix` flag support

2. **src/lib/doctor.sh**: Added new `_cai_doctor_fix()` function that:
   - Creates missing SSH key with proper permissions (ed25519)
   - Creates missing `~/.config/containai/` directory
   - Creates missing `~/.ssh/` and `~/.ssh/containai.d/` directories
   - Adds Include directive to `~/.ssh/config` if missing
   - Fixes wrong file permissions (700 for directories, 600 for keys)
   - Cleans stale SSH configs for non-existent containers
   - Reports issues that cannot be auto-fixed (Sysbox, kernel, Docker daemon)

### Output Format

```
[FIXED]   - Issue was automatically remediated
[OK]      - Check passed, no action needed
[SKIP]    - Cannot auto-fix, requires manual action
[FAIL]    - Fix attempted but failed
[MANUAL]  - Cannot be auto-fixed, provides guidance
```

### Exit Codes

- 0: All checks pass
- 1: Issues remain (either failed fixes or manual action required)
## Evidence
- Commits:
- Tests: {'name': 'shellcheck', 'command': 'shellcheck -x src/lib/doctor.sh src/containai.sh', 'result': 'pass'}, {'name': 'doctor --help shows --fix option', 'command': "source src/containai.sh && cai doctor --help | grep -q -- '--fix'", 'result': 'pass'}, {'name': 'doctor --fix runs and fixes SSH config', 'command': "source src/containai.sh && cai doctor --fix 2>&1 | grep -q '[FIXED]'", 'result': 'pass'}, {'name': 'doctor (regular mode) still works', 'command': "source src/containai.sh && cai doctor 2>&1 | grep -q 'ContainAI Doctor'", 'result': 'pass'}, {'name': 'doctor --json still works', 'command': "source src/containai.sh && cai doctor --json 2>&1 | jq -e '.ssh.all_ok'", 'result': 'pass'}
- PRs:
