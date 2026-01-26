# fn-20-6fe.3 Document limitation and verify integration tests

## Description
Document the runc 1.3.3 incompatibility as a known limitation with security trade-off notes, and verify DinD integration tests pass with the fixed image.

**Size:** S
**Files:**
- `.flow/memory/pitfalls.md` (add new pitfall entry)
- `tests/integration/test-dind.sh` (verify passes with local image)

## Approach

1. Add pitfall entry to `.flow/memory/pitfalls.md` in existing date-stamped format:
   ```markdown
   ## YYYY-MM-DD manual [pitfall]

   **runc 1.3.3+ incompatible with sysbox DinD**: Docker containers fail inside sysbox with
   "unsafe procfs detected: openat2 /proc/./sys/net/ipv4/ip_unprivileged_port_start: invalid cross-device link".
   Pin containerd.io to version with runc < 1.3.3. Security trade-off: temporarily reverts
   CVE-2025-31133/-52565/-52881 fixes, mitigated by sysbox user namespace isolation.
   Track sysbox#973 for removal. (2026-01-26)
   ```

2. Rebuild image with pinned version:
   ```bash
   ./src/build.sh --layer base --load
   ```

3. Run integration test with local image:
   ```bash
   CONTAINAI_TEST_IMAGE=containai/base:latest ./tests/integration/test-dind.sh
   ```

4. Verify DinD operations work end-to-end inside the test container.

Follow pattern in `.flow/memory/pitfalls.md` for existing pitfall entries (date-stamped, concise).

## Key context

- Pitfalls use date-stamped format: `## YYYY-MM-DD manual [pitfall]`
- The test defaults to `ghcr.io/novotnyllc/containai/base:latest` - must override with `CONTAINAI_TEST_IMAGE`
- Test requires sysbox-runc runtime on the host
- Document removal criteria: when Sysbox releases compatibility fix for sysbox#973
- Security trade-off must be explicitly documented (CVE rollback, mitigation via sysbox isolation)

## Acceptance
- [ ] Pitfall entry added to .flow/memory/pitfalls.md in date-stamped format
- [ ] Entry includes error message and root cause (runc 1.3.3 CVE fixes)
- [ ] Entry includes workaround (pin containerd.io)
- [ ] Entry documents security trade-off (CVE rollback) and mitigation (sysbox isolation)
- [ ] Entry includes sysbox#973 reference and removal criteria
- [ ] Image rebuilt with pinned version: `./src/build.sh --layer base --load`
- [ ] tests/integration/test-dind.sh passes with `CONTAINAI_TEST_IMAGE=containai/base:latest`
- [ ] DinD verified working: can run `docker run` inside test container
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
