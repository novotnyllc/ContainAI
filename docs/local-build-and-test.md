# Local Build & Test Guide

Most users can rely on the published images that the CI system keeps in sync with GitHub Container Registry (GHCR). Use this guide when you are:

- Developing Dockerfiles, launcher scripts, or MCP tooling.
- Testing a new dependency before opening a pull request.
- Working offline and need a fully local toolchain.

## 1. Decide: Pull vs. From Source

| Scenario | Recommended Action |
|----------|-------------------|
| You just want the latest runtime | `scripts/build/build.sh` (no flags) pulls GHCR images and tags them as `*:local` |
| You modified Dockerfiles or base scripts | `scripts/build/build.sh --from-source` (Windows: `pwsh scripts/build/build.ps1 --% --from-source`) |
| You only need certain images | Pass `--agents copilot,proxy` (Windows: use the same flag via `--%`) |

### Pulling Published Images (Default)

```bash
./scripts/build/build.sh                  # pulls base, all-agents, and specialized images
./scripts/build/build.sh --agents proxy   # only syncs the proxy image
```

The script now detects your selection, pulls the corresponding `ghcr.io/<owner>/coding-agents-*:latest` tags, and retags them locally so launchers can run offline.

### Building From Source

```bash
./scripts/build/build.sh --from-source --agents copilot,proxy
pwsh scripts/build/build.ps1 --% --from-source --agents copilot,proxy
```

From-source mode:
1. Asks whether to pull or build the base image if you selected any agent image (copilot/codex/claude).
2. Builds `coding-agents:local` from `docker/agents/all/Dockerfile`.
3. Builds each specialized agent you requested plus the Squid proxy when selected.
4. Runs Trivy secret scans after every successful build (requires `trivy` on PATH or `CODING_AGENTS_TRIVY_BIN`).

### Registry Overrides

Set `CODING_AGENTS_IMAGE_OWNER=your-org` before running the script if you publish images under a different namespace.

## 2. Running Automated Tests

| Test Type | Command | Notes |
|-----------|---------|-------|
| Launcher unit tests (bash) | `./scripts/test/test-launchers.sh [all|TEST_NAME ...]` | Fast (≈2 min). Run everything or target specific cases (see `--list`). |
| Launcher unit tests (PowerShell) | `pwsh scripts/test/test-launchers.ps1 [all|Test-Name ...]` | Thin shim to bash version. Use `--%` before GNU-style flags. |
| Branch management unit tests (bash) | `./scripts/test/test-branch-management.sh` | Exercises git branch helpers + cleanup. |
| Branch management unit tests (PowerShell) | `pwsh scripts/test/test-branch-management.ps1` | Shim to bash version; prefix `--%` when passing flags. |
| Integration tests – launchers mode | `./scripts/test/integration-test.sh --mode launchers` | Reuses lightweight mock images; end-to-end launcher coverage. |
| Integration tests – full mode | `./scripts/test/integration-test.sh --mode full` | Builds every image inside Docker-in-Docker; best for pre-PR validation. |
| Integration tests – host secrets | `./scripts/test/integration-test.sh --mode launchers --with-host-secrets` | Copies your `mcp-secrets.env` into the isolated DinD harness (or uses the host daemon if you pass `--isolation host`) and exercises the `run-<agent> --prompt` path (currently Copilot) to verify live secrets. |

> Tip: Use `./scripts/test/test-launchers.sh --list` (bash) or `pwsh scripts/test/test-launchers.ps1 --% --list` (PowerShell) to enumerate available launcher tests, then pass one or more names to run only the scenarios you need.

Tips:
- Use `--preserve` with the integration harness to keep the temporary Docker-in-Docker environment alive for debugging.
- All tests rely on mock secrets stored under `scripts/test/fixtures/mock-secrets` unless you opt into `--with-host-secrets`, which reads your real tokens from `~/.config/coding-agents/mcp-secrets.env` (or `CODING_AGENTS_MCP_SECRETS_FILE`).
- The `--with-host-secrets` flag works in both DinD and host isolation. In DinD mode, the harness securely copies your secrets file into the sandbox, deletes it after the run, and then runs a prompt-mode `--prompt` flow (currently Copilot) against your real repo. Add `--isolation host` only if you explicitly want to run on the host daemon.
- Windows users can run the bash tests inside WSL2. The PowerShell wrappers simply call the bash versions in WSL, so the same flags apply—just prefix commands with `--%` when passing GNU-style options.

For deeper explanations of each suite, consult [scripts/test/README.md](../scripts/test/README.md).

## 3. Publishing Changes

If you need to push rebuilt images to GHCR:

```bash
OWNER=novotnyllc
TAG=latest
for image in base "" copilot codex claude proxy; do
  suffix=${image:+-$image}
  docker tag coding-agents${suffix}:local ghcr.io/$OWNER/coding-agents${suffix}:$TAG
  docker push ghcr.io/$OWNER/coding-agents${suffix}:$TAG
done
```

Remember to stay logged in to GHCR (`docker login ghcr.io`). CI normally handles publishing, so manual pushes should only happen when coordinating with the maintainers.
