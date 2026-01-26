# Implementation Review Request

## Task: fn-22-2ol.1 - Fix sysbox CI test jobs (image + headers)

## Task Specification

Fix the sysbox CI test jobs that fail due to:
1. Non-existent Docker image tag `nestybox/ubuntu-focal-systemd-docker:20240618`
2. Unnecessary kernel header installation in test phase

### Acceptance Criteria
- Image tag changed from `:20240618` to `:latest` for nestybox image
- Kernel header install steps removed from both test jobs
- `apt-get update` preserved/moved to sysbox installation step
- Workflow syntax valid (yq/yamllint passes)

## Diff to Review

```diff
diff --git a/.github/workflows/build-sysbox.yml b/.github/workflows/build-sysbox.yml
index 06d8dba..b5f21ae 100644
--- a/.github/workflows/build-sysbox.yml
+++ b/.github/workflows/build-sysbox.yml
@@ -202,17 +202,11 @@ jobs:
           name: sysbox-ce-amd64
           path: dist

-      - name: Install kernel headers (best-effort)
-        run: |
-          sudo apt-get update
-          sudo apt-get install -y linux-headers-$(uname -r) || \
-            sudo apt-get install -y linux-headers-azure || \
-            echo "::warning::Kernel headers unavailable, some sysbox features may not work"
-
       - name: Install sysbox deb
         run: |
           echo "Installing sysbox deb package..."
           ls -la dist/*.deb
+          sudo apt-get update
           sudo DEBIAN_FRONTEND=noninteractive dpkg -i dist/sysbox-ce*.deb || true
           sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y

@@ -267,7 +261,7 @@ jobs:

           echo "Starting sysbox container: $CONTAINER_NAME"
           docker run --runtime=sysbox-runc -d --name="$CONTAINER_NAME" \
-            nestybox/ubuntu-focal-systemd-docker:20240618
+            nestybox/ubuntu-focal-systemd-docker:latest

           # Wait for inner dockerd to be ready (up to 60s)
           echo "Waiting for inner dockerd to start..."
@@ -314,17 +308,11 @@ jobs:
           name: sysbox-ce-arm64
           path: dist

-      - name: Install kernel headers (best-effort)
-        run: |
-          sudo apt-get update
-          sudo apt-get install -y linux-headers-$(uname -r) || \
-            sudo apt-get install -y linux-headers-azure || \
-            echo "::warning::Kernel headers unavailable, some sysbox features may not work"
-
       - name: Install sysbox deb
         run: |
           echo "Installing sysbox deb package..."
           ls -la dist/*.deb
+          sudo apt-get update
           sudo DEBIAN_FRONTEND=noninteractive dpkg -i dist/sysbox-ce*.deb || true
           sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y

@@ -379,7 +367,7 @@ jobs:

           echo "Starting sysbox container: $CONTAINER_NAME"
           docker run --runtime=sysbox-runc -d --name="$CONTAINER_NAME" \
-            nestybox/ubuntu-focal-systemd-docker:20240618
+            nestybox/ubuntu-focal-systemd-docker:latest

           # Wait for inner dockerd to be ready (up to 60s)
           echo "Waiting for inner dockerd to start..."
```

## Review Instructions

You are a John Carmack-level code reviewer. Analyze this implementation against the task specification.

Evaluate:
1. Does the implementation meet ALL acceptance criteria?
2. Are there any bugs, edge cases, or issues?
3. Is the approach correct and minimal?

Respond with ONE verdict line at the start:
- `VERDICT: SHIP` - Implementation is correct and complete
- `VERDICT: NEEDS_WORK` - Minor issues to fix (list them)
- `VERDICT: MAJOR_RETHINK` - Fundamental approach is wrong

Then provide your analysis.
