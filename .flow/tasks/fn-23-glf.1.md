# fn-23-glf.1 Refactor build-sysbox.yml to use native runners per architecture

## Description

Refactor `.github/workflows/build-sysbox.yml` to eliminate cross-compilation issues by building each architecture on its native runner.

### Changes required

1. **Split `build` job into `build-amd64` and `build-arm64`**
   - `build-amd64`: runs on `ubuntu-22.04`, builds amd64 package
   - `build-arm64`: runs on `ubuntu-24.04-arm`, builds arm64 package

2. **Remove QEMU setup** - no longer needed since each arch builds natively

3. **Keep `TARGET_ARCH` explicit** - set from `dpkg --print-architecture` to ensure sysbox-pkgr uses correct arch metadata, even on native runners

4. **Add explicit dependency install step for arm64** - ensure sysbox-pkgr build requirements are installed (may differ between ubuntu-22.04 and ubuntu-24.04-arm runner images)

5. **Update job dependencies**
   - `test-amd64: needs: build-amd64`
   - `test-arm64: needs: build-arm64`
   - `release: needs: [build-amd64, build-arm64, test-amd64, test-arm64]`

6. **Preserve artifact naming** - keep `sysbox-ce-amd64` and `sysbox-ce-arm64` so download jobs work unchanged

### File to modify

- `.github/workflows/build-sysbox.yml`

### Build step notes

For both build jobs:
- Set `TARGET_ARCH=$(dpkg --print-architecture)` to be explicit
- Remove QEMU setup step from arm64 job
- Add build dependency verification step

## Acceptance

- [ ] `build-amd64` job runs on `ubuntu-22.04`
- [ ] `build-arm64` job runs on `ubuntu-24.04-arm`
- [ ] Both jobs set `TARGET_ARCH` explicitly (from `dpkg --print-architecture`)
- [ ] No QEMU setup steps in workflow
- [ ] `build-arm64` includes explicit dependency install for sysbox-pkgr requirements
- [ ] `test-amd64` depends only on `build-amd64`
- [ ] `test-arm64` depends only on `build-arm64`
- [ ] `release` depends on all four jobs
- [ ] Artifact names unchanged (`sysbox-ce-amd64`, `sysbox-ce-arm64`)
- [ ] Workflow YAML validates (`gh workflow view build-sysbox.yml`)

## Done summary
Refactored build-sysbox.yml to use native runners: build-amd64 on ubuntu-22.04, build-arm64 on ubuntu-24.04-arm. Removed QEMU cross-compilation, added architecture verification using dpkg --print-architecture, and updated job dependencies so tests depend only on their respective build jobs.
## Evidence
- Commits: d78d7e72e20eb08771743dc829142c47a7d1716a
- Tests: gh workflow view build-sysbox.yml
- PRs:
