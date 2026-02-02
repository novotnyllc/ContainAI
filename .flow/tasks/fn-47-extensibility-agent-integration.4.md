# fn-47-extensibility-agent-integration.4 Template Auto-Detection - Mount hooks and network config at runtime

## Description

Update container startup to automatically mount hook directories and network config from both template and workspace levels. Uses runtime mounts (Option B) for fast iteration - no rebuild needed for changes.

### Mount Sources

| Level | Source | Container Destination |
|-------|--------|----------------------|
| Template | `~/.config/containai/templates/<name>/hooks/` | `/etc/containai/template-hooks/` |
| Template | `~/.config/containai/templates/<name>/network.conf` | `/etc/containai/template-network.conf` |
| Workspace | `.containai/hooks/` | (accessed directly via workspace mount) |
| Workspace | `.containai/network.conf` | (accessed directly via workspace mount) |

### Why Runtime Mounts

- **Fast iteration**: Change hooks/config, restart container - no rebuild
- **Template reuse**: Same template image, different hooks per workspace
- **Clear separation**: Template provides base, workspace overrides

### Implementation

1. **`src/lib/container.sh`** - Add mount logic in `_containai_run_container()`:
   ```bash
   # Get current template name from config
   template_name=$(_cai_get_config "template" "default")
   template_dir="$HOME/.config/containai/templates/$template_name"

   # Mount template hooks if present
   if [[ -d "$template_dir/hooks" ]]; then
       EXTRA_MOUNTS+=("-v" "$template_dir/hooks:/etc/containai/template-hooks:ro")
   fi

   # Mount template network.conf if present
   if [[ -f "$template_dir/network.conf" ]]; then
       EXTRA_MOUNTS+=("-v" "$template_dir/network.conf:/etc/containai/template-network.conf:ro")
   fi

   # Workspace files accessed directly - no extra mount needed
   # (workspace already mounted at /home/agent/workspace)
   ```

2. **`src/container/containai-init.sh`** - Check both paths (from Task 2):
   - Template hooks: `/etc/containai/template-hooks/startup.d/`
   - Workspace hooks: `/home/agent/workspace/.containai/hooks/startup.d/`

3. **`src/templates/default.Dockerfile`** - Create directory structure:
   ```dockerfile
   RUN mkdir -p /etc/containai/template-hooks/startup.d
   ```

### User Workflow

**Template-level hooks (shared):**
```bash
# Create hooks in template directory
mkdir -p ~/.config/containai/templates/my-template/hooks/startup.d
cat > ~/.config/containai/templates/my-template/hooks/startup.d/10-common.sh << 'EOF'
#!/bin/bash
echo "Common setup for all projects using this template"
EOF
chmod +x ~/.config/containai/templates/my-template/hooks/startup.d/10-common.sh
```

**Workspace-level hooks (project-specific):**
```bash
# Create hooks in project
mkdir -p .containai/hooks/startup.d
cat > .containai/hooks/startup.d/30-project.sh << 'EOF'
#!/bin/bash
echo "Project-specific setup"
npm install
EOF
chmod +x .containai/hooks/startup.d/30-project.sh

# Run - hooks from both levels execute
cai run
```

## Acceptance

- [ ] Template hooks directory mounted to `/etc/containai/template-hooks/` when present
- [ ] Template network.conf mounted when present
- [ ] Workspace hooks accessible via existing workspace mount
- [ ] Mounts are read-only
- [ ] Missing directories don't cause errors
- [ ] Works with default and custom templates
- [ ] Template name resolved from config (default: "default")
- [ ] Documented in docs/configuration.md

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
