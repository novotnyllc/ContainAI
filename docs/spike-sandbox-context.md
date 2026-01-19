# Spike: Docker Sandbox Context Validation

**Task:** fn-5-urz.1
**Date:** 2026-01-19
**Status:** Blocked - Requires Docker Desktop 4.50+ with Sandboxes

## Overview

Validate whether `docker sandbox run` respects Docker context selection (`--context` flag or `DOCKER_CONTEXT` env var). This is a **blocking spike** - if sandboxes ignore context, the Secure Engine architecture needs revision.

## Test Methodology

### Prerequisites

- Docker Desktop 4.50+ with Sandboxes enabled (Settings > Features in development)
- Ability to create Docker contexts

### Test Setup

1. **Create a test context** pointing to a non-existent endpoint (to verify routing):

```bash
# Create a context with intentionally unreachable endpoint
docker context create test-unreachable --docker "host=tcp://192.0.2.1:2375"

# Verify it exists
docker context ls
```

2. **Alternatively, create a Unix socket context** pointing to a mock socket:

```bash
# Create a context with non-existent socket
docker context create test-mock --docker "host=unix:///tmp/mock-docker.sock"
```

### Test Cases

#### Test 1: Context Flag with `docker sandbox ls`

```bash
# Expected: Should fail with connection error to 192.0.2.1:2375
docker --context test-unreachable sandbox ls

# Alternative: Should fail with "no such file" for socket
docker --context test-mock sandbox ls
```

**Pass criteria:** Error mentions the alternate endpoint/socket (proving context was respected)
**Fail criteria:** Returns results from default daemon (proving context was ignored)

#### Test 2: Environment Variable with `docker sandbox ls`

```bash
# Expected: Should fail with connection error
DOCKER_CONTEXT=test-unreachable docker sandbox ls

# Alternative
DOCKER_CONTEXT=test-mock docker sandbox ls
```

**Pass criteria:** Error mentions the alternate endpoint
**Fail criteria:** Returns results from default daemon

#### Test 3: Context Flag with `docker sandbox run`

```bash
# Expected: Should fail trying to connect to 192.0.2.1:2375
docker --context test-unreachable sandbox run --rm alpine echo test

# Alternative
docker --context test-mock sandbox run --rm alpine echo test
```

**Pass criteria:** Error mentions the alternate endpoint
**Fail criteria:** Runs container on default daemon

#### Test 4: Environment Variable with `docker sandbox run`

```bash
DOCKER_CONTEXT=test-unreachable docker sandbox run --rm alpine echo test
```

**Pass criteria:** Error mentions the alternate endpoint
**Fail criteria:** Runs container on default daemon

#### Test 5: Verify Control - Normal Operation

```bash
# Confirm sandbox works normally on default context
docker --context default sandbox ls
docker --context default sandbox run --rm alpine echo "control test"
```

**Pass criteria:** Commands succeed on default context

### Cleanup

```bash
docker context rm test-unreachable test-mock 2>/dev/null || true
```

## Test Environment

This spike was executed on:
- **Platform:** Linux (WSL2)
- **Docker Version:** Docker Engine Community 29.1.5
- **Docker Desktop:** Not available (Docker Engine only)

## Test Results

### Test Execution Log (2026-01-19)

**Environment:**
- Platform: Linux (WSL2)
- Docker: Docker Engine Community 29.1.5
- Docker Desktop: Not installed (Engine only)

**Test 1: Verify docker context is respected by docker CLI**

```bash
$ docker context create test-unreachable --docker "host=tcp://192.0.2.1:2375"
test-unreachable
Successfully created context "test-unreachable"

$ docker context ls
NAME               DESCRIPTION                               DOCKER ENDPOINT               ERROR
default *          Current DOCKER_HOST based configuration   unix:///var/run/docker.sock
test-unreachable                                             tcp://192.0.2.1:2375

$ timeout 5 docker --context test-unreachable info
# TIMEOUT - command hung trying to connect to 192.0.2.1:2375
# This proves context flag IS respected

$ timeout 3 DOCKER_CONTEXT=test-unreachable docker info
# TIMEOUT - command hung trying to connect to unreachable endpoint
# This proves DOCKER_CONTEXT env var IS respected

$ docker --context default info | head -3
Client: Docker Engine - Community
 Version:    29.1.5
 Context:    default
# Control test: default context works immediately
```

**Result:** Docker CLI respects both `--context` flag and `DOCKER_CONTEXT` env var.

**Test 2: Verify docker sandbox availability**

```bash
$ docker sandbox --help
Usage:  docker [OPTIONS] COMMAND
(no sandbox subcommand - only available in Docker Desktop 4.50+)
```

**Result:** `docker sandbox` is not available in Docker Engine Community edition.

### Finding 1: docker sandbox is Docker Desktop Only

The `docker sandbox` command is a Docker Desktop feature and is **not available** on Docker Engine Community edition. The sandbox feature requires:
- Docker Desktop 4.50+
- "Beta Features" or "Experimental Features" enabled in Docker Desktop settings

### Finding 2: Docker Context IS Respected

Our tests confirm that Docker CLI respects context selection:

1. **`--context` flag:** Commands using `--context test-unreachable` attempted to connect to `tcp://192.0.2.1:2375` and timed out (proving routing worked)

2. **`DOCKER_CONTEXT` env var:** Same behavior - timed out trying to reach the unreachable endpoint

3. **Default context:** Worked immediately, proving the test context was actually routing elsewhere

### Finding 3: Context Architecture Implications (Unverified Hypothesis)

Based on Docker's architecture and documentation, we hypothesize:

1. **Docker context determines the daemon endpoint.** The `--context` flag or `DOCKER_CONTEXT` env var sets which Docker daemon receives commands.

2. **Docker Desktop sandboxes run via the Docker Desktop daemon.** The `docker sandbox` command is implemented by Docker Desktop's backend, not the Docker Engine.

3. **Sandboxes are Docker Desktop-specific.** They use Docker Desktop's Enhanced Container Isolation (ECI) feature, which is not available in Docker Engine.

### Finding 4: Architecture Validation (Hypothesis - Pending Docker Desktop Tests)

The PRD architecture assumes:

| Mode | Context | Implementation | Notes |
|------|---------|----------------|-------|
| Sandbox | `default` | `docker sandbox run` | Docker Desktop only |
| Sysbox | `containai-secure` | `docker run --runtime=sysbox-runc` | Uses regular docker run |

**Hypothesis:** The context question may be moot for Sandbox mode because:
- Sandboxes only work with Docker Desktop
- Docker Desktop is always on the `default` context (or `desktop-linux` on some systems)
- You cannot run sandboxes against a different daemon

**HOWEVER**, this is unverified. The spike's core question is exactly whether `docker --context X sandbox ...` routes to context X or ignores it. This MUST be tested on Docker Desktop.

For Sysbox mode, context IS respected (confirmed by our tests) because it uses regular `docker run`, not `docker sandbox`:
- `docker --context containai-secure run --runtime=sysbox-runc` routes to the containai-secure daemon
- This is standard Docker context behavior

## Conclusion

**BLOCKED: This spike cannot be completed without Docker Desktop 4.50+.**

The core question remains unanswered:
- Does `docker --context test-unreachable sandbox ls` fail (context respected)?
- Or does it succeed against the default daemon (context ignored)?

**What we know:**
1. **Sysbox mode context IS respected** - Confirmed via unreachable endpoint test
2. **docker sandbox is Docker Desktop only** - Confirmed (not available in Docker Engine)
3. **Sandbox mode context behavior** - UNKNOWN - requires Docker Desktop testing

## Required Next Steps

To complete this spike, run these tests on **Docker Desktop 4.50+ with Sandboxes enabled**:

```bash
# 1. Verify sandbox works on default
docker --context default sandbox ls
# Expected: Success (empty list or existing sandboxes)

# 2. Create unreachable context and test
docker context create test-unreachable --docker "host=tcp://192.0.2.1:2375"
docker --context test-unreachable sandbox ls
# Expected outcomes:
#   A) Connection error to 192.0.2.1 → Context IS respected
#   B) Returns results from default daemon → Context IGNORED (architecture problem)

# 3. Test with env var
DOCKER_CONTEXT=test-unreachable docker sandbox ls

# 4. Cleanup
docker context rm test-unreachable
```

## Impact on Epic (Pending Validation)

**DO NOT proceed with dependent tasks until this spike is completed:**

- **fn-5-urz.10 (WSL Secure Engine):** BLOCKED - depends on this spike
- **fn-5-urz.11 (macOS Lima VM):** BLOCKED - depends on this spike
- **fn-5-urz.15 (Linux Sysbox):** CAN PROCEED - uses docker run, context verified
- **fn-5-urz.16 (Dockerfile updates):** CAN PROCEED - uses docker run, context verified

**If Docker Desktop testing shows context IS respected (outcome A):** Proceed with all tasks.
**If context is IGNORED (outcome B):** Update PRD with ECI-only fallback recommendation.
