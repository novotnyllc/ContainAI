# fn-20-6fe.2 Pin containerd.io version in Dockerfiles

## Description
Update Dockerfiles to pin containerd.io to the exact compatible version identified in Task 1.

**Size:** S
**Files:**
- `src/container/Dockerfile.base` (docker-ce installation section, lines 151-172)
- `src/container/Dockerfile.test` (docker installation section, lines 51-82)

## Approach

1. Update `Dockerfile.base` apt-get install line to pin containerd.io to exact version:
   ```dockerfile
   # Pin containerd.io to version with runc < 1.3.3 (sysbox#973 workaround)
   # runc 1.3.3 CVE fixes detect sysbox procfs virtualization as "fake procfs"
   # Remove pin when Sysbox releases compatibility fix
   containerd.io=<exact-version-from-task-1>
   ```

2. Add `apt-mark hold containerd.io` after installation to prevent auto-upgrade:
   ```dockerfile
   && apt-mark hold containerd.io \
   ```

3. Apply same changes to `Dockerfile.test`

4. Add comment explaining:
   - The pin is a workaround for sysbox#973
   - Security trade-off: temporarily reverts CVE-2025-31133/-52565/-52881 protections
   - Mitigation: Sysbox user namespace isolation still protects the host
   - Removal criteria: when Sysbox releases compatibility fix

Follow pattern at `src/container/Dockerfile.base:151-172` for existing docker installation.

## Key context

- Use exact version string from Task 1 (includes Ubuntu codename suffix)
- apt-mark hold prevents unattended-upgrades from breaking the fix
- The security trade-off is acceptable because Sysbox provides user namespace isolation
- Include link to sysbox#973 for tracking when to remove the workaround

## Acceptance
- [ ] Dockerfile.base pins containerd.io to exact version from Task 1
- [ ] Dockerfile.base includes apt-mark hold containerd.io
- [ ] Dockerfile.base has comment explaining workaround with sysbox#973 reference
- [ ] Dockerfile.base documents security trade-off and mitigation
- [ ] Dockerfile.test pins containerd.io to same version
- [ ] Dockerfile.test includes apt-mark hold
- [ ] Dockerfile.test has matching comment
- [ ] Local image build succeeds: `./src/build.sh --layer base --load`
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
