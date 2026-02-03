# fn-49-devcontainer-integration.4 Integrate into cai setup workflow

## Description

Extend `cai setup` to install cai-docker wrapper and VS Code extension. **Reuse existing containai-docker context logic** - do not create new context setup.

### Changes to cai setup

Add new setup steps after sysbox installation:

1. **Install cai-docker wrapper**
   - Copy to `~/.local/bin/cai-docker`
   - Make executable
   - Ensure `~/.local/bin` in PATH

2. **Reuse existing containai-docker context** (DO NOT create new context setup)
   - The context is already created by existing `_cai_setup_containai_docker_context()`
   - Platform-specific endpoints: WSL2 SSH bridge, macOS/Lima, native Linux
   - Use existing `_cai_auto_repair_containai_context()` for repairs
   - The wrapper enforces `--runtime=sysbox-runc` at launch time

3. **Setup SSH config Include directive**
   - Ensure `~/.ssh/containai.d/` directory exists
   - Ensure `Include containai.d/*` is in `~/.ssh/config`
   - Reuse existing `_cai_setup_ssh_config` patterns

4. **Install VS Code extension**
   - Check if VS Code installed
   - Install via `code --install-extension`
   - Also install for code-insiders if present

5. **Update doctor checks**
   - Check cai-docker wrapper exists and is executable
   - Check containai-docker context exists (using existing checks)
   - Check VS Code extension installed (if VS Code present)
   - Check `~/.ssh/containai.d/` exists with Include

### Important: Reuse Existing Infrastructure

Do NOT duplicate context creation logic. The existing codebase has:
- `_cai_setup_containai_docker_context()` - creates context with platform-specific endpoints
- `_cai_auto_repair_containai_context()` - repairs broken contexts
- `_cai_expected_docker_host()` - returns expected host for platform
- `_cai_setup_ssh_config()` - SSH config management

The devcontainer wrapper just needs to:
1. Use the existing context
2. Add `--runtime=sysbox-runc` at launch time

### New Library

`src/lib/devcontainer.sh`:
- `_cai_install_docker_wrapper()` - install cai-docker
- `_cai_install_vscode_extension()` - install extension
- `_cai_doctor_devcontainer()` - check devcontainer components

### User Flow

```
$ cai setup

[existing steps...]

Setting up devcontainer support...
  ✓ cai-docker wrapper installed
  ✓ containai-docker context verified (existing)
  ✓ SSH containai.d directory configured
  ✓ VS Code extension installed

Done! You can now use ContainAI with devcontainers.
```

## Acceptance

- [ ] cai-docker wrapper installed to ~/.local/bin
- [ ] Reuses existing containai-docker context (no new context creation)
- [ ] SSH Include directive set up for ~/.ssh/containai.d/
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
