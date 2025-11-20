# Usage Guide

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

> **Windows shells:** All `.ps1` files in this repo are thin wrappers that call the bash scripts inside your default WSL 2 distro. Install/enable WSL 2, then run `pwsh scripts\launchers\run-copilot.ps1 --% --prompt "..."` (use `--%` to stop PowerShell from interpreting GNU-style `--flags`). Every option documented below uses the bash syntax; the PowerShell wrappers forward those arguments verbatim. Running `scripts\install.ps1` adds `scripts\launchers` to your PATH so you can invoke `run-copilot`, `launch-agent`, etc. directly from any PowerShell prompt.

## What You Need

### On Your Host Machine

1. **Container Runtime**: Docker Desktop (with WSL2 on Windows) or Docker Engine (Linux) - [docker.com](https://www.docker.com/products/docker-desktop)
   - Scripts require Docker to be installed and running before launch
2. **Host Git configuration and credentials**: Whatever identity/credential helpers you already use on the host (SSH keys, credential store, GitHub CLI, etc.). Containers inherit them automatically—no extra setup required inside the container.
3. **socat** on the host (used for credential and GPG proxies). On Linux/macOS install via package manager; on Windows install inside WSL.

### Optional: Agent Authentication

Agents use authentication configs from your host machine (mounted read-only):

- **GitHub Copilot**: Use whatever authentication you already rely on (GitHub CLI, browsers, etc.) **on the host**.
- **OpenAI Codex**: Authenticate the Codex CLI on the host, config at `~/.config/codex/`
- **Anthropic Claude**: Authenticate the Claude CLI on the host, config at `~/.config/claude/`

> **Important:** You must authenticate agents on your **host machine** before launching containers. The authentication configs are mounted read-only into containers.

#### How agent credentials stay brokered
- You authenticate on the host (`github-copilot-cli auth login`, `codex auth login`, `claude auth login`, etc.), so long-lived OAuth tokens live only under your home directory.
- Every `run-*`/`launch-agent` command asks the host-side secret broker (`scripts/runtime/secret-broker.py`) to seal the credentials and emit per-session capability bundles **before** Docker starts.
- The launcher copies those capabilities into `/run/coding-agents` (a tmpfs) and bind-mounts the relevant CLI config directories read-only. Inside the container, the trusted stubs/credential proxies redeem the capability, load the secret into their private tmpfs, and scrub it when the session ends.
- Because the broker is the only component that ever touches the raw secret file, neither your repository nor the container filesystem ever stores the plaintext tokens.

#### Verify the secret broker (optional but recommended)
```bash
./scripts/runtime/secret-broker.py health           # confirms broker.d files and permissions
ls -l ~/.config/coding-agents/broker.d              # shows keys.json/state.json/secrets.json on the host
tail -n5 ~/.config/coding-agents/security-events.log # see capability issuance events
```

- The broker auto-initializes when you run any launcher, but you can force a bootstrap with `./scripts/runtime/secret-broker.py init`.
- To stage static API keys manually (rare), run `./scripts/runtime/secret-broker.py store --stub context7 --name api_key --from-env CONTEXT7_API_KEY` and repeat per stub. Full command details live in `docs/secret-broker-architecture.md`.

### Optional: MCP Server API Keys

If using MCP servers, create `~/.config/coding-agents/mcp-secrets.env`. The launcher reads this file on the **host**, feeds it into the session renderer, and stages the values inside the secret broker—containers never need the plaintext copy.

```bash
GITHUB_TOKEN=ghp_your_token_here
CONTEXT7_API_KEY=your_key_here
```

## Optional: Pre-fetch Images

The launchers automatically pull the correct image the first time you run them. If you prefer to pre-fetch (e.g., limited bandwidth during work hours) you still can:

```bash
docker pull ghcr.io/novotnyllc/coding-agents-copilot:latest
docker pull ghcr.io/novotnyllc/coding-agents-codex:latest
docker pull ghcr.io/novotnyllc/coding-agents-claude:latest
```

## Optional: Build Images Locally

```bash
# Get the repository
git clone https://github.com/novotnyllc/coding-agents.git
cd coding-agents

# Build images
./scripts/build.sh  # Linux/Mac
.\scripts\build.ps1 # Windows
```

See [docs/build.md](docs/build.md) for details.

## Container Naming Convention

All containers follow the pattern: `{agent}-{repo}-{branch}`

**Examples:**
- `copilot-myapp-main` - GitHub Copilot on myapp repository, main branch
- `codex-website-feature` - OpenAI Codex on website repository, feature branch
- `claude-api-develop` - Anthropic Claude on api repository, develop branch

**Why this naming?**
- **Easily identifiable:** See what's running at a glance with `docker ps`
- **No conflicts:** Multiple agents can work on the same repo/different branches
- **Management friendly:** Use `list-agents` to see all your agent containers
- **Labeled for filtering:** All containers have labels for agent, repo, and branch

**Container labels** (for filtering and automation):
```bash
coding-agents.type=agent       # Identifies agent containers
coding-agents.agent=copilot    # Which agent (copilot/codex/claude)
coding-agents.repo=myapp       # Repository name
coding-agents.branch=main      # Branch name
```

## Prompt Mode

Need a quick answer without cloning a repo? Add `--prompt "<prompt>"` (same flag when running through the PowerShell shim) to **any** `run-*` launcher:

```bash
run-codex --prompt "Sketch a README outline"
run-claude --prompt "List security controls in this project"
run-copilot --prompt "Return the words: host secrets OK."
# PowerShell (use --% so PowerShell stops parsing flags)
pwsh scripts\launchers\run-claude.ps1 --% --prompt "Summarize CONTRIBUTING.md"
```

Key traits:
- Works for Copilot, Codex, and Claude; the launcher picks the correct CLI (`github-copilot-cli exec`, `codex exec`, or `claude -p`).
- Reuses your current Git repository automatically (even from a subdirectory). If no repo is detected, the launcher falls back to the legacy empty workspace so prompts still run anywhere.
- Accepts SOURCE arguments and branch flags just like a normal session while still forcing `--no-push`, keeping prompt runs read-only by default.
- Ideal for diagnostics, onboarding checks, or the host-secrets integration test path (`--with-host-secrets`).

You still get all preflight checks, secret-broker protections, and MCP wiring—the only difference is that prompt sessions auto-run the agent CLI and exit when the response is streamed back.

## Auto-Commit and Auto-Push Safety Features

All containers automatically commit and push uncommitted changes back to your local repository before shutting down. This ensures you never lose work even if a container is accidentally removed.

**How it works:**
1. When you exit a container (Ctrl+D, docker stop, remove-agent)
2. Container checks for uncommitted changes (staged or unstaged)
3. If changes exist, automatically commits them with a generated message
4. Pushes the commit to `local` remote (your host machine)
5. Container shuts down safely

**Example generated commit messages:**
```
feat: add user authentication with JWT tokens
fix: resolve null pointer exception in data loader
refactor: extract validation logic to separate class
chore: auto-commit (2 modified, 1 added)  # fallback if AI unavailable
```

The commit message is generated by asking the AI agent (GitHub Copilot) that was just running to analyze the changes and create a meaningful message. If the AI is unavailable, it falls back to a basic summary.

**Default behavior:** Auto-commit and auto-push are **enabled**

**Disable auto-commit (also disables auto-push):**
```bash
# For ephemeral launchers
AUTO_COMMIT_ON_SHUTDOWN=false run-copilot
AUTO_COMMIT_ON_SHUTDOWN=false run-codex

# PowerShell
$env:AUTO_COMMIT_ON_SHUTDOWN="false"; run-copilot.ps1
```

**Disable only auto-push (keep auto-commit):**
```bash
# For ephemeral launchers
AUTO_PUSH_ON_SHUTDOWN=false run-copilot
run-copilot --no-push

# PowerShell
# Usage Guide

The usage content has been split into focused guides so you can jump directly to the workflow you need.

## Quick Start

- Prefer the **`run-*` launchers** for day-to-day work; use `launch-agent` only when you truly need a persistent container.
- Prerequisite checks now run automatically before each launch and cache their results, so you only need to fix issues when the script reports them.
- Published container images are pulled for you—running `scripts/build.*` is only required when you want to pre-load the cache or build a custom image.
- Every container (including `run-*`) uses a managed tmux session, so you can detach with `Ctrl+B, D` and reconnect later with `scripts/launchers/connect-agent*`.
**When to disable:**
