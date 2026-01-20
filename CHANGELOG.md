# Changelog

All notable changes to ContainAI are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project uses date-based versioning in `YYYY-MM-DD` format since it does not follow semantic versioning.

## [Unreleased]

_No unreleased changes._

## [2026-01-20]

Major documentation overhaul, environment variable import, and Secure Engine setup automation.

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
- `agent-sandbox/README.md` now includes banner pointing to root README

### Fixed
- Documentation reconciliation between root and agent-sandbox READMEs
- TOCTOU protections for environment file imports
- Symlink traversal defense ordering in entrypoint
- Validation now correctly checks `.Runtimes` instead of assuming default runtime
- Docker context forcing for sandbox commands (required for Docker Desktop)
- Tmux configuration simplified to XDG-only paths

### Security
- Environment file validation before loading into sandbox

## [2026-01-19]

Unsafe opt-ins with acknowledgements and configuration system enhancements.

### Added
- FR-5 unsafe opt-ins with explicit acknowledgement requirements
- `--allow-host-credentials` flag for credential passthrough
- `--allow-host-docker-socket` flag for Docker socket access
- `--force` flag for bypassing safety checks
- Config `[danger]` section for persistent acknowledgements
- TOML parser extended for `[env]` section support
- Environment configuration resolution function
- Strict mode error handling for configuration parsing

### Fixed
- `set -e` guards for script directory resolution
- Fail-fast behavior in strict mode for all error paths

### Security
- Dangerous operations now require explicit opt-in flags
- Safe defaults reject dangerous options entirely

## [2026-01-18]

ECI and Sysbox dual runtime support.

### Added
- Docker Desktop Enhanced Container Isolation (ECI) support
- Sysbox Secure Engine support as alternative runtime
- `cai doctor` command for environment detection and diagnostics
- Runtime auto-detection based on available Docker features

### Changed
- Container launch now supports both ECI and Sysbox isolation modes
- Documentation updated to reflect dual-runtime architecture

## [2026-01-13 to 2026-01-17]

Agent sandbox refactor and CLI improvements.

### Added
- Flow-Next task tracking integration
- BuildKit cache mounts for faster builds
- OCI labels for image metadata
- Interactive shell mode (`cai shell`)
- Plugin synchronization scripts

### Changed
- Renamed project commands from `csd`/`dotnet-sandbox` to `asb`/`agent-sandbox`
- Standardized status messages to use ASCII markers (`[OK]`, `[ERROR]`, `[WARN]`)
- Volume consolidation for simpler data management

### Fixed
- Shell precedence in cleanup commands
- Docker arguments passed correctly to build
- Layer caching improved by moving dynamic labels to end of Dockerfile

## [2025-12-01 to 2025-12-12]

Security hardening and log collection infrastructure.

### Added
- LogCollector service with Unix socket communication
- AppArmor and seccomp profile management with verification
- Supply chain security with SBOM generation and attestations
- MCP server isolation with deterministic UID allocation
- Host-side secret broker utilities for capability management
- CI testing with Docker-in-Docker and Sysbox

### Changed
- Security profiles updated for channel-specific enforcement
- Integration tests refactored for improved reliability

### Fixed
- MITM CA key permissions and certificate generation
- Proxy CA support for Node.js and other runtimes

### Security
- AppArmor profiles for agent isolation
- Seccomp filters for syscall blocking
- Audit logging for security events

## [2025-11-21 to 2025-11-30]

Release infrastructure and installer development.

### Added
- PowerShell and Bash installers for ContainAI releases
- Payload verification and attestation support
- Channel-specific security profile generation
- MITM CA generation for Squid proxy
- Log forwarder with AppArmor and seccomp profiles
- WHY.md explaining project purpose and security model

### Changed
- Project renamed from CodingAgents to ContainAI
- Security asset management refactored for channel support
- Build workflows enhanced with zstd compression

### Fixed
- AppArmor profile loading and verification
- Installer placeholder replacements validated

## [2025-11-17 to 2025-11-20]

Container hardening and security analysis.

### Added
- Comprehensive security analysis documentation
- Threat model and tool danger matrix
- Secret broker architecture for credential management
- Container hardening with cap-drop and pids-limit
- Health check scripts for installation verification
- WSL shim for cross-platform support

### Changed
- Squid proxy hardening rules block metadata and private IP ranges
- Documentation updated to specify Docker as only supported runtime

### Security
- Capability checks ensure privileges are dropped
- Seccomp mount enforcement validates syscall blocking
- Launcher integrity checks implemented

## [2025-11-16]

SSH and GPG handling improvements.

### Added
- Enhanced SSH key handling in launch scripts
- GPG signing support with improved user guidance

### Fixed
- GPG signing disabled for test repositories to prevent CI failures
- PowerShell script output commands standardized to `Write-Output`

## [2025-11-15]

Security architecture documentation and credential proxy integration.

### Added
- Comprehensive security findings documentation
- Architecture insights documentation
- Container runtime detection test function
- Coding conventions for PowerShell and Bash
- Credential proxy server for secure credential forwarding
- GPG proxy server for commit signing
- VS Code task setup for container development
- Prerequisite verification scripts
- MCP secrets configuration support

### Changed
- Test execution refactored with `Invoke-Test` and `run_test` functions
- MCP configuration handling refactored for improved GitHub CLI checks

### Fixed
- Dockerfile updates for Ubuntu 24.04 package transitions
  - `libasound2` replaced with `libasound2t64`
  - `libssl3` replaced with `libssl3t64`

## [2025-11-14]

Documentation expansion and integration testing framework.

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

## [2025-11-13]

Multi-agent support and auto features.

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

## [2025-11-10]

Initial release.

### Added
- Ultra-simple launchers for coding agents (Claude, Codex, Copilot)
- Docker-based sandboxing for AI agent execution
- Basic workspace mounting support
- Initial project structure

---

## Version History Summary

| Date Range | Milestone |
|------------|-----------|
| 2026-01-20 | Documentation Suite, Env Import, Secure Engine Setup |
| 2026-01-19 | Unsafe Opt-ins, Config Enhancements |
| 2026-01-18 | ECI and Sysbox Dual Runtime |
| 2026-01-13 to 2026-01-17 | Agent Sandbox Refactor, CLI Improvements |
| 2025-12-01 to 2025-12-12 | Security Hardening, Log Collection |
| 2025-11-21 to 2025-11-30 | Release Infrastructure, Installers |
| 2025-11-17 to 2025-11-20 | Container Hardening, Security Analysis |
| 2025-11-16 | SSH/GPG Handling |
| 2025-11-15 | Security Docs, Credential Proxy, VS Code |
| 2025-11-14 | Documentation, Integration Testing |
| 2025-11-13 | Multi-Agent, Auto Features, Proxy Sidecar |
| 2025-11-10 | Initial Release |

<!-- Reference links use date-range queries; once release tags exist, update to tag-based compare links -->
[Unreleased]: https://github.com/novotnyllc/containai/commits/main
[2026-01-20]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-20&until=2026-01-21
[2026-01-19]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-19&until=2026-01-20
[2026-01-18]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-18&until=2026-01-19
[2026-01-13 to 2026-01-17]: https://github.com/novotnyllc/containai/commits/main?since=2026-01-13&until=2026-01-18
[2025-12-01 to 2025-12-12]: https://github.com/novotnyllc/containai/commits/main?since=2025-12-01&until=2025-12-13
[2025-11-21 to 2025-11-30]: https://github.com/novotnyllc/containai/commits/main?since=2025-11-21&until=2025-12-01
[2025-11-17 to 2025-11-20]: https://github.com/novotnyllc/containai/commits/main?since=2025-11-17&until=2025-11-21
[2025-11-16]: https://github.com/novotnyllc/containai/commits/main?since=2025-11-16&until=2025-11-17
[2025-11-15]: https://github.com/novotnyllc/containai/commits/main?since=2025-11-15&until=2025-11-16
[2025-11-14]: https://github.com/novotnyllc/containai/commits/main?since=2025-11-14&until=2025-11-15
[2025-11-13]: https://github.com/novotnyllc/containai/commits/main?since=2025-11-13&until=2025-11-14
[2025-11-10]: https://github.com/novotnyllc/containai/commits/main?since=2025-11-10&until=2025-11-11
