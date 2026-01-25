# fn-17-axl.9 Manifest-driven generators and build integration

## Description

Create generators that read `src/sync-manifest.toml` (created in fn-17-axl.1) and produce Dockerfile fragments and init script content.

**Note:** The manifest was already created in fn-17-axl.1. This task implements the generators and build integration.

**Manifest flags (extended from fn-17-axl.1):**
- `f` = file
- `d` = directory
- `j` = json-init (create {} if empty)
- `s` = secret (600/700 permissions)
- `m` = mirror mode (--delete)
- `x` = exclude .system/
- `g` = git-filter (strip credential.helper)
- `R` = **remove existing path first** (rm -rf before ln -sfn)

**CRITICAL: The R flag**
When creating symlinks in the container, if the destination already exists as a directory, `ln -sfn` will create a nested symlink inside it rather than replacing it. This breaks persistence.

Current code handles this with explicit `rm -rf` before `ln -sfn` (e.g., `Dockerfile.agents:104`):
```dockerfile
rm -rf /home/agent/.copilot/skills && \
ln -sfn /mnt/agent-data/copilot/skills /home/agent/.copilot/skills
```

**Generator must emit safe commands:**
```bash
# For entries with R flag:
rm -rf /home/agent/.copilot/skills
ln -sfn /mnt/agent-data/copilot/skills /home/agent/.copilot/skills

# For entries without R flag (file symlinks):
ln -sfn /mnt/agent-data/copilot/config.json /home/agent/.copilot/config.json
```

**Generators to create:**
1. `src/scripts/gen-dockerfile-symlinks.sh` → outputs Dockerfile RUN commands
2. `src/scripts/gen-init-dirs.sh` → outputs directory creation commands
3. `src/scripts/gen-container-link-spec.sh` → outputs JSON link spec

**Generated files (NOT tracked in git):**
- `src/container/generated/symlinks.dockerfile`
- `src/container/generated/init-dirs.sh`
- `src/container/generated/link-spec.json`

**Build integration:**
1. `src/build.sh` runs generators before Docker build
2. Generated files placed in `src/container/generated/` (gitignored)
3. Dockerfiles updated to include generated content
4. containai-init.sh updated to source generated dirs script

**Audit task:** Review all existing `rm -rf` + `ln -sfn` pairs in Dockerfile.agents, ensure each has R flag in manifest.

## Acceptance

- [ ] Manifest supports `R` flag for "remove before link"
- [ ] Audited all Dockerfile.agents rm -rf cases, mapped to R flag
- [ ] gen-dockerfile-symlinks.sh emits rm -rf for R-flagged entries
- [ ] gen-dockerfile-symlinks.sh emits just ln -sfn for non-R entries
- [ ] gen-init-dirs.sh reads manifest, outputs shell commands
- [ ] gen-container-link-spec.sh reads manifest, outputs JSON
- [ ] Generated files in `src/container/generated/` (gitignored)
- [ ] `src/build.sh` runs generators before Docker build
- [ ] Dockerfile includes generated symlinks
- [ ] link-spec.json shipped into container image
- [ ] Build fails on stale generated files
- [ ] link-repair.sh respects R flag for safe recreation

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
