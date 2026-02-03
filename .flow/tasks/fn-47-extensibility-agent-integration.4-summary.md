# Task fn-47-extensibility-agent-integration.4 Summary

## What was implemented

Added runtime mount support for template hooks and network configuration files. When a container is created, ContainAI now automatically mounts:

1. **Template hooks directory**: `~/.config/containai/templates/<name>/hooks/` → `/etc/containai/template-hooks:ro`
2. **Template network.conf**: `~/.config/containai/templates/<name>/network.conf` → `/etc/containai/template-network.conf:ro`

This enables fast iteration - users can modify hooks or network config and just restart the container, no rebuild needed.

## Files changed

1. **`src/lib/container.sh`** (lines 2666-2689): Added mount logic in `_containai_start_container()` to check for template hooks directory and network.conf file, mounting them read-only if present. The logic is decoupled from template building - even `--image-tag` mode (without template build) will check for default template hooks/network.conf.

2. **`src/templates/default.Dockerfile`**: Added directory creation (`mkdir -p /etc/containai/template-hooks/startup.d`) so the mount point exists. Updated USER warning to clarify that temporary `USER root` is allowed.

3. **`src/templates/example-ml.Dockerfile`**: Added same directory creation for consistency. Updated USER warning to match default.Dockerfile.

4. **`docs/configuration.md`**: Added comprehensive documentation for:
   - Startup hooks (template-level and workspace-level)
   - Hook execution order and naming conventions
   - Network policy file mounting
   - Clarified that `--image-tag` bypasses template Dockerfile build but still mounts default template hooks/network.conf

## Key design decisions

- **Read-only mounts**: Both hooks and network.conf are mounted `:ro` for security
- **Conditional mounting**: Only mounts if the files/directories exist - missing paths don't cause errors
- **Template path resolution**: Correctly builds `${templates_root}/${template_name}` path
- **Decoupled from template build**: The `--image-tag` flow (no template build) still checks default template for hooks/network.conf, per spec requirement
- **Works with all flows**: Handles default templates, custom `--template`, and `--image-tag` flow

## Integration with existing code

- The `containai-init.sh` already runs hooks from both `/etc/containai/template-hooks/startup.d/` and `/home/agent/workspace/.containai/hooks/startup.d/` (from Task 2)
- Network policy code already checks for template network.conf (from Task 3)
- This task adds the runtime mount that makes those paths available in the container

## Review feedback addressed

- Fixed: `--image-tag` mode now checks default template for hooks/network.conf (was incorrectly gated on `use_template`)
- Fixed: Documentation updated to clarify `--image-tag` vs template behavior
- Fixed: Dockerfile USER warning updated to clarify temporary `USER root` is allowed
