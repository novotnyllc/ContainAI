# Installer End-to-End Flow (Channels, Metadata, Verification)

This document explains how the bootstrap installer (`install.sh`) resolves channels, downloads the payload by digest, and verifies the artifacts without authentication.

## Channel resolution
- Metadata source: `ghcr.io/<owner>/containai-metadata:<channel>` (also tagged `:channels`).
- Contents: channel name, version tag, immutable `sha-*`, moving tags, image digest list, payload ref/digest, and timestamp.
- Retrieval: anonymous OCI pulls against GHCR (`/v2/<ns>/containai-metadata/manifests/<channel>` → fetch JSON layer).
- Fallback: if metadata fetch fails, installer falls back to `<channel>` as the tag.

## Payload download and verification
- Payload artifact: `ghcr.io/<owner>/containai-payload:<version>` (layer media type `application/vnd.containai.payload.layer.v1+gzip` plus CycloneDX SBOM layer).
- The installer fetches the manifest by digest (if supplied) or tag, selects payload + SBOM layers, then downloads both anonymously.
- Verification: SHA256 of each downloaded blob must match the manifest descriptors (`sha256:<digest>`). Extraction aborts on mismatch.
- Contents inside payload: `host/`, `agent-configs/`, `config.toml`, `payload.sbom.json`, `SHA256SUMS`, `payload.sha256`, tools, and launcher entrypoints pinned to the published digests.

## Installation steps
1. Resolve channel/version from metadata (or `--version` override).
2. Download payload layer + SBOM by digest; verify SHA256.
3. Extract into a temp directory.
4. Run `host/utils/install-release.sh` with `--version`, `--asset-dir`, `--install-root`, and `--repo` to perform integrity-check + blue/green swap under `/opt/containai/releases/<version>`.
5. Current/previous symlinks updated; integrity-check ensures `SHA256SUMS` matches extracted contents.

## Expectations and defaults
- No authentication required for metadata or payload pulls (artifacts are public).
- Channels: `dev` (pushes), `nightly` (scheduled), `prod`/`v*` (tags). Immutable `sha-*` preserved for audit.
- SBOM: generated from the payload directory (CycloneDX) and shipped as a layer in the OCI artifact; verified against the manifest digest during install.
- Attestations: payload artifact is attested in CI; verification can be added by retrieving the in-toto statement from GitHub if needed.
