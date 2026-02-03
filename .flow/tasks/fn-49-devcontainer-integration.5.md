# fn-49-devcontainer-integration.5 Test sysbox verification matrix

## Description

Comprehensive testing of the sysbox verification logic to ensure it correctly distinguishes sysbox from other container runtimes.

### Test Matrix

| Runtime | UID Map | unshare | Sysboxfs | Cap Probe | Total | Expected |
|---------|---------|---------|----------|-----------|-------|----------|
| sysbox | ✓ | ✓ | ✓ | ✓ | 4 | PASS |
| docker (default) | ✗ | ✗ | ✗ | ✗ | 0 | FAIL |
| docker --privileged | ✗ | ✓ | ✗ | ✓ | 2 | FAIL |
| docker --cap-add=ALL | ✗ | ✗ | ✗ | ✗ | 0 | FAIL |
| podman (rootless) | varies | varies | ✗ | varies | 0-2 | FAIL |

### Integration Test: `tests/integration/test-devcontainer-sysbox.sh`

```bash
# Test 1: Sysbox passes verification
# Test 2: Regular docker fails
# Test 3: Privileged fails (only 2 checks pass)
# Test 4: Full devcontainer flow
```

### Unit Tests

- Test UID map parsing
- Test sysboxfs mount detection
- Test capability probe

### CI Integration

Add to `.github/workflows/ci.yml`:
```yaml
test-devcontainer:
  runs-on: ubuntu-latest
  needs: [build-sysbox]
  steps:
    - name: Test sysbox verification
      run: ./tests/integration/test-devcontainer-sysbox.sh
```

## Acceptance

- [ ] Sysbox containers pass verification (4/4 checks)
- [ ] Regular docker containers fail (0/4 checks)
- [ ] Privileged containers fail (2/4 checks, need 3)
- [ ] Clear error message when verification fails
- [ ] Tests run in CI pipeline

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
