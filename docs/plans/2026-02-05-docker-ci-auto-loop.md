# Docker CI Auto-Loop Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the Docker workflow failure and add an automatic local watcher that monitors the Docker workflow on `main` until it is green.

**Architecture:** Update the Docker workflow to generate container files from `src/manifests/`. Add a local bash watcher script that polls the latest Docker workflow run on `main`, reports failures, and exits only when the run is green (no re-run attempts). Validate the generator scripts locally before pushing.

**Tech Stack:** GitHub Actions, `gh` CLI, bash.

### Task 1: Fix Docker Workflow Manifest Path

**Files:**
- Modify: `.github/workflows/docker.yml`

**Step 1: Update generator inputs**
```bash
# In Generate container files step
./src/scripts/gen-dockerfile-symlinks.sh src/manifests artifacts/container-generated/symlinks.sh
./src/scripts/gen-init-dirs.sh src/manifests artifacts/container-generated/init-dirs.sh
./src/scripts/gen-container-link-spec.sh src/manifests artifacts/container-generated/link-spec.json
./src/scripts/gen-agent-wrappers.sh src/manifests artifacts/container-generated/agent-wrappers.sh
```

**Step 2: Commit**
```bash
git add .github/workflows/docker.yml
git commit -m "ci: generate container files from manifests"
```

### Task 2: Add Automatic CI Watcher Script

**Files:**
- Create: `scripts/ci-watch-docker.sh`

**Step 1: Create watcher script**
```bash
#!/usr/bin/env bash
set -euo pipefail

workflow_name="Build and Push Docker Image"
branch="main"
interval_seconds="${CI_WATCH_INTERVAL_SECONDS:-60}"

if ! command -v gh >/dev/null 2>&1; then
    printf 'ERROR: gh CLI is required\n' >&2
    exit 1
fi

last_run_id=""

while true; do
    run_id="$(gh run list -L 1 --workflow "$workflow_name" --branch "$branch" --json databaseId --jq '.[0].databaseId')"
    if [[ -z "$run_id" ]]; then
        printf 'ERROR: no runs found for %s on %s\n' "$workflow_name" "$branch" >&2
        exit 1
    fi

    conclusion="$(gh run view "$run_id" --json conclusion,status --jq '.conclusion // .status')"

    if [[ "$run_id" != "$last_run_id" ]]; then
        printf 'Run %s status: %s\n' "$run_id" "$conclusion"
        last_run_id="$run_id"

        if [[ "$conclusion" != "success" ]]; then
            gh run view "$run_id" --json jobs --jq '.jobs[] | select(.conclusion=="failure") | "\(.name) \(.url)"'
        fi
    fi

    if [[ "$conclusion" == "success" ]]; then
        printf 'OK: latest %s run on %s is green (%s)\n' "$workflow_name" "$branch" "$run_id"
        exit 0
    fi

    sleep "$interval_seconds"
done
```

**Step 2: Make executable**
```bash
chmod +x scripts/ci-watch-docker.sh
```

**Step 3: Commit**
```bash
git add scripts/ci-watch-docker.sh
git commit -m "tools: add automatic docker CI watcher"
```

### Task 3: Local Validation (No Docker Required)

**Files:**
- None

**Step 1: Ensure output directory exists**
```bash
mkdir -p /tmp/containai-ci
```

**Step 2: Run generators locally**
```bash
./src/scripts/gen-dockerfile-symlinks.sh src/manifests /tmp/containai-ci/symlinks.sh
./src/scripts/gen-init-dirs.sh src/manifests /tmp/containai-ci/init-dirs.sh
./src/scripts/gen-container-link-spec.sh src/manifests /tmp/containai-ci/link-spec.json
./src/scripts/gen-agent-wrappers.sh src/manifests /tmp/containai-ci/agent-wrappers.sh
```

**Expected:** all commands succeed and output files are created.

### Task 4: Push and Watch

**Step 1: Push changes**
```bash
git push
```

**Step 2: Start watcher**
```bash
./scripts/ci-watch-docker.sh
```

**Step 3: When a failure appears**
- Analyze failure, fix, commit, push.
- Leave the watcher running; it will detect the new run and continue.
