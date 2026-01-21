# Changelog

All notable changes to ContainAI are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project uses date-based versioning in `YYYY-MM-DD` format since it does not follow semantic versioning.

## [Unreleased]

### Added

### Changed

### Fixed

### Security

## [2026-01-20]

Documentation suite, environment variable import, and Secure Engine setup automation.

### Added
- Root README.md as canonical project entry point
- SECURITY.md with threat model and vulnerability reporting process
- CONTRIBUTING.md with development setup and contribution guidelines
- Comprehensive quickstart guide (`docs/quickstart.md`)
- Configuration reference (`docs/configuration.md`) with TOML schema documentation
- Troubleshooting guide (`docs/troubleshooting.md`) covering 20+ scenarios
- Architecture overview (`docs/architecture.md`) with Mermaid diagrams
- This CHANGELOG.md with retroactive history
- Environment variable import via `cai import` with `.env` file support
- Safe `.env` file parsing with CRLF handling and `set -e` safety
- Multiline value detection in environment file parser
- Integration tests for environment variable import functionality
- `cai setup` command for automated Sysbox runtime installation
  - WSL2 support with distro detection
  - macOS Lima VM provisioning
  - Linux native installation
- `cai validate` command for verifying Secure Engine configuration
- `Dockerfile.test` for CI testing with dockerd + Sysbox
- `cai sandbox reset` command for troubleshooting sandbox state
- `cai sandbox clear-credentials` command for credential cleanup

### Changed
- `src/README.md` (formerly `agent-sandbox/README.md`) now includes banner pointing to root README

### Fixed
- Documentation reconciliation between root and src READMEs
- TOCTOU protections for environment file imports
- Symlink traversal defense ordering in entrypoint
- Validation now correctly checks `.Runtimes` instead of assuming default runtime
- Docker context forcing for sandbox commands (required for Docker Desktop)
- Tmux configuration simplified to XDG-only paths

### Security
- Environment file validation before loading into sandbox

## [2026-01-19]

ECI detection, doctor command, unsafe opt-ins, and configuration system.

### Added
- Docker Desktop Enhanced Container Isolation (ECI) detection via uid_map and runtime check
- Docker Desktop + Sandboxes availability detection
- `cai doctor` command with decision engine for environment diagnostics
- Auto-selection of Docker context based on isolation availability
- FR-5 unsafe opt-ins with explicit acknowledgement requirements
- `--allow-host-credentials` flag for credential passthrough
- `--allow-host-docker-socket` flag for Docker socket access
- `--force` flag for bypassing safety checks
- Config `[danger]` section for persistent acknowledgements
- TOML config parser CLI (`parse-toml.py`)
- Modular shell library structure (core, platform, docker)
- TOML parser extended for `[env]` section support
- Environment configuration resolution function
- Strict mode error handling for configuration parsing
- `containai.sh` main CLI entry point
- `lib/container.sh` for container operations
- `lib/import.sh` for cai import subcommand
- `lib/export.sh` for cai export subcommand
- `lib/config.sh` with config loading and volume resolution
- CLI aliases (`containai` and `cai`)

### Fixed
- `set -e` guards for script directory resolution
- Fail-fast behavior in strict mode for all error paths
- Use `cd --` to prevent option-like path misinterpretation

### Security
- Dangerous operations now require explicit opt-in flags
- Safe defaults reject dangerous options entirely

## [2026-01-18]

CLI refactoring, sync workflow, and entrypoint hardening.

### Added
- PRD and epic specifications for ContainAI Secure Sandboxed Agent Runtime
- Configurable volume support and CLI aliases
- Platform guard for sync-agent-plugins.sh
- SYNC_MAP declarative config array for rsync-based syncing
- `sync_configs` function with rsync-based implementation
- `ensure_volume_structure` for all SYNC_MAP targets
- New symlinks and sourcing hooks for tmux, shell, copilot, gemini, opencode
- Integration test suite for sync workflow

### Changed
- Sync workflow refactored to use rsync with dry-run support
- Volume ownership bootstrapped and JSON files initialized in entrypoint
- Aliases.sh removed in favor of modular library loading

### Fixed
- Symlink traversal prevention in entrypoint
- Deep symlink validation with `safe_chmod` helper
- Credentials.json initialization with correct flags
- Path boundary checks for volume structure
- Rsync dry-run to ensure no mutations

### Security
- Prevent symlink traversal attacks in volume mounts
- Stricter path boundary checks in entrypoint

## [2026-01-17]

CLI improvements and container management enhancements.

### Added
- Interactive shell mode support in `asb` and `asbs` commands

### Changed
- Improved directory creation and symlink handling in Dockerfile
- Enhanced container ownership checks in aliases

### Fixed
- Docker arguments passed correctly to build command
- Help messages updated for container commands

## [2026-01-16]

Agent sandbox refactor and build improvements.

### Added
- Flow-Next task tracking integration
- BuildKit cache mounts for faster builds
- OCI labels for image metadata
- Plugin synchronization scripts
- Label flag and isolation detection in aliases

### Changed
- Renamed project commands from `csd`/`dotnet-sandbox` to `asb`/`agent-sandbox`
- Renamed internal variables from `_CSD_*` to `_ASB_*`
- Standardized status messages to use ASCII markers (`[OK]`, `[ERROR]`, `[WARN]`)
- Volume consolidation for simpler data management
- Documentation updated to reflect command renaming

### Fixed
- Shell precedence in cleanup commands
- Layer caching improved by moving dynamic labels to end of Dockerfile
- Early docker binary check before daemon check
- Local declarations for loop variables

## [2026-01-15]

Plugin management and environment setup improvements.

### Added
- Plugin synchronization script for Claude Code plugins
- Build scripts for agent-sandbox
- `sync-plugins.sh` script for managing Claude Code plugins in Docker sandbox

### Changed
- Simplified .NET SDK installation (removed PowerShell installation)
- Streamlined directory management for plugins

### Fixed
- Symlink handling for workspace improved
- Detached mode flag added to sandbox run command
- Mountpoint check improved in entrypoint

## [2026-01-14]

Initial Dockerfile and helper scripts.

### Added
- Dockerfile with .NET SDK and WASM workloads
- Helper scripts (`build.sh` and `aliases.sh`)
- Volume mount point directories in Dockerfile
- VS Code sync scripts
- README.md documentation
- Sandbox detection in CLI wrapper

### Fixed
- Package installation improvements
- Dockerfile syntax corrections
- Libicu version and tzdata dependencies

## [2026-01-13]

Project initialization.

### Added
- Initial Docker configuration for Claude Code sandbox
- Flow-Next configuration and usage documentation
- Ralph automation scripts
- Basic project structure

---

## Version History Summary

| Date | Milestone |
|------|-----------|
| 2026-01-20 | Documentation Suite, Env Import, Secure Engine Setup |
| 2026-01-19 | ECI Detection, Doctor Command, Unsafe Opt-ins |
| 2026-01-18 | CLI Refactor, Sync Workflow, Entrypoint Hardening |
| 2026-01-17 | CLI Improvements, Container Management |
| 2026-01-16 | Agent Sandbox Refactor, Build Improvements |
| 2026-01-15 | Plugin Management, Environment Setup |
| 2026-01-14 | Initial Dockerfile, Helper Scripts |
| 2026-01-13 | Project Initialization |

<!-- Reference links use date-range queries; once release tags exist, update to tag-based compare links -->
[Unreleased]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-21
[2026-01-20]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-20&until=2026-01-21
[2026-01-19]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-19&until=2026-01-20
[2026-01-18]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-18&until=2026-01-19
[2026-01-17]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-17&until=2026-01-18
[2026-01-16]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-16&until=2026-01-17
[2026-01-15]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-15&until=2026-01-16
[2026-01-14]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-14&until=2026-01-15
[2026-01-13]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-13&until=2026-01-14
