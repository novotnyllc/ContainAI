# Getting Started with ContainAI

Use this guide to get your host ready and understand what happens the first time you launch an agent container.

## Recommended Approach: Ephemeral Containers

For most use cases, use the **`run-*` scripts** (run-copilot, run-codex, run-claude). These create temporary containers that:
- Launch instantly
- Auto-remove when you exit (no cleanup needed)
- Auto-push changes before exit (safe by default)
- Work like any other CLI tool

Use **`launch-agent`** only when you need:
- Long-running background containers
- Advanced branch management
- Network proxy controls
- Multiple persistent agents on the same repo

## Choose Dev vs. Prod

- **Dev (editable from repo)**: Clone the repo and run `./host/launchers/run-codex .` (or `run-copilot`/`run-claude`). `./host/utils/env-detect.sh --format env` should report `CONTAINAI_PROFILE=dev` with roots under your home directory. Quick smoke: `./scripts/test/test-launchers.sh test_env_detection_profiles`.
- **Prod (installed bundle)**: Install the signed payload: `curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash -s -- --version vX.Y.Z`. Running `sudo /opt/containai/current/host/utils/env-detect.sh --prod-root /opt/containai/current --format env` should show `CONTAINAI_PROFILE=prod` and point to system config/data roots. Launchers live under `/opt/containai/current/host/launchers`.

## What You Need

### On Your Host Machine

1. **Container Runtime**: Docker Desktop (with WSL2 on Windows) or Docker Engine (Linux) - [docker.com](https://www.docker.com/products/docker-desktop)
   - Scripts require Docker to be installed and running
2. **Host Git configuration and credentials**: Whatever identity/credential helpers you already use on the host (SSH keys, credential store, GitHub CLI, etc.). Containers inherit them automatically—no extra setup required inside the container.
3. **socat** on the host (used for credential and GPG proxies). On Linux/macOS install via package manager; on Windows install inside WSL.

### Optional: Agent Authentication

Agents use authentication configs from your host machine (mounted read-only):

- **GitHub Copilot**: Use whatever authentication you already rely on (GitHub CLI, browsers, etc.) **on the host**.
- **OpenAI Codex**: Authenticate the Codex CLI on the host, config at `~/.config/codex/`
- **Anthropic Claude**: Authenticate the Claude CLI on the host, config at `~/.config/claude/`

> **Important:** You must authenticate agents on your **host machine** before launching containers. The authentication configs are mounted read-only into containers.

### Optional: MCP Server API Keys

If using MCP servers, create `~/.config/containai/mcp-secrets.env`. The launcher reads this file on the **host**, feeds it into the session renderer, and stages the values inside the secret broker—containers never need the plaintext copy.

```bash
GITHUB_TOKEN=ghp_your_token_here
CONTEXT7_API_KEY=your_key_here
```

## Automatic Prerequisite Checks

`scripts/verify-prerequisites.sh` (and `.ps1` on Windows) now run automatically before every launcher execution. The scripts gather a fingerprint of:
- The prerequisite script hash
- Your runtime versions (Docker, socat, git, gh)
- Host architecture (`uname -s -m`)

Results are cached at `~/.config/containai/cache/prereq-check`. Launchers silently skip the check when the cache fingerprint matches. When anything changes, you will see:

```
🔍 Running prerequisite verification (first launch or dependency change detected)...
```

If the script succeeds, the fingerprint and timestamp are updated. If it fails, the launcher aborts so you can address the missing dependency. Advanced users can temporarily bypass the automatic run by exporting `CONTAINAI_DISABLE_AUTO_PREREQ_CHECK=1`, but keeping it enabled ensures your host stays compliant.

You can always run the scripts manually:

```bash
./scripts/verify-prerequisites.sh
# or
pwsh -File scripts/verify-prerequisites.ps1
```

## Optional: Pre-fetch Images

The launchers automatically pull the correct image the first time you run them. If you prefer to pre-fetch (e.g., limited bandwidth during work hours) you still can:

```bash
docker pull ghcr.io/novotnyllc/containai-copilot:latest
docker pull ghcr.io/novotnyllc/containai-codex:latest
docker pull ghcr.io/novotnyllc/containai-claude:latest
```

## Optional: Build Images Locally

You only need to run the build scripts if you are pre-loading your local cache or developing custom images. Everyone else can rely on the published images that `run-*`/`launch-agent` pull automatically.

```bash
# Get the repository
git clone https://github.com/novotnyllc/containai.git
cd containai

# Build images
./scripts/build/build-dev.sh  # Linux/Mac (dev namespace)
pwsh scripts/build/build-dev.ps1 --% # Windows
```

See [docs/build.md](../build.md) for details on customizing the build.

## Installing the Signed Payload (dogfooding)

CI publishes a single versioned artifact per tagged release:
- `containai-payload-<version>.tar.gz` (payload tarball; GitHub attaches attestation automatically)

Install it directly (no extra tools required):
```bash
sudo ./host/utils/install-release.sh --version vX.Y.Z --repo <owner/repo>
```
The installer verifies `payload.sha256` against `SHA256SUMS`, runs integrity-check over SHA256SUMS, and performs a blue/green swap under `/opt/containai/releases/<version>`.
