# Running ContainAI Containers

This guide distills everything you need to launch Copilot, Codex, or Claude containers as a daily user. It assumes you already cloned this repository and have Docker available.

## 1. Prerequisites Checklist

| Requirement | Why it matters | How to verify |
|-------------|----------------|---------------|
| Docker Desktop or Docker Engine | Containers run in an OCI runtime | `docker info` should succeed |
| `socat` | Used for Git/GPG proxy relays | `socat -V` (or install via package manager) |
| Git identity configured | Commits created in containers reuse host identity | `git config --global user.name` |
| Host credentials/token already authenticated | Launchers mount host-side auth (Copilot, git, etc.) read-only | Sign into services on the host before launching |
| (Optional) `gh` CLI | Enables OAuth for GitHub Copilot | `gh --version` |

Run the automated verifier any time:

```bash
./host/utils/verify-prerequisites.sh      # Linux/macOS
powershell -File host/utils/verify-prerequisites.ps1  # Windows
```

## 2. Install the Launchers (One Time)

```bash
./scripts/install.sh          # Linux/macOS
powershell -File scripts/install.ps1   # Windows
```

Installation simply adds the `host/launchers` directory to your PATH so you can call `run-*`/`launch-*` from any repository. You can also add the folder manually if you prefer to keep control of your shell profile.

> **Windows note:** The PowerShell entrypoints are WSL shims. They require WSL 2 and forward arguments to the bash scripts verbatim. `scripts\install.ps1` adds the launchers to your PATH so `run-copilot` works anywhere. When passing GNU-style flags (`--prompt`, `--network-proxy squid`, etc.) from PowerShell, use `--%` before the first flag (`pwsh host\launchers\run-copilot.ps1 --% --prompt "Status"`) so PowerShell does not treat them as native parameters.

## 3. Launch Patterns

### Ephemeral (Default)

Use the `run-*` shortcuts when you want the container to disappear after the session:

```bash
cd ~/my-repo
run-copilot                # or run-codex / run-claude
run-copilot --no-push      # skip the safety auto-push
run-copilot ~/other/repo   # explicit repo path
```

Ephemeral containers:
- Mount the target repository read-only
- Create an isolated branch (e.g., `copilot/session-12`)
- Auto-remove themselves when the agent exits

### Prompt Sessions

When you only need an answer (no repo work), pass `--prompt "<prompt>"` (same flag on Windows via the shim) to **any** `run-*` launcher:

```bash
run-copilot --prompt "Return the words: host secrets OK."
run-codex --prompt "Describe the branching policy"
run-claude --prompt "List required secrets"
```

Characteristics:
- Works uniformly for Copilot, Codex, and Claude. The launcher invokes the correct CLI (`github-copilot-cli exec`, `codex exec`, or `claude -p`) inside the container and exits once the response has streamed.
- Reuses your current Git repository automatically (auto-detecting the repo root even when you run from a subdirectory) and falls back to an empty workspace only when no repo exists.
- Accepts repo arguments plus `--branch` or `--use-current-branch` just like a normal session. Auto-push stays enabled whenever a real repo is mounted and is only forced off when the launcher has to synthesize an empty workspace.
- Uses the same security preflights, manifest hashing, and secret-broker flow as repo-backed sessions, so host secrets remain protected.

This is also the path exercised by `./scripts/test/integration-test.sh --with-host-secrets`, so documenting and testing it ensures parity across all agents.

### Persistent (Long-Running)

`launch-agent` keeps the container alive until you remove it:

```bash
launch-agent copilot                # uses current repo + branch
launch-agent codex --branch api-fixes
launch-agent claude ~/proj --network-proxy restricted
```

Persistent containers gain extra management features:
- Reattach with `connect-agent`
- Detach via tmux (`Ctrl-B`, `D`)
- Auto-push before removal (unless `--no-push` specified)

### Container Management

```bash
list-agents                        # show running containers
remove-agent copilot-myapp-main    # remove + auto-push
remove-agent copilot-myapp-main --no-push
connect-agent -n copilot-myapp-main
```

Naming format: `{agent}-{repo}-{branch}` (sanitized). Labels expose repo path, branch, and agent so helper scripts can discover containers quickly.

## 4. Network Profiles

| Flag | Behavior |
|------|----------|
| `--network-proxy restricted` | Launches the container with `--network none` for fully offline sessions |
| `--network-proxy squid` | Spawns a Squid sidecar (`containai-proxy:local`) that logs traffic through the inspectable proxy |
| (default) | Normal Docker networking |

Proxy images now pull automatically the first time you choose Squid mode, so you do not have to run build scripts manually.

## 5. VS Code Integration

1. Install the **Dev Containers** extension.
2. Launch an agent as usual.
3. From VS Code, run `Remote Explorer → Containers → Attach` and pick the container name (e.g., `copilot-myapp-main`).
4. VS Code will open directly inside `/workspace` with the same repo you mounted.

You can still use the tmux session from a terminal, so detaching in VS Code will not stop the container.

## 6. Secrets, MCP, and Configs

- Launchers render a session manifest on the host, hash the Docker + runtime files, and stage MCP configs per agent.
- API keys never leave the host: `secret-broker.py` seals them and places a capability bundle in `/run/containai` (tmpfs) inside the container.
- Every MCP server entry goes through the trusted `mcp-stub`, so even if an agent is compromised it does not learn the raw credential.

If you need to customize MCP servers, edit `config.toml` in your repository or set `~/.config/containai/mcp-secrets.env`. The setup flow is covered in detail in [docs/mcp-setup.md](mcp-setup.md).

## 7. Troubleshooting Quick Reference

| Symptom | Fix |
|---------|-----|
| `docker: command not found` | Install Docker or ensure it is on PATH |
| Launcher hangs on pull | Run `docker login ghcr.io` so GHCR pulls succeed |
| Container exits immediately | Check repo cleanliness; some launchers refuse to start with uncommitted changes unless you pass `--force` |
| VS Code cannot attach | Ensure Dev Containers extension is installed and Docker API is reachable |
| Proxy launch fails | Build dev proxy locally (`scripts/build/build-dev.sh --agents proxy`) or pull the published proxy tag pinned in `host/profile.env` |

## 8. Learn More

- [docs/getting-started.md](getting-started.md) – Full onboarding walkthrough (installation through first container)
- [docs/local-build-and-test.md](local-build-and-test.md) – When you need to build from source or run the automated test suite
- [docs/security-workflows.md](security-workflows.md) – Sequence diagrams for launch flow, secret brokering, and CI security gates
- [docs/cli-reference.md](cli-reference.md) – All launcher and helper command options
