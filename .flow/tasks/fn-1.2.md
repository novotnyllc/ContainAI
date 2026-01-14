# fn-1.2 Create Dockerfile with .NET 10 SDK and WASM workloads

## Description
Create Dockerfile for .NET development sandbox with:

**Base Image:**
- `docker/sandbox-templates:claude-code`
- Fail fast if not Ubuntu Noble

**.NET SDK Installation (via dotnet-install.sh, NOT apt):**
- Use dotnet-install.sh script from Microsoft
- Default: latest LTS (no version required)
- Build ARGs for: preview, STS, major.minor
- Install wasm-tools workload
- Run uno-check with auto-fix flags

**PowerShell:**
- Install via Microsoft's recommended method

**Node.js:**
- Install nvm
- Install Node.js LTS via nvm
- Pre-install global packages: typescript, eslint, prettier

**NuGet Cache Pre-warming:**
- Pre-warm cache with basic packages: wasm, aspnet, console templates

**Ports:**
- Expose 5000-5010 for WASM app serving

**Image Naming:**
- Image: `dotnet-sandbox`
- Tags: `:latest` AND `:YYYY-MM-DD`

**Single RUN approach for smallest image size.**
## Acceptance
- [ ] Build fails with clear error if base image is not Ubuntu Noble
- [ ] `dotnet --version` outputs latest LTS
- [ ] `dotnet workload list` shows `wasm-tools`
- [ ] `uno-check` passes during build
- [ ] `pwsh --version` succeeds
- [ ] `node --version` outputs LTS version
- [ ] `nvm --version` works
- [ ] `tsc --version`, `eslint --version`, `prettier --version` work
- [ ] Container runs as `uid=1000(agent)`
- [ ] Blazor WASM project creates and builds
- [ ] Uno Platform WASM project creates and builds
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
