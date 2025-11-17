# Unrestricted Mode Current Architecture

## FINDING-CA-01: Launch Surfaces
- Category: Current Architecture
- References: scripts/launchers/launch-agent, scripts/launchers/run-agent, docs/architecture.md
- Details: Agents are launched exclusively via bash/PowerShell launchers that wrap `docker run`/`podman run` and orchestrate repo copies, branch selection, and MCP setup. `launch-agent` creates persistent containers, while `run-agent` creates ephemeral `--rm` containers with auto-attach. Both rely on shared helpers in `scripts/utils/common-functions.sh` for branch isolation, runtime detection, and host update checks.

## FINDING-CA-02: Container Runtime Settings
- Category: Current Architecture
- References: scripts/launchers/launch-agent, scripts/launchers/run-agent
- Details: Containers run Ubuntu 24.04 images (`coding-agents-<agent>:local`). `run-agent` drops all Linux capabilities (`--cap-drop=ALL`), enforces `--pids-limit=4096`, sets `--memory` and `--memory-swap` hard limits, and keeps `--security-opt no-new-privileges:true`. `launch-agent` retains `no-new-privileges` but currently does not drop capabilities or enforce pids/memory-swap beyond user-provided CPU/memory reservations.

## FINDING-CA-03: Filesystem Scope
- Category: Current Architecture
- References: docs/architecture.md, scripts/launchers/launch-agent, scripts/runtime/entrypoint.sh
- Details: Host source repos are copied into `/workspace` inside the container (no shared RW mount). Host auth/config data are mounted read-only: `~/.gitconfig`, `~/.config/gh`, `~/.config/github-copilot`, optional `~/.config/codex|claude`, `~/.config/coding-agents/mcp-secrets.env`. Local repo path is mounted read-only at `/tmp/source-repo` for initial copy. Optional local bare remote and credential/GPG/SSH sockets are mounted to `/tmp`. Workspace writes are limited to the copied repo plus container-local temp dirs.

## FINDING-CA-04: Secrets Exposure
- Category: Current Architecture
- References: docs/architecture.md, scripts/launchers/launch-agent, scripts/runtime/entrypoint.sh, docs/security-credential-proxy.md
- Details: OAuth tokens (gh, Copilot, Codex, Claude) and MCP API keys are available via read-only mounts. Git credentials are proxied via a host-side Unix socket that only allows `get` operations. SSH agent and GPG sockets can be forwarded into the container if available. No other host secrets are mounted by default.

## FINDING-CA-05: Network Policies
- Category: Current Architecture
- References: docs/network-proxy.md, scripts/launchers/launch-agent
- Details: Three network modes exist: `allow-all` (default Docker bridge), `restricted` (`--network none`), and `squid` (egress proxy sidecar enforcing an allowlist: GitHub, Copilot, NuGet, npm, PyPI, Microsoft, Docker registries, etc.). Squid mode sets HTTP(S)_PROXY env vars; restricted mode cannot clone URLs.

## FINDING-CA-06: Git Safeguards & Prompts
- Category: Current Architecture
- References: scripts/launchers/launch-agent, scripts/runtime/entrypoint.sh, docs/architecture.md
- Details: Launchers enforce per-agent branches (`<agent>/<name>` or session numbers), auto-archive conflicting branches with unmerged commits, and prompt before branch replacement unless `--force`. Entrypoint auto-commits/pushes to a host-side bare remote on shutdown unless disabled. High-risk `--use-current-branch` requires explicit flag.

## FINDING-CA-07: Host Exposure Points
- Category: Current Architecture
- References: scripts/launchers/launch-agent, scripts/runtime/entrypoint.sh, docs/security-credential-proxy.md
- Details: No docker.sock or host filesystem mounts beyond auth directories and sockets. Containers run as non-root `agentuser` (UID 1000). Credential and GPG proxies expose Unix sockets but enforce read-only semantics and validation. SSH agent socket forward provides signing/auth ability but not direct file access. No privileged containers are used.
