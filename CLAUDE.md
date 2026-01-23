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

# Run integration tests (requires Docker)
./tests/integration/test-secure-engine.sh
./tests/integration/test-sync-integration.sh

# Lint shell scripts
shellcheck -x src/*.sh src/lib/*.sh
```

## Project Structure

```
src/
├── containai.sh        # Main CLI entry point (source this)
├── lib/                # Modular shell libraries
│   ├── core.sh         # Logging utilities
│   ├── config.sh       # TOML config parsing
│   ├── container.sh    # Container lifecycle
│   ├── ssh.sh          # SSH configuration
│   └── ...             # Other modules
├── Dockerfile*         # Multi-layer Docker builds
└── build.sh            # Build script

tests/integration/      # Integration tests (require Docker)
docs/                   # Architecture, config, quickstart
.flow/                  # Flow-Next task tracking
```

## Code Conventions

- **Bash 4.0+ required** (not zsh or fish)
- Use `printf` instead of `echo` for portability
- Use `command -v` instead of `which`
- Use POSIX grep patterns (`[[:space:]]` not `\s`)
- All function variables must be `local` to prevent shell pollution
- Functions return status codes; use stdout for data, stderr for errors
- Error handling: `set -euo pipefail` at script start

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
