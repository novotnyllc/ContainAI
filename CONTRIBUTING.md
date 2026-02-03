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

- **Bash 4.0+** - The CLI requires bash (not zsh or fish)
- **Docker Desktop 4.50+** with sandbox feature enabled, OR
- **Sysbox runtime** installed (for Linux/WSL2/macOS via Lima)
- **Git** for version control

### Shell Requirement

ContainAI scripts require **bash**. If your default shell is zsh or fish:

```bash
# Switch to bash before developing
bash

# Or run bash explicitly
bash ./tests/integration/test-secure-engine.sh
```

### Setup

```bash
# Source the CLI to load all functions
source src/containai.sh

# Verify your environment
cai doctor
```

### Building Images (Buildx Preferred)

ContainAI builds use Docker buildx by default to match CI behavior. The default platform is `linux/<host-arch>` even on macOS (builds run inside Lima). Use `--build-setup` to configure a buildx builder and binfmt if required.

```bash
# Build all layers for the current host arch (buildx + --load)
./src/build.sh

# Configure buildx builder/binfmt (first-time setup)
./src/build.sh --build-setup

# Build and tag for a registry (all layers)
./src/build.sh --image-prefix ghcr.io/ORG/containai --platforms linux/amd64,linux/arm64 --push --build-setup

# Multi-arch build (CI style) - requires --push or --output
./src/build.sh --platforms linux/amd64,linux/arm64 --push --build-setup
```

### Project Structure

```
containai/
├── src/                     # Main CLI and container runtime
│   ├── containai.sh         # Entry point (sources lib/*.sh)
│   ├── lib/                 # Modular shell libraries
│   │   ├── core.sh          # Logging utilities
│   │   ├── platform.sh      # OS detection
│   │   ├── docker.sh        # Docker helpers
│   │   ├── eci.sh           # ECI detection
│   │   ├── doctor.sh        # Health checks
│   │   ├── config.sh        # TOML parsing
│   │   ├── container.sh     # Container lifecycle
│   │   ├── import.sh        # Dotfile sync
│   │   ├── export.sh        # Volume backup
│   │   ├── setup.sh         # Sysbox installation
│   │   └── env.sh           # Environment handling
│   └── container/           # Container-specific content
│       ├── entrypoint.sh    # Container entrypoint (security validation)
│       └── Dockerfile*      # Container image definitions
├── tests/                   # Test suites
│   ├── unit/                # Unit tests (portable)
│   └── integration/         # Integration tests (require Docker)
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

### Test Scripts

Integration tests are located in `tests/integration/`:

| Script | Purpose |
|--------|---------|
| `test-secure-engine.sh` | Verifies Sysbox runtime and Docker context setup |
| `test-sync-integration.sh` | Tests dotfile sync, config parsing, container lifecycle |

### Documentation Validation

Before submitting docs changes, validate internal links:

```bash
./scripts/check-doc-links.sh
```

This script validates all internal markdown links (relative paths and anchors) in `docs/` and root markdown files. It catches broken links, invalid anchors, and handles GitHub's duplicate heading behavior.

### Running Tests

```bash
# Run from the repo root
cd containai

# Run secure engine tests
./tests/integration/test-secure-engine.sh

# Run sync integration tests (requires Docker)
./tests/integration/test-sync-integration.sh
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

1. **Use the standard markers**: `[PASS]`, `[FAIL]`, `[WARN]`, `[INFO]`
2. **Test actual behavior**: Verify sentinel values or specific outputs, not just that operations succeed
3. **Provide remediation hints**: On failure, tell the user how to fix it
4. **Be hermetic**: Clear external env vars with `env -u` to avoid test pollution

Example test structure:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/containai.sh"

# Test helpers
pass() { printf '%s\n' "[PASS] $*"; }
fail() { printf '%s\n' "[FAIL] $*" >&2; FAILED=1; }
warn() { printf '%s\n' "[WARN] $*"; }
info() { printf '%s\n' "[INFO] $*"; }
section() { printf '\n%s\n' "=== $* ==="; }

FAILED=0

# Tests
section "Feature X"
if some_condition; then
    pass "Feature X works as expected"
else
    fail "Feature X failed"
    info "  Remediation: Check Y and Z"
fi

exit $FAILED
```

## Pull Request Process

### Before Submitting

1. **Run tests** to ensure nothing is broken:
   ```bash
   ./tests/integration/test-secure-engine.sh
   ./tests/integration/test-sync-integration.sh
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
4. **Squash commits** if requested (keep history clean)

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
- **Dual isolation paths**: Docker Desktop sandbox (ECI) or Sysbox runtime
- **Modular libraries**: `src/lib/*.sh` modules with explicit dependencies
- **Safe defaults**: Dangerous operations require explicit CLI flags
- **Workspace-scoped config**: Per-project settings via TOML config files

## Questions?

- **Security issues**: See [SECURITY.md](SECURITY.md) for responsible disclosure
- **Bugs and features**: Open a GitHub issue
- **General questions**: Start a discussion on GitHub Discussions

Thank you for contributing to ContainAI!
