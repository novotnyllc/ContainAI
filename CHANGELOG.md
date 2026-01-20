# Changelog

All notable changes to ContainAI are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project uses date-based versioning in `YYYY-MM-DD` format since it does not follow semantic versioning.

## [Unreleased]

### Added
- Nothing yet

## [2026-01-20] - Documentation Suite

### Added
- Root README.md as canonical project entry point
- SECURITY.md with threat model and vulnerability reporting process
- CONTRIBUTING.md with development setup and contribution guidelines
- Comprehensive quickstart guide (`docs/quickstart.md`)
- Configuration reference (`docs/configuration.md`) with TOML schema documentation
- Troubleshooting guide (`docs/troubleshooting.md`) covering 20+ scenarios
- Architecture overview (`docs/architecture.md`) with Mermaid diagrams
- This CHANGELOG.md with retroactive history

### Changed
- `agent-sandbox/README.md` now includes banner pointing to root README

### Fixed
- Documentation reconciliation between root and agent-sandbox READMEs

## [2026-01-20] - Environment Variable Import

### Added
- `cai import-env` command for importing host environment variables into sandboxes
- Safe `.env` file parsing with CRLF handling and `set -e` safety
- Multiline value detection in environment file parser
- Integration tests for environment variable import functionality

### Fixed
- TOCTOU protections for environment file imports
- Symlink traversal defense ordering in entrypoint

### Security
- Environment file validation before loading into sandbox

## [2026-01-20] - Secure Engine Setup Commands

### Added
- `cai setup` command for automated Sysbox runtime installation
  - WSL2 support with distro detection
  - macOS Lima VM provisioning
  - Linux native installation
- `cai setup validate` for verifying Secure Engine configuration
- `Dockerfile.test` for CI testing with dockerd + Sysbox
- `cai sandbox reset` command for troubleshooting sandbox state
- `cai sandbox clear-credentials` command for credential cleanup

### Fixed
- Validation now correctly checks `.Runtimes` instead of assuming default runtime
- Docker context forcing for sandbox commands (required for Docker Desktop)
- Tmux configuration simplified to XDG-only paths

## [2026-01-19] - Unsafe Opt-ins with Acknowledgements

### Added
- FR-5 unsafe opt-ins with explicit acknowledgement requirements
- `--allow-host-credentials` flag for credential passthrough
- `--allow-host-docker-socket` flag for Docker socket access
- `--force` flag for bypassing safety checks
- Config `[danger]` section for persistent acknowledgements

### Security
- Dangerous operations now require explicit opt-in flags
- Safe defaults reject dangerous options entirely

## [2026-01-19] - Configuration System Enhancements

### Added
- TOML parser extended for `[env]` section support
- Environment configuration resolution function
- Strict mode error handling for configuration parsing

### Fixed
- `set -e` guards for script directory resolution
- Fail-fast behavior in strict mode for all error paths

## [2026-01-18] - ECI and Sysbox Dual Runtime Support

### Added
- Docker Desktop Enhanced Container Isolation (ECI) support
- Sysbox Secure Engine support as alternative runtime
- `cai doctor` command for environment detection and diagnostics
- Runtime auto-detection based on available Docker features

### Changed
- Container launch now supports both ECI and Sysbox isolation modes
- Documentation updated to reflect dual-runtime architecture

## [2025-11-16] - SSH and GPG Handling Improvements

### Added
- Enhanced SSH key handling in launch scripts
- GPG signing support with improved user guidance

### Fixed
- GPG signing disabled for test repositories to prevent CI failures
- PowerShell script output commands standardized to `Write-Output`

## [2025-11-15] - Security Architecture Documentation

### Added
- Comprehensive security findings documentation
- Architecture insights documentation
- Container runtime detection test function
- Coding conventions for PowerShell and Bash

### Fixed
- Dockerfile updates for Ubuntu 24.04 package transitions
  - `libasound2` replaced with `libasound2t64`
  - `libssl3` replaced with `libssl3t64`

### Changed
- Test execution refactored with `Invoke-Test` and `run_test` functions

## [2025-11-15] - Credential Proxy and VS Code Integration

### Added
- Credential proxy server for secure credential forwarding
- GPG proxy server for commit signing
- VS Code task setup for container development
- Prerequisite verification scripts
- MCP secrets configuration support

### Changed
- MCP configuration handling refactored for improved GitHub CLI checks

## [2025-11-14] - Documentation and Integration Testing

### Added
- Getting started guide
- VS Code integration documentation
- CLI reference documentation
- MCP setup documentation
- Network proxy configuration guide
- Integration testing framework with mock proxy and fixtures
- Resource limits for CPU, memory, and GPU in launch scripts
- Branch management with session branches and current branch option
- Launcher update checks and configuration options

### Changed
- README, USAGE, and ARCHITECTURE documentation improved
- Launch-agent command syntax changed to require agent type as first argument
- Workspace isolation model clarified with rationale against git worktrees

## [2025-11-13] - Multi-Agent Support and Auto Features

### Added
- Squid proxy sidecar for network monitoring and control
- Auto-commit and auto-push features with intelligent commit message generation
- Multi-agent support for Claude, Codex, and Copilot
- Container runtime auto-detection for Docker and Podman
- Agent custom instructions and configuration guidance
- Test suite for branch management features
- PowerShell language server support via Serena

### Changed
- Docker images moved to `novotnyllc` organization
- Base images updated to Ubuntu 24.04
- Agent configurations and initialization scripts streamlined
- Launch scripts refactored for improved `-NoPush` handling

## [2025-11-10] - Initial Release

### Added
- Ultra-simple launchers for coding agents (Claude, Codex, Copilot)
- Docker-based sandboxing for AI agent execution
- Basic workspace mounting support
- Initial project structure

---

## Version History Summary

| Date | Milestone |
|------|-----------|
| 2026-01-20 | Documentation Suite, Env Import, Secure Engine Setup |
| 2026-01-19 | Unsafe Opt-ins, Config Enhancements |
| 2026-01-18 | ECI and Sysbox Dual Runtime |
| 2025-11-16 | SSH/GPG Handling |
| 2025-11-15 | Security Docs, Credential Proxy, VS Code |
| 2025-11-14 | Documentation, Integration Testing |
| 2025-11-13 | Multi-Agent, Auto Features, Proxy Sidecar |
| 2025-11-10 | Initial Release |

[Unreleased]: https://github.com/novotnyllc/containai/compare/HEAD...main
[2026-01-20]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-20
[2026-01-19]: https://github.com/novotnyllc/containai/commits/main?after=2026-01-20&since=2026-01-19
[2026-01-18]: https://github.com/novotnyllc/containai/commits/main?after=2026-01-19&since=2026-01-18
[2025-11-16]: https://github.com/novotnyllc/containai/commits/main?after=2026-01-18&since=2025-11-16
[2025-11-15]: https://github.com/novotnyllc/containai/commits/main?after=2025-11-16&since=2025-11-15
[2025-11-14]: https://github.com/novotnyllc/containai/commits/main?after=2025-11-15&since=2025-11-14
[2025-11-13]: https://github.com/novotnyllc/containai/commits/main?after=2025-11-14&since=2025-11-13
[2025-11-10]: https://github.com/novotnyllc/containai/commits/main?after=2025-11-13&since=2025-11-10
