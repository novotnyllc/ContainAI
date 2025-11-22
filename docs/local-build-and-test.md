# Local Build & Test Guide

Most users can rely on the published images that the CI system keeps in sync with GitHub Container Registry (GHCR). Use this guide when you are:

- Developing Dockerfiles, launcher scripts, or MCP tooling.
- Testing a new dependency before opening a pull request.
- Working offline and need a fully local toolchain.

## Dev vs. Prod entrypoints

- **Dev (from repo)**: Run launchers directly from your clone (`./host/launchers/entrypoints/run-codex-dev .` etc.). `./host/utils/env-detect.sh --format env` should return `CONTAINAI_PROFILE=dev`. Use this path for editing scripts/images; tags stay in the `containai-dev-*` namespace.
- **Prod (installed)**: Install the signed payload with `./host/utils/install-release.sh --version vX.Y.Z --repo owner/repo` (or via `install.sh`). `sudo /opt/containai/current/host/utils/env-detect.sh --prod-root /opt/containai/current --format env` should return `CONTAINAI_PROFILE=prod` and the system config/data roots. Use these entrypoints for dogfooding and release verification.

## 1. Decide: Build vs. Pull (Compose-backed)

| Scenario | Recommended Action |
|----------|-------------------|
| Build locally (offline or Dockerfile changes) | `scripts/build/build-dev.sh [--agents copilot,codex,claude]` (proxy always built) |
| Use published prod images | Handled by CI; prod image tags are pinned in `host/profile.env` before signing |
| Push to GHCR | CI-only (immutable releases); do not push from dev script |

### Build with docker compose (default)

```bash
./scripts/build/build-dev.sh                           # build dev-scoped images (containai-dev-*, :devlocal)
./scripts/build/build-dev.sh --agents copilot,codex     # limit to selected agents (proxy always built)
```

Prod images are delivered by CI with signed artifacts; dev tags stay in the `containai-dev-*` namespace to avoid collisions.

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
- All tests rely on mock secrets stored under `scripts/test/fixtures/mock-secrets` unless you opt into `--with-host-secrets`, which reads your real tokens from `~/.config/containai/mcp-secrets.env` (or `CONTAINAI_MCP_SECRETS_FILE`).
- The `--with-host-secrets` flag works in both DinD and host isolation. In DinD mode, the harness securely copies your secrets file into the sandbox, deletes it after the run, and then runs a prompt-mode `--prompt` flow (currently Copilot) against your real repo. Add `--isolation host` only if you explicitly want to run on the host daemon.
- Windows users can run the bash tests inside WSL2. The PowerShell wrappers simply call the bash versions in WSL, so the same flags apply—just prefix commands with `--%` when passing GNU-style options.

For deeper explanations of each suite, consult [scripts/test/README.md](../scripts/test/README.md).

## 3. Publishing Changes

- Build a local bundle (for smoke only): `./scripts/release/package.sh --version vX.Y.Z --out dist --skip-sbom --cosign-asset /path/to/cosign`
- Prod publishing happens in GitHub Actions; dev script does not push.
- Install signed packages (dogfooding): `sudo ./host/utils/install-release.sh --version vX.Y.Z --repo owner/repo` (downloads bundle, verifies hash + attestation, installs)

See [docs/ghcr-publishing.md](ghcr-publishing.md) for GHCR secrets, signing, and workflow recommendations.
