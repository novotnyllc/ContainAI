# fn-1.5: Test image build and WASM functionality

## Summary

Completed Part C (Implementation Compliance) tests and fixed all compliance issues. Parts A (DinD) and B (Sandbox) tests could not be executed as Docker daemon is not available in this environment.

## Test Results

### Part A: CI-Compatible (DinD) - SKIPPED
- Requires Docker daemon (not available)
- Tests: Image build, .NET SDK, Node.js, Blazor WASM, Uno WASM, Claude CLI

### Part B: Sandbox-Specific - SKIPPED
- Requires Docker Desktop 4.50+ with sandbox feature
- Tests: csd command, uno-check, container naming, port forwarding

### Part C: Implementation Compliance - PASS (8/8)

| Test | Status | Fix Applied |
|------|--------|-------------|
| C1: Workload separation | PASS | Split wasm-tools and wasm-tools-net9 into separate RUN commands |
| C3: Label support check | PASS | Probe sandbox_help for --label support before using |
| C4: Volume permissions | PASS | Chown ALL volumes including docker-claude-sandbox-data |
| C5: Fallback image | PASS | Use base image for permission fix if dotnet-sandbox not built |
| C6: Blocking errors | PASS | Already implemented |
| C7: Collision details | PASS | Show expected vs actual label and image in errors |
| C8: README clarification | PASS | Clarified sync-plugins does NOT sync credentials |
| C9: Fallback pattern | PASS | Use sandbox-<dirname> pattern, not sandbox-container |

## Files Modified

1. **dotnet-sandbox/Dockerfile** - Split workload installation into separate RUN commands
2. **dotnet-sandbox/aliases.sh** - Multiple fixes for csd wrapper
3. **dotnet-sandbox/README.md** - Clarified sync-plugins credential handling

## Notes

- Parts A and B require Docker runtime which is not available in this environment
- Part C fixes address implementation issues from prerequisite tasks
- The image and sandbox functionality should be tested manually when Docker is available
