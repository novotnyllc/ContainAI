# fn-23-glf.1 Refactor build-sysbox.yml to use native runners per architecture

## Description

Refactor `.github/workflows/build-sysbox.yml` to eliminate QEMU cross-compilation by building each architecture on its native runner.

### Changes required

1. **Split `build` job into `build-amd64` and `build-arm64`**
   - `build-amd64`: runs on `ubuntu-22.04`, builds amd64 package
   - `build-arm64`: runs on `ubuntu-24.04-arm`, builds arm64 package

2. **Remove QEMU setup** - no longer needed since each arch builds natively

3. **Update job dependencies**
   - `test-amd64: needs: build-amd64`
   - `test-arm64: needs: build-arm64`
   - `release: needs: [build-amd64, build-arm64, test-amd64, test-arm64]`

4. **Preserve artifact naming** - keep `sysbox-ce-amd64` and `sysbox-ce-arm64` so download jobs work unchanged

### File to modify

- `.github/workflows/build-sysbox.yml`

### Build step notes

For arm64 build job, can simplify since no cross-compilation:
- Remove `TARGET_ARCH` environment variable (native arch is correct)
- Remove QEMU conditional step entirely

## Acceptance

- [ ] `build-amd64` job runs on `ubuntu-22.04`
- [ ] `build-arm64` job runs on `ubuntu-24.04-arm`
- [ ] No QEMU setup steps in workflow
- [ ] `test-amd64` depends only on `build-amd64`
- [ ] `test-arm64` depends only on `build-arm64`
- [ ] `release` depends on all four jobs
- [ ] Artifact names unchanged (`sysbox-ce-amd64`, `sysbox-ce-arm64`)
- [ ] Workflow YAML validates (`gh workflow view build-sysbox.yml`)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
