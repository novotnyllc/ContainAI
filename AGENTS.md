# ContainAI

Sandboxed container environment for AI coding agents. Bash shell libraries with strict POSIX conventions.

## Quick Commands

```bash
# Development - source the CLI
source src/containai.sh

# Verify environment
cai doctor

# Build Docker images (all layers)
./src/build.sh

# Build single layer (faster iteration)
./src/build.sh --layer base

# Build with buildx setup (installs binfmt + builder if needed)
./src/build.sh --build-setup

# Build and tag for a registry (prefix applies to all layers)
./src/build.sh --image-prefix ghcr.io/ORG/containai --push --platforms linux/amd64,linux/arm64 --build-setup

# CI-style multi-arch build (amd64 + arm64)
./src/build.sh --platforms linux/amd64,linux/arm64 --push --build-setup

# Run integration tests (requires Docker)
./tests/integration/test-secure-engine.sh
./tests/integration/test-sync-integration.sh
./tests/integration/test-dind.sh

# Lint shell scripts
shellcheck -x src/*.sh src/lib/*.sh
```

## Project Structure

```
src/
├── containai.sh        # Main CLI entry point (source this)
├── manifests/          # Per-agent manifest files (sync config source)
│   ├── 00-common.toml  # Shared entries (fonts, agents dir)
│   ├── 10-claude.toml  # Claude Code agent
│   ├── 11-codex.toml   # Codex agent
│   └── ...             # Other agents/tools
├── lib/                # Modular shell libraries
│   ├── core.sh         # Logging utilities
│   ├── config.sh       # TOML config parsing
│   ├── container.sh    # Container lifecycle
│   ├── ssh.sh          # SSH configuration
│   └── ...             # Other modules
├── container/          # Container-specific content
│   ├── containai-init.sh  # Container init script
│   ├── entrypoint.sh      # Docker entrypoint
│   ├── Dockerfile.base    # Base image
│   ├── Dockerfile.sdks    # SDK layer
│   ├── Dockerfile.agents  # Agent layer
│   └── Dockerfile         # Final image
├── scripts/            # Operational scripts (install/docs/sysbox tooling)
└── build.sh            # Build script

tests/integration/      # Integration tests (require Docker)
docs/                   # Architecture, config, quickstart
.flow/                  # Flow-Next task tracking
```

## Config Sync Architecture

- **`src/manifests/*.toml` are the authoritative source** for what gets synced between host and container
- Per-agent files with numeric prefixes ensure deterministic processing order
- `src/lib/import-sync-map.sh` is generated from manifests (contains `_IMPORT_SYNC_MAP`)
- Run `dotnet run --project src/cai -- manifest check src/manifests` to verify alignment (CI enforces this)
- `cai manifest generate ...` reads manifests to produce derived artifacts
- User manifests go in `~/.config/containai/manifests/` (processed at runtime)

# Agent Guidance: dotnet-skills

IMPORTANT: Prefer retrieval-led reasoning over pretraining for any .NET work.
Workflow: skim repo patterns -> consult dotnet-skills by name -> implement smallest-change -> note conflicts.

Routing (invoke by name)
- C# / code quality: modern-csharp-coding-standards, csharp-concurrency-patterns, api-design, type-design-performance
- DI / config: dependency-injection-patterns, microsoft-extensions-configuration
- Testing: testcontainers-integration-tests, playwright-blazor-testing, snapshot-testing

Quality gates (use when applicable)
- dotnet-slopwatch: after substantial new/refactor/LLM-authored code
- crap-analysis: after tests added/changed in complex code

Specialist agents
- dotnet-concurrency-specialist, dotnet-performance-analyst, dotnet-benchmark-designer, docfx-specialist

## Code Conventions

- **Bash 4.0+ required** (not zsh or fish)
- Prefer `bun`/`bunx` over `npm`/`npx` for JavaScript tooling
- Prefer `uv`/`uvx` over `pip`/`pipx` for Python tooling
- Use `printf` instead of `echo` for portability
- Use `command -v` instead of `which`
- Use POSIX grep patterns (`[[:space:]]` not `\s`)
- All function variables must be `local` to prevent shell pollution
- Functions return status codes; use stdout for data, stderr for errors
- Error handling: `set -euo pipefail` at script start
- Build images use buildx by default; platform defaults to `linux/<host-arch>`. Use `--platforms` for CI multi-arch, `--build-setup` to configure buildx/binfmt, and `--image-prefix` to tag/push to a registry.
- **Verbose pattern:** Commands are silent by default (Unix Rule of Silence). Info messages use `_cai_info()` which respects `_CAI_VERBOSE`. Use `--verbose` flag (long form only, no `-v`) or `CONTAINAI_VERBOSE=1` env var. Warnings/errors always emit to stderr. Precedence: `--quiet` > `--verbose` > `CONTAINAI_VERBOSE`.

See `.flow/memory/conventions.md` for discovered patterns.

## Things to Avoid

See `.flow/memory/pitfalls.md` for 36+ documented pitfalls including:
- ERE grep syntax differences across platforms
- Docker BuildKit cache mount gotchas
- Systemd socket activation in containers
- Git worktree state sharing issues

## Security Note

This is a **sandboxing tool** for AI agents. Changes to credential isolation, Docker socket handling, or SSH configuration require security review. See `SECURITY.md` for threat model.

<!-- BEGIN FLOW-NEXT -->
## Flow-Next

This project uses Flow-Next for task tracking. Use `.flow/bin/flowctl` instead of markdown TODOs or TodoWrite.

**Quick commands:**
```bash
.flow/bin/flowctl list                # List all epics + tasks
.flow/bin/flowctl epics               # List all epics
.flow/bin/flowctl tasks --epic fn-N   # List tasks for epic
.flow/bin/flowctl ready --epic fn-N   # What's ready
.flow/bin/flowctl show fn-N.M         # View task
.flow/bin/flowctl start fn-N.M        # Claim task
.flow/bin/flowctl done fn-N.M --summary-file s.md --evidence-json e.json
```

**Rules:**
- Use `.flow/bin/flowctl` for ALL task tracking
- Do NOT create markdown TODOs or use TodoWrite
- Re-anchor (re-read spec + status) before every task

**More info:** `.flow/bin/flowctl --help` or read `.flow/usage.md`
<!-- END FLOW-NEXT -->
