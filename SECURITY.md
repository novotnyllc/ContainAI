# Security Policy

ContainAI provides secure Docker sandboxes for AI agent execution. Security is central to our mission.

## Supported Versions

| Version | Supported |
|---------|-----------|
| main branch | Yes |

ContainAI is pre-release software. We recommend always using the latest `main` branch.

## Security Model

ContainAI enforces sandbox-first execution using a dedicated Docker daemon with the Sysbox runtime:

### Sysbox System Container Isolation

ContainAI uses a dedicated Docker daemon (`containai-docker`) with the Sysbox runtime (`sysbox-runc`) to provide:

- **User namespace remapping**: Root inside container maps to unprivileged user on host
- **Procfs/sysfs virtualization**: Containers see virtualized system information via sysbox-fs
- **Secure Docker-in-Docker**: Nested containers run without `--privileged` flag
- **Full systemd support**: Containers run systemd as PID 1 for service management
- **Enhanced syscall filtering**: Dangerous syscalls are intercepted and virtualized

**Architecture**:
- Dedicated daemon socket: `/var/run/containai-docker.sock`
- Docker context: `containai-docker`
- Isolated data directory: `/var/lib/containai-docker/`
- Default runtime: `sysbox-runc`

Detection: [`src/lib/doctor.sh`](src/lib/doctor.sh) verifies Sysbox runtime availability and [`src/lib/container.sh`](src/lib/container.sh) enforces `--runtime=sysbox-runc` for all containers.

### Alternative Isolation Solutions

For comparison with other sandboxing approaches (Docker Desktop ECI, gVisor, microVMs, etc.), see [Security Comparison](docs/security-comparison.md).

## Security Guarantees

ContainAI enforces the following security measures:

### Enforced by Default

| Protection | Location | Description |
|------------|----------|-------------|
| Isolation availability check | `src/lib/doctor.sh` | Verifies Sysbox runtime is available before starting containers |
| Fail-closed on unknown errors | `src/lib/container.sh` | Blocks execution rather than proceeding with unknown status |
| Symlink traversal defense | `src/container/entrypoint.sh` | `reject_symlink()` and `verify_path_under_data_dir()` prevent path escape |
| Volume mount TOCTOU protection | `src/container/entrypoint.sh` | Validates paths before and after resolution |
| Safe .env parsing | `src/container/entrypoint.sh` | CRLF handling, key validation, no shell eval |
| Credential isolation | `src/lib/container.sh` | Credentials stay inside container by default |
| Docker socket access denied | `src/lib/container.sh` | Host Docker socket not mounted by default |

**Note:** Isolation detection is best-effort and serves as a warning system. Use `--force` to bypass sandbox availability checks (not recommended for production use).

### Unsafe Opt-ins

These features bypass security boundaries and require explicit acknowledgement:

| Flag | Acknowledgement Required | Risk |
|------|-------------------------|------|
| `--allow-host-credentials` | `--i-understand-this-exposes-host-credentials` | Exposes ~/.ssh, ~/.gitconfig, API tokens to agent |
| `--allow-host-docker-socket` | `--i-understand-this-grants-root-access` | Full root access to host system |
| `--force` | None | Skips isolation verification (testing only) |

**Note:** `--allow-host-credentials` and `--allow-host-docker-socket` are not supported with Sysbox isolation and will error at runtime. Use `cai import` to sync credentials into containers.

### Network Security

ContainAI applies iptables rules to block container access to sensitive network destinations:

| Blocked | CIDR/Address | Reason |
|---------|--------------|--------|
| Cloud metadata endpoints | `169.254.169.254`, `169.254.170.2`, `100.100.100.200` | Prevents SSRF attacks that could steal cloud credentials (AWS, ECS, Alibaba) |
| Private IP ranges (RFC 1918) | `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` | Prevents access to internal network services |
| Link-local addresses | `169.254.0.0/16` | Prevents access to link-local services |

**Allowed**: Host gateway (Docker bridge gateway) for host communication, and all public internet addresses.

**Implementation**: Rules are applied to the `DOCKER-USER` iptables chain via [`src/lib/network.sh`](src/lib/network.sh). The `cai doctor` command verifies rules are in place.

**Per-container policies**: Opt-in egress restrictions can be configured via `.containai/network.conf` - see [Configuration Reference](docs/configuration.md#network-policy-files-runtime-mounts).

## Non-Goals

ContainAI does **not** protect against:

| Threat | Reason |
|--------|--------|
| Malicious container images | Users must trust images they use |
| Resource exhaustion | No cgroup limits enforced by default |
| Host kernel exploits | Container isolation relies on kernel security |

## Reporting a Vulnerability

**Do not report security vulnerabilities through public GitHub issues.**

### How to Report

Report vulnerabilities through [GitHub Security Advisories](https://github.com/novotnyllc/containai/security/advisories/new):

1. Go to the **Security** tab in the repository
2. Click **Report a vulnerability**
3. Fill out the advisory form

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact assessment
- Affected versions/branches
- Any suggested mitigations (optional)

### Response Timeline

- **Initial acknowledgement:** Within 48 hours
- **Detailed response:** Within 7 days
- **Resolution target:** Based on severity

### Scope

**In Scope:**
- Container isolation bypasses
- Host credential exposure
- Path traversal vulnerabilities
- Docker socket access escalation
- Authentication/authorization issues

**Out of Scope:**
- Vulnerabilities in upstream dependencies (report to respective maintainers)
- Issues requiring physical access
- Social engineering attacks
- Denial of service against your own containers

## Safe Harbor

We support safe harbor for security researchers who:

- Make a good faith effort to avoid privacy violations, data destruction, and service disruption
- Only interact with accounts you own or have explicit permission to test
- Do not exploit vulnerabilities beyond demonstrating the issue
- Provide us reasonable time to address the issue before public disclosure

We will not pursue legal action against researchers who follow these guidelines.

## Security Architecture

For detailed technical information about ContainAI's security implementation, see:

- [Security Comparison](docs/security-comparison.md) - Compare with other sandboxing solutions
- [Security Scenarios](docs/security-scenarios.md) - Real-world attack scenarios and how isolation helps
- [Technical README](src/README.md#security) - Container isolation details
- [`src/lib/docker.sh`](src/lib/docker.sh) - containai-docker context and daemon management
- [`src/lib/container.sh`](src/lib/container.sh) - Container start with Sysbox runtime enforcement
- [`src/lib/network.sh`](src/lib/network.sh) - Network security iptables rules
- [`src/container/entrypoint.sh`](src/container/entrypoint.sh) - Volume mount security and .env parsing
