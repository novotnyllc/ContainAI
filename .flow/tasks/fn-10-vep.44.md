# fn-10-vep.44 Create sdks Dockerfile layer (.NET, Rust, Go, Node)

## Description
Create the sdks Dockerfile layer with development SDKs and tools.

**Size:** M
**Files:** src/Dockerfile.sdks (new)

## Approach

1. Base from `containai/base:latest`
2. Copy .NET SDK from official image (same pattern as current Dockerfile)
3. Install Rust via rustup
4. Install Go from official tarball
5. Install nvm + latest Node LTS
6. Install Python tools: uv, pipx
7. Set up PATH for all SDKs

## Key context

- Current Dockerfile copies .NET from `mcr.microsoft.com/dotnet/sdk` - keep this pattern
- Rust: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y`
- Go: download from `go.dev/dl/`
- nvm: `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash`
## Acceptance
- [ ] `src/Dockerfile.sdks` created
- [ ] Builds from `containai/base:latest`
- [ ] .NET SDK (latest LTS) installed and `dotnet --version` works
- [ ] Rust installed and `rustc --version` works
- [ ] Go installed and `go version` works
- [ ] Node (via nvm) installed and `node --version` works
- [ ] uv installed and `uv --version` works
- [ ] pipx installed
- [ ] Image builds successfully
- [ ] Total layer size reasonable (< 3GB)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
