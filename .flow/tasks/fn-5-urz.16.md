# fn-5-urz.16 Dockerfile updates for testing with dockerd + Sysbox

## Description
## Overview

Update the Dockerfile to support testing with dockerd + Sysbox installed. This enables building and testing ContainAI images directly inside a container that has Sysbox configured.

**Key Requirement:** Configure dockerd for a different context. NEVER interfere with Docker Desktop.

## Use Case

When running CI or development in a container that itself has Sysbox:
1. Container has dockerd + Sysbox installed
2. Tests can build/run ContainAI images directly
3. No need for external Docker daemon
4. Isolated from host Docker Desktop

## Dockerfile Changes

```dockerfile
# agent-sandbox/Dockerfile.test (new file for testing)
FROM ubuntu:24.04

# Install Docker daemon
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce docker-ce-cli containerd.io

# Install Sysbox
ARG SYSBOX_VERSION=0.6.7
RUN ARCH=$(dpkg --print-architecture) \
    && wget -O /tmp/sysbox.deb "https://downloads.nestybox.com/sysbox/releases/v${SYSBOX_VERSION}/sysbox-ce_${SYSBOX_VERSION}-0.linux_${ARCH}.deb" \
    && apt-get install -y /tmp/sysbox.deb \
    && rm /tmp/sysbox.deb

# Configure Docker with Sysbox runtime (NOT as default)
# Use a different socket to avoid conflicts
RUN mkdir -p /etc/docker
COPY <<EOF /etc/docker/daemon.json
{
  "hosts": ["unix:///var/run/docker-test.sock"],
  "runtimes": {
    "sysbox-runc": {
      "path": "/usr/bin/sysbox-runc"
    }
  }
}
EOF

# Create context for test Docker daemon
ENV DOCKER_HOST=unix:///var/run/docker-test.sock

# Startup script
COPY <<'EOF' /usr/local/bin/start-test-docker.sh
#!/bin/bash
set -e
# Start Sysbox services
sysbox-mgr &
sysbox-fs &
# Start Docker daemon on test socket
dockerd -H unix:///var/run/docker-test.sock &
# Wait for Docker to be ready
while ! docker info >/dev/null 2>&1; do sleep 1; done
echo "Docker + Sysbox ready on /var/run/docker-test.sock"
exec "$@"
EOF
RUN chmod +x /usr/local/bin/start-test-docker.sh

ENTRYPOINT ["/usr/local/bin/start-test-docker.sh"]
CMD ["bash"]
```

## Context Isolation

The test Dockerfile uses a different socket (`/var/run/docker-test.sock`) to:
1. Avoid conflicts with any host Docker socket mounted into the container
2. Allow testing `--context containai-secure` scenarios
3. Keep test Docker isolated from production Docker

## Usage in CI/Testing

```bash
# Build test image
docker build -t containai-test -f Dockerfile.test .

# Run tests inside the test container
# The container has its own dockerd + Sysbox
docker run --privileged -v $(pwd):/workspace containai-test \
    bash -c "cd /workspace && ./run-tests.sh"

# Or for interactive testing
docker run --privileged -it containai-test
```

## Integration with Existing Dockerfile

The main `agent-sandbox/Dockerfile` remains unchanged for production use. This is a separate `Dockerfile.test` for testing purposes only.

## Depends On

<!-- Updated by plan-sync: fn-5-urz.1 Sysbox context confirmed, sandbox context UNKNOWN (blocked) -->
- Task 1 spike (fn-5-urz.1) findings:
  - **Sysbox context: CONFIRMED** - Sysbox in Dockerfile.test can proceed
  - **Sandbox context: UNKNOWN** - Blocked pending Docker Desktop 4.50+ testing
- NOTE: Spike document recommends NOT proceeding until Docker Desktop testing completes

## References

- Sysbox DinD: https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md
- Docker socket configuration: https://docs.docker.com/engine/reference/commandline/dockerd/
## Acceptance
- [ ] Creates `Dockerfile.test` (separate from production Dockerfile)
- [ ] Installs Docker daemon inside container
- [ ] Installs Sysbox inside container
- [ ] Configures dockerd with different socket (`/var/run/docker-test.sock`)
- [ ] Sysbox is available as runtime (NOT default)
- [ ] Startup script starts Sysbox services and dockerd
- [ ] Can build images inside the test container
- [ ] Can run containers with Sysbox inside the test container
- [ ] Does NOT interfere with any host Docker socket mounted in
- [ ] Works with `--privileged` flag (required for nested Docker)
- [ ] Documentation shows how to use in CI/testing
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
