# GHCR Publishing, Metadata, and Retention Runbook

This runbook covers how the single build graph publishes container images, payload artifacts, and channel metadata to GHCR. All artifacts are public and immutable by digest; moving tags (`dev`/`nightly`/`prod`/release) are applied only after every image succeeds.

## Build graph overview
- Workflow: `.github/workflows/build-runtime-images.yml`
- Jobs: build base → build `containai` → build variants (`-copilot`, `-codex`, `-claude`, `-proxy`, `-log-forwarder`) → finalize tags → publish payload → publish metadata → retention/visibility.
- Tagging: every build pushes only the immutable `sha-<commit>` tag. The finalize step re-tags the same digest to `dev`/`nightly`/`prod` (and release tag for `v*`) in a single imagetools call.
- Caches: GHA cache scopes per image (`containai-base`, `runtime-containai`, etc.).
- Scanning: Trivy secret scan runs by digest after push; no `--load`/tarball outputs.
- Attestations: `actions/attest-build-provenance@v1` for every image and the payload artifact.

## Public artifacts
- Images: `ghcr.io/<owner>/containai[-*]:sha-*` plus moving tags after finalize.
- Payload OCI: `ghcr.io/<owner>/containai-payload:<version>` (layer `application/vnd.containai.payload.layer.v1+gzip` + CycloneDX SBOM). Attested.
- Channel metadata OCI: `ghcr.io/<owner>/containai-metadata:<channel>` and `:channels` containing:
  - `channel`, `version`, `immutable_tag`, `moving_tags`
  - `images` (array of repo/digest objects for base + variants)
  - `payload` ref/digest
  - `generated_at` timestamp
- Visibility: workflow `cleanup-ghcr` step forces packages public via `gh api` PATCH on each container package.

## Required permissions/secrets
- GitHub Actions OIDC permissions: `packages: write`, `id-token: write`, `attestations: write`, `contents: read`.
- No PAT required for defaults; keep `GITHUB_TOKEN` scoped to repo.
- (Optional) `GHCR_PAT` if running workflows from forks or requiring cross-org pushes.

## Retention policy
- `actions/delete-package-versions@v4` keeps recent digests: containai (15), base/variants (10), payload/metadata (10). Moving tags are reapplied after each run.
- Retention job runs after publish; adjust counts before changing image cadence.

## How to run or recover builds
- Triggered on pushes to `main`, PRs (build only), nightly schedule, and workflow_dispatch (channel override).
- To rerun a failed publish: rerun workflow from Actions UI; final tagging ensures moving tags are updated atomically only when all images succeed.
- To manually retag a release: dispatch the workflow with `channel=prod` and `version=vX.Y.Z`; the finalize step will retag the existing `sha-*` digests.

## Release/ops checklist
- Confirm workflow succeeded: base + all variants, payload push, metadata push, cleanup.
- Verify channel metadata: `oras pull ghcr.io/<owner>/containai-metadata:<channel>` and inspect `channels.json`.
- Verify payload digest: compare manifest layer digest vs. local `sha256sum` of `containai-payload-<version>.tar.gz`.
- Ensure packages remain public (check GHCR UI) and retention job succeeded.
- Proxy base validation: run `docker run --rm --security-opt seccomp=docker/profiles/seccomp-containai-proxy.json --security-opt apparmor=containai-proxy ghcr.io/<owner>/containai-proxy:<tag> squid -v` to confirm profiles still apply on debian-slim.
