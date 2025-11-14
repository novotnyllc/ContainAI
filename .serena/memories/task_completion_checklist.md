# Task Completion Checklist

When you've completed a coding task, follow this checklist before submitting:

## 1. Run Unit Tests

### Bash Tests
```bash
./scripts/test/test-launchers.sh
./scripts/test/test-branch-management.sh
```

**Expected**: All tests pass (✓), zero failures (✗)

### PowerShell Tests
```powershell
pwsh scripts/test/test-launchers.ps1
pwsh scripts/test/test-branch-management.ps1
```

**Expected**: All tests pass (✓), zero failures (✗)

## 2. Code Quality Checks

### PowerShell: PSScriptAnalyzer
```powershell
# Must show ZERO errors and ZERO warnings
Get-ChildItem -Path "scripts" -Filter "*.ps1" -Recurse | 
    ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings PSGallery } |
    Where-Object {$_.Severity -in @('Error','Warning')}
```

**Expected**: No output (clean)

### Bash: Shellcheck (if available)
```bash
shellcheck scripts/**/*.sh
```

**Expected**: No errors

## 3. Feature Parity Check

If you modified scripts, ensure both versions exist and work:

- [ ] Bash version in `scripts/launchers/` or `scripts/utils/`
- [ ] PowerShell version (`.ps1`) with equivalent functionality
- [ ] Both versions tested and working
- [ ] Error messages are equivalent
- [ ] Parameter names match (accounting for language conventions)

## 4. Test Coverage

If you added new functions:

- [ ] Unit tests added for bash version
- [ ] Unit tests added for PowerShell version
- [ ] Both test files pass
- [ ] Edge cases covered

## 5. Integration Tests (Before PR)

```bash
# Minimum: launchers mode (~3-5 min)
./scripts/test/integration-test.sh --mode launchers

# Recommended for Dockerfile changes: full mode (~10-15 min)
./scripts/test/integration-test.sh --mode full
```

**Expected**: All integration tests pass

## 6. Manual Testing

Test with a real container to verify behavior:

```bash
cd ~/test-project
launch-agent copilot --branch test-feature

# Work in the container, verify changes work as expected
# Exit and verify cleanup happened correctly
```

## 7. Documentation Updates

If you changed functionality:

- [ ] Update `README.md` if user-facing changes
- [ ] Update `USAGE.md` if launcher behavior changed
- [ ] Update `CONTRIBUTING.md` if development workflow changed
- [ ] Update `docs/ARCHITECTURE.md` if design changed
- [ ] Update `AGENTS.md` if agent-specific guidance changed

## 8. Security Check

- [ ] No hardcoded secrets (API keys, tokens, passwords)
- [ ] No secrets in test files (use mock values)
- [ ] No secrets baked into Dockerfiles
- [ ] Sensitive mounts are read-only (`:ro` flag)

## 9. Error Handling

- [ ] All external commands have error handling
- [ ] Error messages are clear and actionable
- [ ] Error messages follow format: `❌ Error: What went wrong. How to fix it.`
- [ ] Warnings use: `⚠️ Warning: ...`
- [ ] Success messages use: `✅ ...`

## 10. Git Commit

```bash
git add .
git status  # Verify only intended files are staged
git commit -m "Clear, descriptive commit message"

# If working in container, push to local remote first
git push local

# Then push to origin when ready for PR
git push origin
```

## 11. PR Submission Checklist

Before creating the pull request:

- [ ] All unit tests pass (bash and PowerShell)
- [ ] Integration tests pass
- [ ] PSScriptAnalyzer clean (zero warnings/errors)
- [ ] Both bash and PowerShell versions updated (if applicable)
- [ ] New functions have tests
- [ ] Error messages are clear
- [ ] No hardcoded secrets
- [ ] Documentation updated
- [ ] Manual testing completed successfully

## Quick Command Summary

```bash
# Full verification (run all)
./scripts/test/test-launchers.sh
./scripts/test/test-branch-management.sh
pwsh scripts/test/test-launchers.ps1
pwsh scripts/test/test-branch-management.ps1
./scripts/test/integration-test.sh --mode launchers

# PowerShell quality check
Get-ChildItem -Path "scripts" -Filter "*.ps1" -Recurse | 
    ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings PSGallery } |
    Where-Object {$_.Severity -in @('Error','Warning')}
```

If all checks pass, you're ready to commit and submit a PR! 🎉
