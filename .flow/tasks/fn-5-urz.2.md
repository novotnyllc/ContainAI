# fn-5-urz.2 Implement shell library structure (containai.sh, lib/*.sh)

## Description
## Overview

Create the modular shell library structure that all ContainAI commands will use. Replace the monolithic `aliases.sh` with a clean, sourced library pattern.

## Files to Create

```
agent-sandbox/
├── containai.sh          # Main entry point (source this)
└── lib/
    ├── core.sh           # Logging, error handling, color output
    ├── platform.sh       # Platform detection (WSL, macOS, Linux)
    ├── docker.sh         # Docker interaction helpers
    └── config.sh         # Config file loading (calls parse-toml.py)
```

## Implementation Details

### containai.sh
- Shebang: `#!/usr/bin/env bash`
- Strict mode: `set -euo pipefail`
- Source all lib/*.sh files
- Export public functions: `containai`, `containai_doctor`, `containai_run`, etc.

### lib/core.sh
- Logging: `_cai_info()`, `_cai_warn()`, `_cai_error()`, `_cai_debug()`
- Color output: `[OK]`, `[WARN]`, `[ERROR]` markers (per memory convention)
- All loop variables must be `local` (per memory pitfall)

### lib/platform.sh
- `_cai_detect_platform()` - returns "wsl", "macos", "linux"
- WSL detection: check `/proc/sys/fs/binfmt_misc/WSLInterop` or `WSL_DISTRO_NAME`
- Use `command -v` not `which` (per memory convention)

### lib/docker.sh
- `_cai_docker_version()` - parse Docker Desktop version
- `_cai_sandbox_available()` - check `docker sandbox version`
- Reuse patterns from `aliases.sh:129-228` (`_asb_check_sandbox`)

### lib/config.sh
- `_cai_load_config()` - load TOML config via parse-toml.py
- Config paths: `.containai/config.toml` (repo), `~/.config/containai/config.toml` (user)
- Precedence: CLI flags > env vars > repo config > user config > defaults

## Reuse

- `aliases.sh:91-126` - `_asb_check_isolation()` patterns
- `aliases.sh:129-228` - `_asb_check_sandbox()` patterns
- `sync-agent-plugins.sh:107-124` - platform detection patterns

## Naming Convention

- Internal functions: `_cai_*` prefix
- Public functions: `containai_*` prefix
- Labels: `containai.sandbox=containai` (replaces `asb.sandbox=agent-sandbox`)
## Acceptance
- [ ] `containai.sh` sources all lib/*.sh without errors
- [ ] `source agent-sandbox/containai.sh` works from any directory
- [ ] All functions use `local` for loop variables
- [ ] Uses `command -v` instead of `which`
- [ ] Status messages use `[OK]`, `[WARN]`, `[ERROR]` format
- [ ] Platform detection returns correct value for current environment
- [ ] No global variable pollution when sourced
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
