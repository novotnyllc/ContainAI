# Task fn-51.8: Update documentation for per-agent manifest structure

**Status:** pending
**Depends on:** fn-51.5, fn-51.6, fn-51.7

## Objective

Update all documentation to reflect per-agent manifest structure.

## Files to Update

1. **docs/adding-agents.md** - Contributor guide (for adding built-in agents)
   - Update directory structure diagram
   - Change workflow to create per-agent file
   - Document `[agent]` section format
   - Update examples to show file-based approach
   - Remove references to editing monolithic manifest

2. **docs/custom-tools.md** - NEW: User guide for adding custom tools
   - When to create a manifest vs just use `additional_paths`
   - Step-by-step: "I installed tool X, now what?"
   - Complete examples for common scenarios
   - Troubleshooting section

3. **docs/sync-architecture.md** - Technical deep-dive
   - Document build-time vs runtime generation
   - Document user manifest processing in containai-init.sh

4. **AGENTS.md** - Quick reference
   - Update sync manifest path references
   - Note per-agent structure

5. **src/README.md** - Source layout
   - Document `src/manifests/` directory
   - List all manifest files

6. **docs/configuration.md** - User config
   - Link to custom-tools.md for manifest guide
   - Document user manifest location briefly

## Content to Add

### Per-Agent Manifest Format

```toml
# src/manifests/myagent.toml
# =============================================================================
# MY AGENT
# Description and docs link
# =============================================================================

[agent]
name = "myagent"
binary = "myagent"
default_args = ["--auto"]
optional = true

[[entries]]
source = ".myagent/config.json"
target = "myagent/config.json"
container_link = ".myagent/config.json"
flags = "fj"
```

### User Guide: Adding Custom Tools (docs/custom-tools.md)

Target audience: Users who installed a tool and want it to work in ContainAI.

**Structure:**

1. **Do I need a manifest?**
   - Just syncing config files? → Use `additional_paths` in containai.toml (simpler)
   - Need launch wrapper with default args? → Create a manifest
   - Decision flowchart

2. **Quick Start**
   ```bash
   # 1. Find where your tool stores config
   ls -la ~/.mytool/

   # 2. Create manifest
   cat > ~/.config/containai/manifests/mytool.toml << 'EOF'
   [agent]
   name = "mytool"
   binary = "mytool"
   default_args = ["--headless"]
   optional = true

   [[entries]]
   source = ".mytool/config.json"
   target = "mytool/config.json"
   container_link = ".mytool/config.json"
   flags = "fjo"
   EOF

   # 3. Start container - it just works
   cai run --fresh
   ```

3. **Common Scenarios**
   - Tool with single config file
   - Tool with config directory
   - Tool with credentials (use `s` flag)
   - Tool with cache dir (don't sync cache, only config)

4. **Reference**
   - All flags explained
   - `[agent]` section fields
   - Where files end up (host → volume → container symlink)

5. **Troubleshooting**
   - "Symlink not created" → check flags, check source exists
   - "Wrapper not working" → check binary name, check PATH
   - "Config not persisting" → check target path

## Acceptance Criteria

- [ ] All docs reference per-agent files, not monolithic manifest
- [ ] `[agent]` section documented
- [ ] **docs/custom-tools.md created** with user-friendly guide
- [ ] Decision flowchart: manifest vs additional_paths
- [ ] Common scenarios with copy-paste examples
- [ ] Examples updated in existing docs
- [ ] No stale references to old structure

## Notes

- Keep docs concise - don't over-document
- Link to sync-architecture.md for technical details
- Include practical examples users can copy

## Done summary
Updated all documentation to reflect per-agent manifest structure.
## Evidence
- Commits: dc18570, 478b01a, 3ff15d4
- Tests:
- PRs:
