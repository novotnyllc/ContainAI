# fn-32-2mq.6 Implement image freshness check

## Description

On container start, check if a newer base image is available and notify the user without blocking.

**Implementation Location:**
- Create `src/lib/registry.sh` with helper functions
- Add freshness check call in container startup flow (after template is ready)

**Registry API Implementation:**

Create `src/lib/registry.sh` with helper functions using Python for JSON parsing (not jq):

```bash
# Get anonymous token for GHCR
_cai_ghcr_token() {
  local image="$1"  # e.g., "novotnyllc/containai"
  curl -sf --max-time 2 \
    "https://ghcr.io/token?scope=repository:${image}:pull" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))"
}

# Get manifest (returns manifest list for multi-arch images)
# Use HEAD request to get digest without downloading full manifest
_cai_ghcr_manifest_digest() {
  local image="$1" tag="$2" token="$3"
  curl -sf --max-time 2 -I \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json" \
    "https://ghcr.io/v2/${image}/manifests/${tag}" \
    | grep -i "docker-content-digest" | awk '{print $2}' | tr -d '\r'
}

# Get image config for labels (version, created date)
_cai_ghcr_config() {
  local image="$1" tag="$2" token="$3"
  # ... fetch manifest, get config digest, fetch config blob
}
```

**Digest Comparison Strategy:**
For multi-arch images, `RepoDigests` contains the **manifest list digest**. Therefore:
1. Get local digest: `docker image inspect "$image" --format '{{index .RepoDigests 0}}'`
   - This returns e.g., `ghcr.io/novotnyllc/containai@sha256:abc123...`
   - Extract just the `sha256:abc123...` part
2. Get remote manifest list digest via HEAD request (Docker-Content-Digest header)
3. Compare the two manifest list digests (like-for-like)
4. If different, fetch config to get version label for display

**Freshness Check Flow:**
1. Get local image digest from RepoDigests
2. Get local image version: `docker image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.version"}}'`
3. Query remote manifest list digest (with caching)
4. If digests differ:
   - Fetch remote config to get version label
   - Display notice using `_cai_notice()`:
```
[NOTICE] A newer ContainAI base image is available.
         Local: 0.1.0 (2026-01-10)
         Remote: 0.2.0 (2026-01-15)

         Run 'cai --refresh' to update.
```
5. Continue to container startup (never block)

**Error Handling (per epic):**
- On 401/403 auth failure: `[NOTICE] Cannot check for updates (authentication required)`
- On network timeout/error: `[NOTICE] Cannot check for updates (network error)`
- On parse error: silently skip (internal issue, not user-actionable)
- Always continue with startup (never block)

**Caching:**
- Cache directory: `~/.config/containai/cache/registry/`
- Cache key: `<image>-<tag>.json` containing `{digest, version, created, checked_at}`
- TTL: 60 minutes
- On cache hit within TTL: use cached values, skip network

## Acceptance

- [ ] New `src/lib/registry.sh` module with helper functions
- [ ] Uses Python for JSON parsing (not jq)
- [ ] Gets manifest list digest via HEAD request (Docker-Content-Digest header)
- [ ] Compares manifest list digest from local RepoDigests with remote
- [ ] Like-for-like comparison (both manifest list digests)
- [ ] Extracts version from OCI labels (`org.opencontainers.image.version`)
- [ ] Displays `[NOTICE]` message when newer image available
- [ ] Shows both local and remote version/date in message
- [ ] Suggests `cai --refresh` command
- [ ] Shows `[NOTICE] Cannot check for updates (authentication required)` on 401/403
- [ ] Shows `[NOTICE] Cannot check for updates (network error)` on timeout/network error
- [ ] Silently skips on parse errors (no notice)
- [ ] Never blocks container startup on check failure
- [ ] Registry API calls timeout at 2 seconds
- [ ] Caches results for 60 minutes per image:tag
- [ ] Cache stored in `~/.config/containai/cache/registry/`

## Done summary
Implemented image freshness check for ContainAI base images. When users start a container, the system now checks if a newer base image is available on GHCR and displays a non-blocking notice with version comparison.

**Key changes:**

1. **src/lib/registry.sh** - Added freshness check functions:
   - `_cai_local_image_digest()` - Extract digest from local image RepoDigests
   - `_cai_local_image_version()` - Get version from OCI labels
   - `_cai_local_image_created()` - Get created date from OCI labels
   - `_cai_check_image_freshness()` - Main function comparing local vs remote digests
   - `_cai_display_freshness_notice()` - Display formatted notice to user

2. **src/lib/template.sh** - Integrated freshness check into `_cai_ensure_base_image()` which runs when the base image exists locally (after the image pull prompt).

**Features:**
- Manifest list digest comparison (like-for-like)
- Python-based JSON parsing (no jq dependency)
- HTTP status code detection for auth errors (401/403)
- 60-minute caching in `~/.config/containai/cache/registry/`
- 2-second timeout budget for registry API calls
- Silent skip on parse errors (non-user-actionable)
- Never blocks container startup
## Evidence
- Commits:
- Tests: Unit tests not applicable - requires live registry
- PRs:
