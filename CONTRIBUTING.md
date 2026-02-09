# Contributing to ContainAI

Thank you for your interest in contributing to ContainAI! This guide covers development setup, coding conventions, testing, and the pull request process.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Environment](#development-environment)
- [Coding Conventions](#coding-conventions)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Good First Issues](#good-first-issues)
- [Architecture Overview](#architecture-overview)

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork**:
   ```bash
   git clone https://github.com/YOUR_USERNAME/containai.git
   cd containai
   ```
3. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Environment

### Requirements

- **.NET SDK 10.0+** - Required for native CLI build and test
- **Docker CLI** - Any recent version (`docker --version`)
- **Bash** 4.0+ (macOS: `brew install bash`)
- **Git** for version control

### Setup

```bash
# Restore local tools and bootstrap cai
dotnet tool restore
./install.sh --local --yes --no-setup

# One-time runtime setup
cai setup

# Build and verify your environment
dotnet build ContainAI.slnx -c Release
cai doctor
```

`install.sh` delegates install operations to `cai install`, and `cai setup` provisions platform runtime dependencies (Linux/WSL2 installs the ContainAI-managed dockerd bundle + Sysbox on supported distros; macOS configures Lima).

### Building Images (Buildx Preferred)

ContainAI image builds are driven by MSBuild targets in `src/cai/cai.csproj`.
Use `ContainAIBuildSetup=true` to configure buildx builder/binfmt when needed.

```bash
# Build all layers for host architecture
dotnet build src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest

# Build single layer
dotnet build src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=base -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest

# CI-style multi-arch build and push
dotnet build src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIPlatforms=linux/amd64,linux/arm64 -p:ContainAIPush=true -p:ContainAIBuildSetup=true -p:ContainAIImagePrefix=ghcr.io/ORG/containai -p:ContainAIImageTag=nightly

# Publish native AOT CLI (single RID)
dotnet publish src/cai/cai.csproj -c Release -r linux-x64 -p:PublishAot=true -p:PublishTrimmed=true

# Multi-arch release tarballs
dotnet build src/cai/cai.csproj -t:BuildContainAITarballs -p:Configuration=Release "-p:ContainAIRuntimeIdentifiers=linux-x64;linux-arm64"
```

### Project Structure

```
containai/
├── src/
│   ├── cai/                 # Native CLI host runtime
│   ├── ContainAI.Cli/       # System.CommandLine parser and routing
│   ├── AgentClientProtocol.Proxy/ # ACP proxy library
│   ├── container/           # Container image definitions
│   └── manifests/           # Authoritative sync manifests
├── tests/                   # xUnit v3 test suites
├── docs/                    # Documentation
├── SECURITY.md              # Security model
└── README.md                # Project overview
```

See [docs/architecture.md](docs/architecture.md) for detailed component documentation.

## Coding Conventions

### Shell Scripting Rules

ContainAI follows strict shell scripting conventions for portability and safety.

#### Use `command -v` instead of `which`

```bash
# Good
if command -v docker >/dev/null 2>&1; then
    printf '%s\n' "Docker found"
fi

# Bad - 'which' is not a shell builtin and may not exist
if which docker >/dev/null 2>&1; then
    printf '%s\n' "Docker found"
fi
```

#### Use `printf` instead of `echo`

```bash
# Good - handles all strings safely
printf '%s\n' "Message: $var"
printf '%s\n' "-n this is not a flag"

# Bad - echo mishandles strings starting with -n/-e
echo "Message: $var"
echo "-n this looks like a flag"
```

#### Use ASCII status markers

```bash
# Good - consistent ASCII markers
printf '%s\n' "[OK] Operation succeeded"
printf '%s\n' "[WARN] Non-critical issue"
printf '%s\n' "[ERROR] Operation failed"

# Bad - inconsistent formats
echo "OK: Operation succeeded"
echo "WARNING - Non-critical issue"
echo "Error: Operation failed"
```

#### Declare loop variables as local

In sourced scripts, loop variables pollute the caller's environment:

```bash
# Good - prevents shell pollution
my_function() {
    local item
    for item in "$@"; do
        process "$item"
    done
}

# Bad - 'item' leaks to caller's environment
my_function() {
    for item in "$@"; do
        process "$item"
    done
}
```

#### Use POSIX character classes in grep

```bash
# Good - POSIX compatible
grep -E '[[:space:]]+'

# Bad - ERE does not support \s
grep -E '\s+'
```

#### Handle errors properly with set -e

```bash
# Good - captures exit code correctly
if ! result=$(some_command); then
    printf '%s\n' "[ERROR] Command failed" >&2
    return 1
fi

# Bad - dead code under set -e
result=$(some_command)
rc=$?  # Never reached if command fails
```

### Additional Conventions

For the complete list of coding conventions, see [.flow/memory/conventions.md](.flow/memory/conventions.md).

Common pitfalls to avoid are documented in [.flow/memory/pitfalls.md](.flow/memory/pitfalls.md).

## Testing

### Test Commands

| Command | Purpose |
|--------|---------|
| `dotnet test --solution ContainAI.slnx -c Release --xunit-info` | Full unit/integration test suite |
| `dotnet test --project tests/ContainAI.Cli.Tests/ContainAI.Cli.Tests.csproj -c Release -- --filter-trait "Category=SyncIntegration" --xunit-info` | Docker-backed sync integration tests |

### Documentation Validation

Before submitting docs changes, validate internal links:

```bash
dotnet test --project tests/ContainAI.Cli.Tests/ContainAI.Cli.Tests.csproj -c Release -- --filter-trait "Category=Docs" --xunit-info
```

The docs link validation tests check internal markdown links (relative paths and anchors) in `docs/` and root markdown files.

### Running Tests

```bash
# Run from the repo root
cd containai

# Run full suite
dotnet test --solution ContainAI.slnx -c Release --xunit-info

# Run sync integration tests (requires Docker)
dotnet test --project tests/ContainAI.Cli.Tests/ContainAI.Cli.Tests.csproj --configuration Release -- --filter-trait "Category=SyncIntegration" --xunit-info
```

### Test Output Format

Tests use consistent markers for results:

```
=== Test Section Name ===
[PASS] Test description
[FAIL] Test description (with remediation hint)
[WARN] Non-critical issue
[INFO] Informational message
```

### Writing Tests

When adding new tests:

1. **Use xUnit v3** and deterministic assertions.
2. **Test behavior, not implementation details**.
3. **Use trait filters** for environment-specific tests (for example, `Category=SyncIntegration`).
4. **Keep tests hermetic** and avoid dependency on user-local state.

## Pull Request Process

### Before Submitting

1. **Run tests** to ensure nothing is broken:
   ```bash
   dotnet test --solution ContainAI.slnx -c Release --xunit-info
   dotnet test --project tests/ContainAI.Cli.Tests/ContainAI.Cli.Tests.csproj --configuration Release -- --filter-trait "Category=SyncIntegration" --xunit-info
   ```

2. **Follow coding conventions** described above

3. **Keep changes focused** - one feature or fix per PR

4. **Update documentation** if your change affects user-facing behavior

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
type(scope): description

- detail 1
- detail 2
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `test`: Test changes
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `chore`: Maintenance tasks

Examples:
```
feat(container): add port forwarding support
fix(config): handle TOML arrays correctly
docs(quickstart): add WSL2 setup instructions
test(sync): add credential isolation test
```

### PR Review Process

1. **Create a PR** against the `main` branch
2. **Fill in the PR template** with:
   - Summary of changes
   - Test plan (how you verified the change)
   - Related issues (if any)
3. **Address review feedback** promptly
4. **Squash commits** if requested (keep the commit set concise)

### Review Expectations

Reviewers will check for:
- **Correctness**: Does the code do what it claims?
- **Security**: No new attack vectors (this is a sandboxing tool)
- **Conventions**: Follows shell scripting rules above
- **Tests**: New features should have tests
- **Documentation**: User-facing changes need doc updates

## Good First Issues

Looking for a place to start? Search for issues labeled [`good first issue`](https://github.com/novotnyllc/containai/labels/good%20first%20issue).

Good first contributions include:
- Documentation improvements
- Test coverage for existing features
- Bug fixes with clear reproduction steps
- Small enhancements with limited scope

Tips for newcomers:
1. **Read the architecture docs** first: [docs/architecture.md](docs/architecture.md)
2. **Understand the security model**: [SECURITY.md](SECURITY.md)
3. **Start small** - a docs fix or test addition is a great first PR
4. **Ask questions** - open an issue if something is unclear

## Architecture Overview

For a comprehensive understanding of the codebase:

- [Architecture Overview](docs/architecture.md) - System components, data flow, and design decisions
- [Configuration Reference](docs/configuration.md) - TOML config schema and semantics
- [Technical README](src/README.md) - Image building and container internals

Key concepts:
- **Isolated runtime provisioning**: `cai setup` configures the platform runtime (managed dockerd + Sysbox on Linux/WSL2, Lima on macOS)
- **Native command runtime**: `.NET 10` CLI with `System.CommandLine` entrypoint
- **Safe defaults**: Dangerous operations require explicit CLI flags
- **Workspace-scoped config**: Per-project settings via TOML config files

## Questions?

- **Security issues**: See [SECURITY.md](SECURITY.md) for responsible disclosure
- **Bugs and features**: Open a GitHub issue
- **General questions**: Start a discussion on GitHub Discussions

Thank you for contributing to ContainAI!
