# Getting Started with ContainAI

This guide covers the installation and basic usage of ContainAI. You can install without cloning the repository—just run the installer. If you prefer to install from source or need a custom setup, see [Manual Installation](usage/manual-installation.md).

## TL;DR

```
# Install the latest release channel (default: prod)
curl -fsSL https://raw.githubusercontent.com/novotnyllc/ContainAI/main/install.sh | bash

# Install nightly
curl -fsSL https://raw.githubusercontent.com/novotnyllc/ContainAI/main/install.sh | bash -s -- --channel nightly

# Verify host security after install (Linux/macOS/WSL)
sudo /opt/containai/current/host/utils/check-health.sh

# Launch an agent (examples)
/opt/containai/current/host/launchers/entrypoints/run-copilot --help
/opt/containai/current/host/launchers/entrypoints/run-codex --help
/opt/containai/current/host/launchers/entrypoints/run-claude --help
```

The installer self-verifies from GHCR (Sigstore/Fulcio), verifies the payload attestation, installs to `/opt/containai`, and loads the required AppArmor profiles. It prompts for sudo when needed.

## Prerequisites

- **Docker**: Docker Desktop (macOS/Windows) or Docker Engine (Linux). Start Docker before launching agents.
- **socat**: Required for credential/GPG proxying (install via package manager; on Windows install inside WSL).
- **AppArmor (Linux/WSL)**: Must be enabled; the installer loads profiles automatically. Enable AppArmor to ensure successful installation.
- **Git credentials on the host**: Whatever you normally use (SSH agent, credential helper, GitHub CLI) are reused inside the container.

## Install

Channels:

- `prod` (default): Latest signed release (recommended for stability).
- `nightly`: Latest nightly; requires attestations and updates frequently.
- `dev`: Development channel; attestations are optional.

Run the installer (prompts for sudo on Linux/WSL):

```
curl -fsSL https://raw.githubusercontent.com/novotnyllc/ContainAI/main/install.sh | bash
```

To pick a channel explicitly:

```
curl -fsSL https://raw.githubusercontent.com/novotnyllc/ContainAI/main/install.sh | bash -s -- --channel nightly
```

To pin a specific version:

```
curl -fsSL https://raw.githubusercontent.com/novotnyllc/ContainAI/main/install.sh | bash -s -- --version vX.Y.Z
```

On Windows, download and run the PowerShell wrapper (requires WSL and Docker Desktop):

```powershell
powershell -Command "iwr https://raw.githubusercontent.com/novotnyllc/ContainAI/main/install.ps1 -OutFile install.ps1; pwsh -File install.ps1"
```

The wrapper runs the attested `install.sh` inside WSL and syncs launcher shims into `%LOCALAPPDATA%\ContainAI`.

## After Install

1. **Health check (Linux/macOS/WSL):** `sudo /opt/containai/current/host/utils/check-health.sh` ensures Docker/AppArmor/seccomp are active and profiles are loaded.
2. **Launch agents:** Use the entrypoints under `/opt/containai/current/host/launchers/entrypoints/`.
   - Prod: `run-copilot`, `run-codex`, `run-claude`, `run-proxy`
   - Nightly: `run-copilot-nightly`, etc.
3. **Auth:** Authenticate tooling on the host (e.g., GitHub CLI for Copilot) before launching; configs mount read-only into containers.

## Updating

Re-run the install command with the desired channel or version. The installer swaps `/opt/containai/current` to the new release and preserves the previous version under `/opt/containai/previous`.

## Security

ContainAI isolates AI agents using defense-in-depth:

- **Kernel hardening**: Seccomp syscall filtering + AppArmor MAC profiles
- **Process isolation**: Non-root user (UID 1000), `no-new-privileges`, namespace sandboxing
- **Secret protection**: OAuth configs mounted read-only; MCP secrets sealed by host broker
- **Network governance**: All traffic routed through auditing proxy

The health check verifies these controls are active. For detailed security architecture, see [Security Model](security/model.md) and [Profile Architecture](security/profile-architecture.md).

## Uninstalling

To uninstall ContainAI, see the [Uninstall Guide](operations.md#uninstalling-containai).
