# fn-44-build-system-net-project-restructuring.5 Update CI to build and publish multi-arch .NET binaries

## Description
Create release packaging system: build multi-arch .NET binaries, package into flat per-architecture tarballs (runtime only), publish tarball + standalone install.sh to GitHub Releases. PR builds upload to PR-specific artifact location for testing.

**Size:** M
**Files:**
- `.github/workflows/docker.yml` (update build and test jobs)
- `.github/workflows/release.yml` (new workflow for releases)
- `install.sh` (rewrite as standalone wget-able script)
- `scripts/package-release.sh` (new - creates tarball)

## Approach

1. **Two install paths:**

   **Path A - curl/wget (most users):**
   ```bash
   curl -fsSL https://github.com/.../releases/latest/download/install.sh | bash
   ```
   - install.sh detects arch, downloads tarball, extracts, configures

   **Path B - manual tarball download:**
   ```bash
   # User downloads tarball manually, then:
   tar xzf containai-0.2.0-linux-x64.tar.gz
   cd containai-0.2.0-linux-x64
   ./install.sh --local   # Install from extracted directory
   ```

2. **install.sh dual-mode behavior:**
   - If run standalone (no local files): download tarball from Releases
   - If run from extracted tarball (`--local` or detects local files): install from current directory
   - Same script works both ways

3. **Flat tarball structure - runtime only** (e.g., `containai-0.2.0-linux-x64.tar.gz`):
   ```
   containai-0.2.0-linux-x64/
   ├── containai.sh            # Main CLI
   ├── lib/                    # Shell libraries
   ├── templates/              # User templates
   ├── acp-proxy               # AOT binary
   ├── install.sh              # Same script, works locally too
   ├── VERSION
   └── LICENSE
   ```

   **NOT included** (contributors clone repo):
   - Dockerfiles
   - Tests
   - Build scripts
   - Documentation

4. **Multi-arch matrix build**:
   - linux-x64 on ubuntu-latest
   - linux-arm64 on ubuntu-24.04-arm
   - Build AOT binaries with `dotnet publish --self-contained`

5. **PR artifact flow**:
   - PR builds upload tarball to GitHub Actions artifacts
   - Test job downloads, extracts, runs `./install.sh --local`

6. **Release flow**:
   - Tag push triggers release workflow
   - Upload install.sh + tarballs as release assets
   - install.sh included in both release assets AND inside each tarball

## Key context

- install.sh must work both as standalone download AND from inside tarball
- Detect mode: check if `containai.sh` exists in same directory
- `--local` flag forces local install even if files look like they might be elsewhere
- Tarballs are for end users, not contributors
## Approach

1. **Standalone install.sh** - Published as release asset, wget-able:
   ```bash
   # User runs:
   curl -fsSL https://github.com/.../releases/latest/download/install.sh | bash
   ```
   - Detects architecture
   - Downloads appropriate tarball from same release
   - Extracts to ~/.local/share/containai
   - Creates cai wrapper in ~/.local/bin
   - Installs sysbox if needed

2. **Flat tarball structure - runtime only** (e.g., `containai-0.2.0-linux-x64.tar.gz`):
   ```
   containai-0.2.0-linux-x64/
   ├── containai.sh            # Main CLI
   ├── lib/                    # Shell libraries
   ├── templates/              # User templates
   ├── acp-proxy               # AOT binary
   ├── VERSION
   └── LICENSE
   ```

   **NOT included** (contributors clone repo):
   - Dockerfiles
   - Tests
   - Build scripts
   - Documentation

3. **Multi-arch matrix build**:
   - linux-x64 on ubuntu-latest
   - linux-arm64 on ubuntu-24.04-arm
   - Build AOT binaries with `dotnet publish --self-contained`

4. **PR artifact flow**:
   - PR builds upload tarball + install.sh to GitHub Actions artifacts
   - Test job downloads and runs install.sh
   - install.sh can accept artifact URL override for PR testing

5. **Release flow**:
   - Tag push triggers release workflow
   - Upload install.sh + tarballs as release assets
   - install.sh published at predictable URL: `.../releases/latest/download/install.sh`

## Key context

- install.sh must be standalone - can't be inside tarball (chicken-egg)
- Tarballs are for end users, not contributors
- Contributors clone repo to access Dockerfiles, tests, build scripts
- GitHub releases have `latest/download/` URL pattern for latest release
## Approach

1. **Standalone install.sh** - Published as release asset, wget-able:
   ```bash
   # User runs:
   curl -fsSL https://github.com/.../releases/latest/download/install.sh | bash
   ```
   - Detects architecture
   - Downloads appropriate tarball from same release
   - Extracts to ~/.local/share/containai
   - Creates cai wrapper in ~/.local/bin
   - Installs sysbox if needed

2. **Flat tarball structure** (e.g., `containai-0.2.0-linux-x64.tar.gz`):
   ```
   containai-0.2.0-linux-x64/
   ├── containai.sh            # Main CLI
   ├── lib/                    # Shell libraries
   ├── container/              # Dockerfiles
   ├── acp-proxy               # AOT binary (flat, not in bin/)
   ├── VERSION
   └── README.md
   ```
   No nested `bin/` or `src/` - flat and simple.

3. **Multi-arch matrix build**:
   - linux-x64 on ubuntu-latest
   - linux-arm64 on ubuntu-24.04-arm
   - Build AOT binaries with `dotnet publish --self-contained`

4. **PR artifact flow**:
   - PR builds upload tarball + install.sh to GitHub Actions artifacts
   - Test job downloads and runs install.sh
   - install.sh can accept artifact URL override for PR testing

5. **Release flow**:
   - Tag push triggers release workflow
   - Upload install.sh + tarballs as release assets
   - install.sh published at predictable URL: `.../releases/latest/download/install.sh`

## Key context

- install.sh must be standalone - can't be inside tarball (chicken-egg)
- Flat tarball structure is simpler to extract and navigate
- GitHub releases have `latest/download/` URL pattern for latest release
- PR artifacts accessible via `actions/download-artifact`
## Approach

1. **Create release tarball structure**:
   ```
   containai-${VERSION}-${ARCH}/
   ├── bin/acp-proxy          # Pre-built AOT binary
   ├── src/                   # Shell libraries
   ├── install.sh             # Standalone installer
   ├── VERSION                # Version from NBGV
   └── README.md
   ```

2. **Multi-arch matrix build**:
   - linux-x64 on ubuntu-latest
   - linux-arm64 on ubuntu-24.04-arm
   - Build AOT binaries with `dotnet publish --self-contained`

3. **PR artifact flow**:
   - PR builds upload tarball to GitHub Actions artifacts
   - Test job downloads artifact and runs install.sh from it
   - This validates the full install flow before merge

4. **Release flow**:
   - Tag push triggers release workflow
   - Upload tarballs as release assets
   - Use NBGV version for release tag and tarball names

5. **Update install.sh**:
   - Detect architecture
   - Download tarball from GitHub Releases (or PR artifact URL if provided)
   - Extract to ~/.local/share/containai
   - Create cai wrapper
   - No repo clone needed

## Key context

- Current install.sh clones repo to ~/.local/share/containai
- Tarballs eliminate git dependency for end users
- PR artifacts accessible via: `actions/download-artifact`
- Release assets accessible via: `https://github.com/{owner}/{repo}/releases/download/{tag}/{filename}`
## Approach

1. **Multi-arch matrix build**: Use matrix strategy for RIDs (linux-x64, linux-arm64).

2. **Self-contained AOT publish**: Use `dotnet publish --self-contained` to create standalone binaries that don't need .NET runtime.

3. **Publish to GitHub Releases**:
   - On tag push or release creation, upload binaries as release assets
   - Use NBGV version for release tag
   - Binary naming: `acp-proxy-<version>-<rid>` (e.g., `acp-proxy-0.2.0-linux-x64`)

4. **Update install.sh to download binaries**:
   - Detect architecture
   - Download appropriate binary from GitHub Releases
   - No need to clone repo or have .NET installed
   - Example: `curl -L https://github.com/org/repo/releases/download/v${VERSION}/acp-proxy-${VERSION}-linux-x64 -o /usr/local/bin/acp-proxy`

5. **Docker build uses downloaded binary**: Don't build .NET in Dockerfile, copy pre-built binary.

## Key context

- Binaries must NOT be checked into repo (download at install time)
- install.sh is the primary way users get ContainAI
- AOT binaries are self-contained, no .NET runtime needed
- NBGV version used for release tags and binary names
## Approach

1. **Multi-arch matrix build**: Use matrix strategy for RIDs (linux-x64, linux-arm64, osx-x64, osx-arm64, win-x64).

2. **Self-contained publish**: Use `dotnet publish --self-contained` to create standalone binaries.

3. **Upload as release artifacts**: Attach binaries to GitHub releases.

4. **Update Docker build**: Copy pre-built binary instead of building during Docker image creation.

Follow pattern from `Tyrrrz/YoutubeDownloader` and `JustArchiNET/ArchiSteamFarm` workflows.

## Key context

- Current build at `.github/workflows/docker.yml:285-295` uses `dotnet publish -c Release -r linux-x64`
- AOT publishing requires building on target platform (can't cross-compile AOT)
- For AOT: use ubuntu-latest for linux, macos-latest for osx, windows-latest for win
- ArtifactsOutput puts publish output in `artifacts/publish/acp-proxy/<config>_<rid>/`
## Acceptance
- [ ] CI builds acp-proxy for linux-x64, linux-arm64
- [ ] Binaries are self-contained AOT (no .NET runtime needed)
- [ ] Release tarballs contain runtime only (CLI, lib, templates, binary, install.sh)
- [ ] Release tarballs do NOT contain Dockerfiles, tests, or build scripts
- [ ] install.sh works when curl'd standalone (downloads tarball)
- [ ] install.sh works from inside extracted tarball (--local or auto-detect)
- [ ] install.sh included in each tarball
- [ ] install.sh published as standalone release asset too
- [ ] PR builds upload tarball to Actions artifacts
- [ ] PR test job extracts tarball and runs ./install.sh --local
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
