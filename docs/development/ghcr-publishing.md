# GHCR Operations Runbook

This runbook covers GitHub repository setup, manual operations, and disaster recovery for the ContainAI CI/CD pipeline. For the complete build pipeline architecture, see [build-architecture.md](build-architecture.md).

## Audience

| Role | Focus Areas |
|------|-------------|
| **Repository admins** | [GitHub Repository Setup](#github-repository-setup), [Package Visibility](#package-visibility) |
| **Release managers** | [Manual Release](#manual-release), [Emergency Rollback](#emergency-rollback) |
| **Security auditors** | [Supply Chain Security](#supply-chain-security), [Verification](#artifact-verification) |

---

## GitHub Repository Setup

### Required Permissions

The CI workflow requires these repository settings:

**Settings → Actions → General → Workflow permissions:**
- ✅ **Read and write permissions** for `GITHUB_TOKEN`
- ✅ **Allow GitHub Actions to create and approve pull requests** (if applicable)

### Secrets

The pipeline uses only automatic tokens—no long-lived secrets required:

| Secret | Source | Purpose |
|--------|--------|---------|
| `GITHUB_TOKEN` | Automatic | GHCR auth, package management, visibility |
| `id-token` | Automatic (OIDC) | SLSA provenance, Sigstore signing |

### OIDC Configuration

The `id-token: write` permission in the workflow YAML enables OIDC. This allows keyless signing via GitHub's identity provider—no private keys to manage.

---

## Package Visibility

The pipeline automatically sets package visibility to **Public** after publishing. If this fails (first run or permission issues):

1. Go to your GitHub profile/org → **Packages**
2. For each package (`containai`, `containai-base`, `containai-payload`, etc.):
   - Click **Package Settings**
   - Scroll to **Danger Zone**
   - Click **Change visibility** → **Public**

### Package List

| Package | Type | Description |
|---------|------|-------------|
| `containai-base` | Container | Base image with runtimes |
| `containai` | Container | All-agents image |
| `containai-copilot` | Container | Copilot wrapper |
| `containai-codex` | Container | Codex wrapper |
| `containai-claude` | Container | Claude wrapper |
| `containai-proxy` | Container | Squid proxy sidecar |
| `containai-log-forwarder` | Container | Log sidecar |
| `containai-payload` | OCI Artifact | Installation bundle |
| `containai-installer` | OCI Artifact | Standalone installer script |
| `containai-metadata` | OCI Artifact | Channel→version mapping |

---

## Manual Release

### Promote to Production

To manually promote a specific commit to `prod`:

1. Go to **Actions** → **Build and Publish Images**
2. Click **Run workflow**
3. Configure:
   - **Branch**: `main` (or the branch with your commit)
   - **Channel**: `prod`
   - **Version**: `v1.2.3` (semantic version tag)
4. Click **Run workflow**

The workflow will:
- Build and scan all images
- Generate attestations
- Apply `prod` and `v1.2.3` tags
- Update `containai-metadata:prod`

### Force Nightly Build

To trigger a nightly build outside the schedule:

1. Go to **Actions** → **Build and Publish Images**
2. Click **Run workflow**
3. Configure:
   - **Channel**: `nightly`
   - **Version**: (leave empty for auto-generated)
4. Click **Run workflow**

---

## Emergency Rollback

Since `prod` is a moving tag, rollback is fast:

### 1. Find the Previous Good Digest

```bash
# List recent digests
docker buildx imagetools inspect ghcr.io/OWNER/containai:prod

# Or check GitHub Packages UI for the previous sha-* tag
```

### 2. Re-tag with imagetools

```bash
# Replace OWNER and GOOD_DIGEST
docker buildx imagetools create \
    ghcr.io/OWNER/containai@sha256:GOOD_DIGEST \
    --tag ghcr.io/OWNER/containai:prod

# Repeat for all affected images
for img in containai-base containai-copilot containai-codex containai-claude containai-proxy containai-log-forwarder; do
    docker buildx imagetools create \
        ghcr.io/OWNER/${img}@sha256:GOOD_DIGEST_FOR_IMG \
        --tag ghcr.io/OWNER/${img}:prod
done
```

### 3. Update Metadata (if needed)

If the payload also needs rollback:
```bash
# Re-tag payload artifact
oras tag ghcr.io/OWNER/containai-payload:GOOD_VERSION prod

# Re-tag metadata
oras tag ghcr.io/OWNER/containai-metadata:GOOD_CHANNEL prod
```

---

## Retention Policy

The `cleanup-ghcr` job applies these retention rules:

| Category | Retention | Notes |
|----------|-----------|-------|
| **Within 180 days** | Keep all | Recent builds preserved |
| **Prod-tagged** | Keep indefinitely | Latest prod always kept even if old |
| **Dev/Nightly untagged** | Keep newest 10-15 | Per-image configurable |
| **Failed builds** | Prune aggressively | Untagged manifests removed |

### Manual Cleanup

If the automated cleanup misses something:

```bash
# List package versions (requires gh CLI)
gh api /user/packages/container/containai/versions | jq '.[] | {id, tags: .metadata.container.tags}'

# Delete a specific version
gh api --method DELETE /user/packages/container/containai/versions/VERSION_ID
```

---

## Supply Chain Security

### Security Controls

| Control | Implementation |
|---------|----------------|
| **Immutable tags** | `sha-<commit>` pushed first; channel tags applied only after all checks pass |
| **SLSA provenance** | Every image signed via GitHub OIDC; linked to workflow run + commit |
| **Secret scanning** | Trivy scans images before promotion; failures block `dev` tag update |
| **Attestation** | DSSE envelopes attached to images and payload artifacts |

### Artifact Verification

Consumers can verify artifacts using the attestation:

```bash
# Verify image attestation
gh attestation verify \
    ghcr.io/OWNER/containai:prod \
    --owner OWNER

# Verify payload attestation
gh attestation verify \
    ghcr.io/OWNER/containai-payload:prod \
    --owner OWNER
```

### SBOM Access

```bash
# Download SBOM from payload artifact
oras pull ghcr.io/OWNER/containai-payload:VERSION \
    --media-type application/vnd.cyclonedx+json \
    --output sbom.json

# Or extract from pulled payload tarball
tar -xzf payload.tar.gz payload.sbom.json
```

---

## Troubleshooting

### Workflow Fails at Push

**Symptom:** Build succeeds but push fails with 403/401

**Check:**
1. Repository permissions (Settings → Actions → General)
2. Package exists and is linked to repository
3. `GITHUB_TOKEN` has `packages: write` in workflow

### Attestation Fails

**Symptom:** `attest-build-provenance` step fails

**Check:**
1. `id-token: write` permission in job
2. Repository is public (required for OIDC)
3. Fulcio/Rekor services available (sigstore status page)

### Package Not Public

**Symptom:** Users get 401 when pulling

**Fix:**
1. Go to package settings
2. Change visibility to Public
3. Or ensure workflow ran the `cleanup-ghcr` job (it sets visibility)

### Missing Channel Tag

**Symptom:** `prod` tag not applied

**Check:**
1. Did all prior jobs succeed? (attestation, scan, etc.)
2. Was `push` output set to `true`? (PR builds don't push)
3. Check `apply-moving-tags.sh` step logs

---

## OCI Artifact Reference

### Media Types

| Artifact | Artifact Type | Layer Type |
|----------|---------------|------------|
| Payload | `application/vnd.containai.payload.v1` | `application/vnd.containai.payload.layer.v1+gzip` |
| Installer | `application/vnd.containai.installer.v1` | `application/vnd.containai.installer.v1+sh` |
| Metadata | `application/vnd.containai.metadata.v1+json` | `application/json` |
| SBOM | (bundled in payload) | `application/vnd.cyclonedx+json` |
| Attestation | (bundled in payload) | `application/vnd.in-toto+json` |

### Pulling Artifacts with ORAS

```bash
# Pull payload tarball
oras pull ghcr.io/OWNER/containai-payload:VERSION

# Pull installer script
oras pull ghcr.io/OWNER/containai-installer:VERSION

# Pull channel metadata
oras pull ghcr.io/OWNER/containai-metadata:prod
```

---

## See Also

- [build-architecture.md](build-architecture.md) — Complete pipeline reference with diagrams
- [build.md](build.md) — Container image contents and modification
- [contributing.md](contributing.md) — Development workflow
- [../security/architecture.md](../security/architecture.md) — Security model
