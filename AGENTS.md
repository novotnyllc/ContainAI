# ContainAI

Sandboxed container environment for AI coding agents. Native .NET 10 CLI with container/runtime artifacts.

## Quick Commands

```bash
# Verify environment
cai doctor

# Build Docker images (all layers)
dotnet msbuild src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest

# Build single layer (faster iteration)
dotnet msbuild src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=base -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest

# Build with buildx setup (installs binfmt + builder if needed)
dotnet msbuild src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIPlatforms=linux/amd64,linux/arm64 -p:ContainAIPush=true -p:ContainAIBuildSetup=true -p:ContainAIImagePrefix=ghcr.io/ORG/containai -p:ContainAIImageTag=nightly

# Build and tag for a registry (prefix applies to all layers)
dotnet msbuild src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIPlatforms=linux/amd64,linux/arm64 -p:ContainAIPush=true -p:ContainAIBuildSetup=true -p:ContainAIImagePrefix=ghcr.io/ORG/containai -p:ContainAIImageTag=latest

# CI-style multi-arch build (amd64 + arm64)
dotnet msbuild src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIPlatforms=linux/amd64,linux/arm64 -p:ContainAIPush=true -p:ContainAIBuildSetup=true

# Run tests
dotnet test --solution ContainAI.slnx -c Release --xunit-info
dotnet test --project tests/ContainAI.Cli.Tests/ContainAI.Cli.Tests.csproj -c Release -- --filter-trait "Category=SyncIntegration" --xunit-info

# Lint shell scripts
shellcheck -x install.sh scripts/*.sh scripts/ralph/*.sh
```

## Project Structure

```
src/
├── cai/                # Native CLI host entrypoint and runtime
│   ├── Program.cs
│   ├── NativeLifecycleCommandRuntime.cs
│   └── ContainerRuntimeCommandService.cs
├── ContainAI.Cli/      # System.CommandLine command surface and routing
├── manifests/          # Per-agent manifest files (sync config source)
│   ├── 00-common.toml  # Shared entries (fonts, agents dir)
│   ├── 10-claude.toml  # Claude Code agent
│   ├── 11-codex.toml   # Codex agent
│   └── ...             # Other agents/tools
├── AgentClientProtocol.Proxy/ # ACP proxy library integrated into cai
├── container/          # Container-specific content
│   ├── Dockerfile.template-system # Template wrapper
│   ├── Dockerfile.base    # Base image
│   ├── Dockerfile.sdks    # SDK layer
│   ├── Dockerfile.agents  # Agent layer
│   └── Dockerfile         # Final image
├── services/           # systemd units using native cai system commands
└── templates/          # Template Dockerfiles

tests/                  # xUnit v3 test suites
docs/                   # Architecture, config, quickstart
.flow/                  # Flow-Next task tracking
```

## Config Sync Architecture

- **`src/manifests/*.toml` are the authoritative source** for what gets synced between host and container
- Per-agent files with numeric prefixes ensure deterministic processing order
- `cai manifest generate import-map` generates the import mapping from manifests
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
