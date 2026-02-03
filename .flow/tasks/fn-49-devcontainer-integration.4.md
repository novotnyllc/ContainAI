# fn-49-devcontainer-integration.4 Integrate into cai setup workflow

## Description

Extend `cai setup` to install cai-docker wrapper and VS Code extension, and configure the containai-docker context.

### Changes to cai setup

Add new setup steps after sysbox installation:

1. **Install cai-docker wrapper**
   - Copy to `~/.local/bin/cai-docker`
   - Make executable
   - Ensure `~/.local/bin` in PATH

2. **Create containai-docker context** (if not exists)
   - `docker context create containai-docker --docker "host=unix:///var/run/docker.sock"`
   - Configure to use sysbox-runc as default runtime

3. **Install VS Code extension**
   - Check if VS Code installed
   - Install via `code --install-extension`
   - Also install for code-insiders if present

4. **Update doctor checks**
   - Check cai-docker wrapper exists and is executable
   - Check containai-docker context exists
   - Check VS Code extension installed (if VS Code present)

### New Library

`src/lib/devcontainer.sh`:
- `_cai_install_docker_wrapper()` - install cai-docker
- `_cai_setup_devcontainer_context()` - create/verify context
- `_cai_install_vscode_extension()` - install extension
- `_cai_doctor_devcontainer()` - check devcontainer components

### User Flow

```
$ cai setup

[existing steps...]

Setting up devcontainer support...
  ✓ cai-docker wrapper installed
  ✓ containai-docker context created
  ✓ VS Code extension installed

Done! You can now use ContainAI with devcontainers.
```

## Acceptance

- [ ] cai-docker wrapper installed to ~/.local/bin
- [ ] containai-docker context created with sysbox runtime
- [ ] VS Code extension installed (if VS Code present)
- [ ] Doctor checks for devcontainer components
- [ ] Clear error messages if setup fails
- [ ] Idempotent (can run multiple times safely)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
