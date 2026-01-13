# fn-1.8 Add Podman for container-internal testing

## Description
Add Podman to the container for container-internal testing without requiring host Docker socket access.

### Why Podman

The container runs with ECI enabled and no Docker socket access. For testing container builds and running test containers, we need an internal solution:

- **Podman rootless**: Can run as non-root user (UID 1000)
- **No daemon**: Daemonless architecture, no socket needed
- **Compatible**: Docker CLI compatible commands
- **Nested support**: Can run containers inside containers without --privileged

### Installation in Dockerfile

```dockerfile
# Install Podman for container-internal testing
RUN apt-get update && apt-get install -y \
    podman \
    slirp4netns \
    fuse-overlayfs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure Podman for rootless operation as agent user
RUN mkdir -p /home/agent/.config/containers \
    && echo '[storage]' > /home/agent/.config/containers/storage.conf \
    && echo 'driver = "overlay"' >> /home/agent/.config/containers/storage.conf \
    && echo '[storage.options.overlay]' >> /home/agent/.config/containers/storage.conf \
    && echo 'mount_program = "/usr/bin/fuse-overlayfs"' >> /home/agent/.config/containers/storage.conf \
    && chown -R agent:agent /home/agent/.config/containers

# Set up subuid/subgid for user namespaces
RUN echo "agent:100000:65536" >> /etc/subuid \
    && echo "agent:100000:65536" >> /etc/subgid
```

### Testing Strategy

With Podman, the agent can:
1. Build Docker/OCI images (`podman build`)
2. Run test containers (`podman run`)
3. Test multi-container setups (`podman-compose` or `podman play kube`)

### Verification Commands

```bash
# Test Podman works
podman run --rm hello-world

# Test image build
podman build -t test-image .

# Test rootless operation
podman info | grep rootless
```

### Reference

- Podman rootless: https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md
- fuse-overlayfs: Required for rootless overlay storage
- slirp4netns: Required for rootless networking
## Acceptance
- [ ] Podman is installed in the container
- [ ] slirp4netns is installed (rootless networking)
- [ ] fuse-overlayfs is installed (rootless storage)
- [ ] `/etc/subuid` and `/etc/subgid` configured for agent user
- [ ] Podman storage config exists at `/home/agent/.config/containers/storage.conf`
- [ ] `podman run --rm hello-world` succeeds inside container
- [ ] `podman info` shows rootless mode enabled
- [ ] Agent can build images with `podman build` inside container
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
