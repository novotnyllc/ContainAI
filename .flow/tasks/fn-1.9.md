# fn-1.9 Apply security hardening (capabilities, seccomp)

## Description
Apply security hardening to the container for running potentially untrusted code. The host already has ECI enabled and no Docker socket access.

### Security Layers

1. **Non-root user**: Already using `agent` (UID 1000)
2. **Capability dropping**: Drop all, add only required
3. **Read-only root filesystem**: Use tmpfs for temp, volumes for data
4. **no-new-privileges**: Prevent privilege escalation
5. **seccomp profile**: Use Docker default or custom restrictive profile

### Implementation in run.sh and devcontainer.json

#### run.sh security flags
```bash
docker run -it --rm \
    --cap-drop=ALL \
    --cap-add=CHOWN \
    --cap-add=DAC_OVERRIDE \
    --cap-add=FOWNER \
    --cap-add=SETGID \
    --cap-add=SETUID \
    --cap-add=NET_BIND_SERVICE \
    --security-opt=no-new-privileges:true \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=1g \
    --tmpfs /run:rw,noexec,nosuid \
    -v docker-vscode-server:/home/agent/.vscode-server \
    # ... other volume mounts
    docker-sandbox-dotnet-wasm:latest
```

#### devcontainer.json security additions
```json
{
  "runArgs": [
    "--cap-drop=ALL",
    "--cap-add=CHOWN",
    "--cap-add=DAC_OVERRIDE",
    "--cap-add=FOWNER",
    "--cap-add=SETGID",
    "--cap-add=SETUID",
    "--cap-add=NET_BIND_SERVICE",
    "--security-opt=no-new-privileges:true"
  ]
}
```

### Capabilities Explanation

| Capability | Why Needed |
|------------|------------|
| CHOWN | VS Code/npm may need to change file ownership |
| DAC_OVERRIDE | Access files regardless of permission bits |
| FOWNER | Set file ownership |
| SETGID/SETUID | Run processes as different user (for Podman rootless) |
| NET_BIND_SERVICE | Bind to privileged ports (5000, 5001) |

### What's NOT Included

- `--privileged`: Never use
- `SYS_ADMIN`: Not needed (Podman handles namespaces differently)
- Docker socket mount: Explicitly forbidden
- Host network: Use bridge network

### Seccomp Consideration

For maximum compatibility, use Docker's default seccomp profile. Only create custom profile if specific syscalls cause issues.

### Reference

- OWASP Docker Security: https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html
- Docker seccomp: https://docs.docker.com/engine/security/seccomp/
- Container capabilities: https://man7.org/linux/man-pages/man7/capabilities.7.html
## Acceptance
- [ ] run.sh includes `--cap-drop=ALL` flag
- [ ] run.sh adds only required capabilities (CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID, NET_BIND_SERVICE)
- [ ] run.sh includes `--security-opt=no-new-privileges:true`
- [ ] devcontainer.json includes security runArgs
- [ ] Container starts successfully with security restrictions
- [ ] VS Code devcontainer works with security restrictions
- [ ] Podman rootless still works with security restrictions
- [ ] .NET builds succeed with security restrictions
- [ ] No `--privileged` flag anywhere in scripts
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
