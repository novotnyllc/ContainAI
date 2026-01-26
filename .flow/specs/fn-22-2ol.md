# Fix Sysbox CI Test Failures and Symlinks Build

## Problem

The sysbox build workflow (`.github/workflows/build-sysbox.yml`) has multiple failures:

1. **Test image missing**: `nestybox/ubuntu-focal-systemd-docker:20240618` tag doesn't exist (only `latest` available)
2. **Unnecessary kernel headers in test phase**: Test jobs install `linux-headers-$(uname -r)` but headers are only needed for sysbox build, not runtime testing
3. **Symlinks.sh build failure**: `src/container/generated/symlinks.sh` exits with code 1 during container build

## Key Context

- Test jobs at lines 192-414 use non-existent image tag (line 270, 382)
- Kernel header install at lines 205-210 and 317-322 is unnecessary for testing (sysbox is already compiled in the deb)
- **Important**: The header install step contains the only `apt-get update` in test jobs - must preserve it when removing headers
- Using `nestybox/...:latest` is lower risk than switching to `docker:dind` (Sysbox compatibility)
- symlinks.sh failure likely caused by `/mnt/agent-data` permission issues (script runs as `agent` user but `/mnt` is root-owned)

## Quick commands

```bash
# Verify workflow syntax
yq e '.' .github/workflows/build-sysbox.yml

# Test symlinks.sh locally (match user context from Dockerfile)
docker run --rm --user 1000:1000 -v $(pwd)/src/container/generated/symlinks.sh:/tmp/symlinks.sh ubuntu:22.04 sh -x /tmp/symlinks.sh
```

## Acceptance

- [ ] Test jobs use `nestybox/ubuntu-focal-systemd-docker:latest` image
- [ ] Kernel headers install step removed from test-amd64 and test-arm64 jobs
- [ ] `apt-get update` preserved in sysbox installation step
- [ ] symlinks.sh builds without error (fix /mnt/agent-data permissions in Dockerfile)
- [ ] CI workflow passes on push
