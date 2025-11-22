# GHCR Publishing & Secrets Guide

This doc explains how to build, sign, and publish ContainAI artifacts to GitHub Container Registry (GHCR) with the new host/container split.

## Prerequisites
- Docker Desktop/Engine with `docker compose`
- GHCR login: `echo "$PAT" | docker login ghcr.io -u <user> --password-stdin`
- Optional signing: `cosign` installed; `COSIGN_KEY` or keyless OIDC identity available
- Optional SBOM: `syft` installed (packaging will fail without `--skip-sbom`)

## Build & Package (Dev/Prod)
```bash
# Dev-only: build images locally (agents + proxy, dev namespace)
./scripts/build/build-dev.sh

# CI: stamp host/profile.env with prod values, then create payload
CONTAINAI_LAUNCHER_CHANNEL=prod ./scripts/release/package.sh --version v1.2.3 --out dist --sbom dist/v1.2.3/sbom.json --cosign-asset dist/v1.2.3/cosign
```

Artifacts land in `dist/<version>/`:
- `payload/` directory (host tree + SBOM + tools + SHA256SUMS + payload.sha256)
- `containai-payload-<version>.tar.gz` (payload tarball for release upload; preserves executable bits)
- `sbom.json` (CycloneDX)

Attestation is added in CI via `actions/deploy-artifact@v4` / release upload (GitHub produces the attestation for the uploaded zip automatically).

## Install (Prod / Dogfood)
```bash
sudo ./host/utils/install-release.sh --version v1.2.3 --repo owner/repo
```
Blue/green swap lives under `/opt/containai/releases/<version>` with `current`/`previous` symlinks. Install copies the tarball + signature so `check-health` can verify sigstore.

## Publish to GHCR
Prod pushes happen in CI; dev script never pushes. CI should stamp `host/profile.env` with digests for every image:

```
PROFILE=prod
IMAGE_PREFIX=containai
IMAGE_TAG=<immutable tag>
REGISTRY=ghcr.io/<owner>
IMAGE_DIGEST=sha256:<main image>
IMAGE_DIGEST_COPILOT=sha256:<copilot image>
IMAGE_DIGEST_CODEX=sha256:<codex image>
IMAGE_DIGEST_CLAUDE=sha256:<claude image>
IMAGE_DIGEST_PROXY=sha256:<proxy image>
IMAGE_DIGEST_LOG_FORWARDER=sha256:<log-forwarder image>
```

before running package/signing so launchers are pinned to the released container versions (proxy included).

### GitHub Actions secrets
- `GHCR_PAT` (or OIDC workflow permissions `packages: write`)
- `COSIGN_PASSWORD` / `COSIGN_KEY` if using key-based signing
- Optional: `SYFT_DOWNLOAD_URL` if pinning syft in CI

Recommended workflow steps:
1. `actions/checkout`
2. Write `host/profile.env` with prod values (see above) **including all IMAGE_DIGEST* entries**
3. Generate SBOM (GitHub action)
4. Fetch cosign (static)
5. `CONTAINAI_LAUNCHER_CHANNEL=prod CONTAINAI_IMAGE_DIGEST=$DIGEST CONTAINAI_IMAGE_DIGEST_COPILOT=$DIGEST_COPILOT CONTAINAI_IMAGE_DIGEST_CODEX=$DIGEST_CODEX CONTAINAI_IMAGE_DIGEST_CLAUDE=$DIGEST_CLAUDE CONTAINAI_IMAGE_DIGEST_PROXY=$DIGEST_PROXY CONTAINAI_IMAGE_DIGEST_LOG_FORWARDER=$DIGEST_LOG scripts/release/package.sh --version $GIT_TAG --out dist --sbom dist/$GIT_TAG/sbom.json --cosign-asset dist/$GIT_TAG/cosign`
6. Upload `dist/$GIT_TAG/containai-payload-$GIT_TAG.tar.gz` as the release asset (GitHub will attach attestation)
7. Build/push images using IMAGE_PREFIX/IMAGE_TAG from profile.env (proxy mandatory)

For nightly builds, set `CONTAINAI_LAUNCHER_CHANNEL=nightly` and provide all IMAGE_DIGEST* variables when invoking `package.sh` to emit `run-*-nightly` entrypoints in the payload.

## Troubleshooting
- `syft not available`: install syft or rerun with `--skip-sbom` (dev only).
- `cosign verify-blob` fails: ensure bundle contains cosign + attestation and matches payload hash; rebuild if missing.
- Podman detected: check-health will block; install Docker Desktop/Engine instead.
