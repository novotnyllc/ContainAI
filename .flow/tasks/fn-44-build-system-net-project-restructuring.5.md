# fn-44-build-system-net-project-restructuring.5 Update CI to build and publish multi-arch .NET binaries

## Description
Create release packaging system: build multi-arch .NET binaries, package into flat per-architecture tarballs (runtime only but including required helper scripts and manifest), publish tarball + standalone install.sh to GitHub Releases. PR builds upload to PR-specific artifact location for testing.

**Size:** M
**Files:**
- `.github/workflows/docker.yml` (update build and test jobs)
- `.github/workflows/release.yml` (new workflow for releases)
- `install.sh` (rewrite as dual-mode standalone/local script)
- `scripts/package-release.sh` (new - creates tarball)

## Approach

1. **Dual-mode install.sh**:

   **Path A - curl/wget (most users):**
   ```bash
   curl -fsSL https://github.com/.../releases/latest/download/install.sh | bash
   ```
   - Detects architecture, downloads tarball, extracts, configures

   **Path B - from extracted tarball:**
   ```bash
   tar xzf containai-0.2.0-linux-x64.tar.gz
   cd containai-0.2.0-linux-x64
   ./install.sh --local   # or auto-detects local files
   ```

2. **Flat tarball structure - runtime only** (includes all runtime dependencies):
   ```
   containai-0.2.0-linux-x64/
   ├── containai.sh            # Main CLI
   ├── lib/                    # Shell libraries
   ├── scripts/
   │   └── parse-manifest.sh   # ONLY this runtime script (not gen-*, test-*, etc.)
   ├── sync-manifest.toml      # Required by sync.sh
   ├── templates/              # User templates
   ├── acp-proxy               # AOT binary
   ├── install.sh              # Same script, works locally too
   ├── VERSION
   └── LICENSE
   ```

   **NOT included** (contributors clone repo):
   - Dockerfiles (src/container/)
   - Tests (tests/)
   - Build scripts (src/build.sh, src/scripts/gen-*.sh, etc.)
   - Documentation

3. **scripts/ directory selection**: Only copy `parse-manifest.sh` to the tarball's `scripts/` directory. Do NOT copy the entire `src/scripts/` folder (which contains build/generator scripts that aren't runtime dependencies).

4. **Multi-arch matrix build**:
   - linux-x64 on ubuntu-latest
   - linux-arm64 on ubuntu-24.04-arm
   - Build AOT binaries with `dotnet publish --self-contained`

5. **PR artifact flow**:
   - PR builds upload tarball to GitHub Actions artifacts
   - Test job downloads, extracts, runs `./install.sh --local`
   - Task 4 (sysbox E2E) uses these same artifacts

6. **Release flow** (integrates with NBGV branching):
   - Release branches: `rel/v0.2` format (create from main)
   - Main branch has `-dev` prerelease suffix (e.g., `0.2.0-dev.42`)
   - Release branches have stable version (e.g., `0.2.0`, `0.2.1`)
   - Push to `rel/v*` triggers release workflow
   - Upload install.sh + tarballs as release assets
   - install.sh included in both release assets AND inside each tarball
   - Tarball names use NBGV version (e.g., `containai-0.2.0-linux-x64.tar.gz`)

## Key context

- install.sh must work both as standalone download AND from inside tarball
- Detect mode: check if `containai.sh` exists in same directory
- `--local` flag forces local install
- `scripts/parse-manifest.sh` is a RUNTIME dependency (required by sync.sh)
- `sync-manifest.toml` is a RUNTIME dependency (required by sync.sh at line 22, 46-50)
- Do NOT copy entire `src/scripts/` - only `parse-manifest.sh` is runtime-needed
- Tarballs are for end users, contributors clone repo

## Acceptance
- [ ] CI builds acp-proxy for linux-x64, linux-arm64
- [ ] Binaries are self-contained AOT (no .NET runtime needed)
- [ ] Release tarballs contain: containai.sh, lib/, scripts/parse-manifest.sh (only), sync-manifest.toml, templates/, acp-proxy, install.sh, VERSION, LICENSE
- [ ] Release tarballs do NOT contain: Dockerfiles, tests, build scripts, gen-*.sh, documentation
- [ ] install.sh works when curl'd standalone (downloads tarball)
- [ ] install.sh works from inside extracted tarball (--local or auto-detect)
- [ ] install.sh handles --yes flag for non-interactive mode
- [ ] install.sh included in each tarball
- [ ] install.sh published as standalone release asset too
- [ ] PR builds upload tarball to Actions artifacts
- [ ] PR test job extracts tarball and runs ./install.sh --local
- [ ] Task 4 E2E tests use these same PR artifacts
- [ ] Release workflow triggers on push to `rel/v*` branches
- [ ] Release workflow publishes all assets to GitHub Releases
- [ ] `curl ... | bash` install works for end users
- [ ] Manual tarball download + extract + ./install.sh works
- [ ] Version from NBGV used for tarball names
- [ ] No binaries or tarballs in git history

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
