# ContainAI Quickstart (Users)

This guide is for people **using** ContainAI. You do not need to clone the repository—just run the installer. If you are developing or contributing, see [../getting-started.md](../getting-started.md).

## TL;DR

```
# Install the latest release channel (default: prod)
curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash

# Verify host security after install (Linux/macOS/WSL)
sudo /opt/containai/current/host/utils/check-health.sh

# Launch an agent (examples)
/opt/containai/current/host/launchers/entrypoints/run-copilot --help
/opt/containai/current/host/launchers/entrypoints/run-codex --help
/opt/containai/current/host/launchers/entrypoints/run-claude --help
```

The installer downloads the signed payload, verifies hashes/attestations (enforced on prod/nightly), installs to `/opt/containai`, and loads the required AppArmor profiles. It prompts for sudo when needed.

## Prerequisites

- **Docker**: Docker Desktop (macOS/Windows) or Docker Engine (Linux). Start Docker before launching agents.
- **socat**: Required for credential/GPG proxying (install via package manager; on Windows install inside WSL).
- **AppArmor (Linux/WSL)**: Must be enabled; the installer loads profiles automatically. If AppArmor is disabled, installation will fail until it is turned on.
- **Git credentials on the host**: Whatever you normally use (SSH agent, credential helper, GitHub CLI) are reused inside the container.

## Install

Channels:

- `prod` (default): Latest signed release (recommended for stability).
- `nightly`: Latest nightly; requires attestations and updates frequently.
- `dev`: Development channel; attestations are optional.

Run the installer (prompts for sudo on Linux/WSL):

```
curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash
```

To pick a channel explicitly:

```
curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash -s -- --channel nightly
```

To pin a specific version:

```
curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash -s -- --version vX.Y.Z
```

## After Install

1. **Health check (Linux/macOS/WSL):** `sudo /opt/containai/current/host/utils/check-health.sh` ensures Docker/AppArmor/seccomp are active and profiles are loaded.
2. **Launch agents:** Use the entrypoints under `/opt/containai/current/host/launchers/entrypoints/`.
   - Prod: `run-copilot`, `run-codex`, `run-claude`, `run-proxy`
   - Nightly: `run-copilot-nightly`, etc.
3. **Auth:** Authenticate tooling on the host (e.g., GitHub CLI for Copilot) before launching; configs mount read-only into containers.

## Updating

Re-run the install command with the desired channel or version. The installer swaps `/opt/containai/current` to the new release and preserves the previous version under `/opt/containai/previous`.

## Developing Instead?

If you intend to build images or modify code, follow the contributor guide at [../getting-started.md](../getting-started.md) which covers cloning the repo, building images, and regenerating entrypoints.
