# ContainAI Source (`src/`)

Source code for ContainAI's native `.NET 10` CLI and container artifacts.

## Overview

ContainAI is implemented as a native `.NET 10` CLI (`cai`) with `System.CommandLine` command routing and NativeAOT publish support.

Key implementation areas:

- `cai/` - native host/runtime orchestration (`Program.cs`, runtime services, build/publish targets)
- `ContainAI.Cli/` - static command/option/argument declarations and routing
- `ContainAI.Cli.Abstractions/` - strongly typed command option records
- `AgentClientProtocol.Proxy/` - ACP proxy library used by `cai acp proxy`
- `container/` - Dockerfile layers (`base`, `sdks`, `agents`, `final`, `test`)
- `manifests/` - TOML manifest source of truth for sync/link generation
- `services/` - systemd units consumed inside ContainAI containers
- `templates/` - user template Dockerfiles and examples

## Quick Commands

### Validate environment

```bash
cai doctor
```

### Build container layers via MSBuild targets

```bash
# all layers
dotnet build src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest

# single layer
dotnet build src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=base -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest

# multi-arch with buildx setup
dotnet build src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIPlatforms=linux/amd64,linux/arm64 -p:ContainAIPush=true -p:ContainAIBuildSetup=true -p:ContainAIImagePrefix=ghcr.io/ORG/containai -p:ContainAIImageTag=latest
```

### Build and test

```bash
# strict build (analyzers + warnings as errors)
dotnet build ContainAI.slnx -c Release -warnaserror

# test (xUnit v3 on Microsoft Testing Platform v2)
dotnet test --solution ContainAI.slnx -c Release --xunit-info

# strict NativeAOT+trim publish
dotnet publish src/cai/cai.csproj -c Release -r linux-x64 -p:PublishAot=true -p:PublishTrimmed=true -warnaserror -p:TrimmerSingleWarn=false
```

## Command Surface

`cai` commands are statically defined in:

- `src/ContainAI.Cli/RootCommandBuilder.cs`

No runtime command discovery is used. Completion is internal via:

- `cai completion suggest --line "..." [--position N]`

No `dotnet-suggest` or external completion dependency is required.

## Config/Manifest Model

ContainAI sync/link behavior is defined by TOML manifests in `src/manifests/*.toml`.

Examples:

- `00-common.toml` - shared entries
- `10-claude.toml` - Claude-specific entries
- `11-codex.toml` - Codex-specific entries

Validation and generation commands:

```bash
# validate manifest model
dotnet run --project src/cai -- manifest check src/manifests

# generate derived artifacts from manifests
cai manifest generate import-map src/manifests
cai manifest generate container-link-spec src/manifests /tmp/link-spec.json
```

## Devcontainer Feature

`src/devcontainer/feature/install.sh` is the required devcontainer feature entrypoint and intentionally minimal:

- validates `cai` exists on `PATH`
- delegates all logic to `cai system devcontainer install --feature-dir ...`

Feature runtime logic is implemented in C# (`src/cai/DevcontainerFeatureRuntime.cs`).

## Packaging

Release tarballs are produced automatically after `dotnet publish` (`AfterTargets=Publish` in `src/cai/build/ContainAI.Build.targets`) and include:

- `cai` binary
- `manifests/`
- `templates/`
- `container/`
- `install.sh`
- `LICENSE`

Tarball target:

```bash
dotnet publish src/cai/cai.csproj -c Release -r linux-x64
dotnet publish src/cai/cai.csproj -c Release -r linux-arm64
```

## Notes for Contributors

- Keep core config parsing in-process with `.NET` libraries (`System.Text.Json`, `CsToml`, YAML parser paths in C# code).
- Do not reintroduce shell parser dependencies (`jq`, `yq`, Python) for CLI config paths.
- Keep warnings-as-errors and analyzer enforcement intact.
- Use `[GeneratedRegex]` for regex patterns in production code.
- Avoid `Process.Start`; process execution should go through `CliWrap` abstractions in host runtime code.

For full contributor workflow and CI expectations, see `docs/for-contributors.md`.
