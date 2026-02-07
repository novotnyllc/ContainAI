# CI Fixes Implementation Plan: User Manifests Import + macOS Lima Docker Access

> Historical context: this plan was drafted against legacy shell files. The current implementation is .NET-native; equivalent logic now lives under `src/cai/`.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix CI failures by syncing user manifest entries during import and making macOS Lima Docker access reliable on GitHub Actions (macos-15-intel).

**Architecture:** Extend import pipeline to include user manifest entries by parsing host manifests at import time. For macOS Lima on CI, expose Docker via a TCP endpoint (forwarded to localhost) to avoid unix socket access issues, and ensure context creation targets the correct endpoint.

**Tech Stack:** .NET 10 native CLI (`cai`), GitHub Actions, Lima, Docker.

---

### Task 1: Reproduce the failing user manifest test (RED)

**Files:**
- Test: `tests/integration/test-user-manifests.sh`

**Step 1: Run the failing test (if Docker is available)**

Run:
```bash
./tests/integration/test-user-manifests.sh
```

Expected:
FAIL with output similar to:
```
[FAIL] User config not synced to volume
```

**Step 2: Capture current failure context**

- Note the failing case: "User manifest entries sync custom data".
- Confirm that only the manifest directory is synced, not its entries.

---

### Task 2: Add user manifest entries to import sync map (GREEN)

**Files:**
- Modify: `src/cai/NativeLifecycleCommandRuntime.cs`
- Reference: `src/cai/ManifestTomlParser.cs`

**Step 1: Implement user manifest parsing for import**

Add helper logic in `src/cai/NativeLifecycleCommandRuntime.cs`:
- `_import_get_parse_manifest_script` (resolve parser path)
- `_import_generate_user_manifest_entries` (parse user manifest dir and emit `/source/...:/target/...:flags` entries)

Parsing rules:
- Only include type `entry`
- Skip disabled entries (default parser behavior)
- Skip absolute `source` paths
- Strip leading `/` from `target` if present
- Skip entries missing flags (warn in stderr)

**Step 2: Integrate parsed user entries**

After manifest entries are loaded and before exclude rewriting:
- Append parsed user entries to `sync_map_entries`
- Honor `--no-secrets` by skipping entries with `s` flag
- Emit dry-run info lines when `--dry-run` is set

**Step 3: Verify**

Run (if Docker available):
```bash
./tests/integration/test-user-manifests.sh
```
Expected: PASS

---

### Task 3: Stabilize macOS Lima Docker access on CI (RED)

**Files:**
- Modify: `src/cai/NativeLifecycleCommandRuntime.cs`
- Modify: `.github/workflows/docker.yml` (only if needed for env or logs)

**Step 1: Confirm failure signature**

From CI logs:
- `Docker not accessible via Lima socket after 120s`
- `error during connect .../docker.sock ... EOF`

---

### Task 4: Use TCP Docker endpoint for Lima on GitHub Actions (GREEN)

**Files:**
- Modify: `src/cai/NativeLifecycleCommandRuntime.cs`

**Step 1: Add TCP mode helpers**

Add constants/helpers:
- `_CAI_LIMA_TCP_PORT` (default `2375`)
- `_cai_lima_use_tcp` (true when `GITHUB_ACTIONS=true` or `CONTAINAI_LIMA_USE_TCP=1/true`)
- `_cai_lima_docker_host` (returns `tcp://127.0.0.1:PORT` or `unix://...`)

**Step 2: Update Lima template**

When TCP mode enabled:
- Update `/etc/containai/docker/daemon.json` to include:
  - `"hosts": ["unix:///var/run/docker.sock","tcp://0.0.0.0:2375"]`

**Step 3: Update readiness checks and context creation**

Use `_cai_lima_docker_host` in:
- `_cai_lima_wait_socket` (TCP: skip socket existence check, poll `docker info` via TCP)
- `_cai_lima_create_context` (create context with `host=tcp://127.0.0.1:2375`)
- `_cai_lima_verify_install` (use TCP host for docker info)

**Step 4: Verify**

In CI (macos-15-intel), `cai setup` should:
- Create VM
- Pass readiness checks using TCP host
- Create `containai-docker` context successfully

---

### Task 5: Push and Observe CI

**Step 1: Commit changes**
```bash
git add src/cai/NativeLifecycleCommandRuntime.cs src/cai/ManifestTomlParser.cs docs/plans/2026-02-05-ci-fix-user-manifest-macos-lima.md
git commit -m "fix(ci): sync user manifests and use TCP for macOS Lima in CI"
```

**Step 2: Push and monitor**
```bash
git push
gh run list -L 5
```

Expected:
- `test (amd64/arm64)` user manifest tests pass
- `e2e-test-macos-intel` setup passes
