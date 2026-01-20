# Security Policy

ContainAI provides secure Docker sandboxes for AI agent execution. Security is central to our mission.

## Supported Versions

| Version | Supported |
|---------|-----------|
| main branch | Yes |

ContainAI is pre-release software. We recommend always using the latest `main` branch.

## Security Model

ContainAI enforces sandbox-first execution with two isolation modes:

### ECI Mode (Docker Desktop 4.50+)

Enhanced Container Isolation (ECI) via Docker Desktop's `docker sandbox` command provides:
- User namespace remapping (root inside container maps to unprivileged user on host)
- Sysbox-runc runtime for enhanced syscall filtering
- Seccomp profiles and capability restrictions
- Isolated credential storage per sandbox

Detection: [`agent-sandbox/lib/eci.sh`](agent-sandbox/lib/eci.sh) verifies both uid_map remapping and sysbox-runc runtime.

### Sysbox Mode (Linux)

For Linux environments without Docker Desktop, ContainAI uses the Sysbox runtime (`--runtime=sysbox-runc`) which provides:
- Enhanced syscall filtering
- Nested container support with isolation
- User namespace isolation

Detection: [`agent-sandbox/lib/doctor.sh`](agent-sandbox/lib/doctor.sh) verifies Sysbox runtime availability in the Docker daemon.

## Security Guarantees

ContainAI enforces the following security measures:

### Enforced by Default

| Protection | Location | Description |
|------------|----------|-------------|
| Sandbox availability check | `agent-sandbox/lib/container.sh` | Verifies sandbox feature is available before starting containers |
| Fail-closed on unknown errors | `agent-sandbox/lib/container.sh` | Blocks execution rather than proceeding with unknown status |
| Symlink traversal defense | `agent-sandbox/entrypoint.sh` | `reject_symlink()` and `verify_path_under_data_dir()` prevent path escape |
| Volume mount TOCTOU protection | `agent-sandbox/entrypoint.sh` | Validates paths before and after resolution |
| Safe .env parsing | `agent-sandbox/entrypoint.sh` | CRLF handling, key validation, no shell eval |
| Credential isolation | `agent-sandbox/lib/container.sh` | Credentials stay inside container by default |
| Docker socket access denied | `agent-sandbox/lib/container.sh` | Host Docker socket not mounted by default |

**Note:** Isolation detection is best-effort. Use `--force` to bypass sandbox availability checks (not recommended). Set `CONTAINAI_REQUIRE_ISOLATION=1` for strict enforcement that also requires isolation detection to pass.

### Unsafe Opt-ins

These features bypass security boundaries and require explicit acknowledgement:

| Flag | Acknowledgement Required | Risk |
|------|-------------------------|------|
| `--allow-host-credentials` | `--i-understand-this-exposes-host-credentials` | Exposes ~/.ssh, ~/.gitconfig, API tokens to agent |
| `--allow-host-docker-socket` | `--i-understand-this-grants-root-access` | Full root access to host system |
| `--force` | None | Skips isolation verification (testing only) |

**Note:** `--allow-host-credentials` and `--allow-host-docker-socket` are ECI-only features and will error in Sysbox mode.

## Non-Goals

ContainAI does **not** protect against:

| Threat | Reason |
|--------|--------|
| Malicious container images | Users must trust images they use |
| Network-based attacks | Containers have internet access by default |
| Resource exhaustion | No cgroup limits enforced by default |
| Host kernel exploits | Container isolation relies on kernel security |

## Vulnerability Reporting

**Do not report security vulnerabilities through public GitHub issues.**

Instead, please email security reports to: **security@novotny.org**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (optional)

We will acknowledge receipt within 48 hours and provide a detailed response within 7 days.

## Safe Harbor

We support safe harbor for security researchers who:

- Make a good faith effort to avoid privacy violations, data destruction, and service disruption
- Only interact with accounts you own or have explicit permission to test
- Do not exploit vulnerabilities beyond demonstrating the issue
- Provide us reasonable time to address the issue before public disclosure

We will not pursue legal action against researchers who follow these guidelines.

## Security Architecture

For detailed technical information about ContainAI's security implementation, see:

- [Technical README - Security Section](agent-sandbox/README.md#security) - Container isolation details
- [`agent-sandbox/lib/eci.sh`](agent-sandbox/lib/eci.sh) - ECI detection implementation
- [`agent-sandbox/lib/docker.sh`](agent-sandbox/lib/docker.sh) - Docker sandbox detection
- [`agent-sandbox/lib/container.sh`](agent-sandbox/lib/container.sh) - Container start with isolation checks
- [`agent-sandbox/entrypoint.sh`](agent-sandbox/entrypoint.sh) - Volume mount security and .env parsing
