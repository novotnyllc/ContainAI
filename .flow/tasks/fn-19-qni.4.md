# fn-19-qni.4 Add --reset flag and clarify run semantics

## Description
Clarify `cai run` vs `cai shell` semantics for multi-agent use and add `--reset` flag to wipe data volume. Currently `--fresh` recreates the container but keeps the data volume (correct behavior). Add `--reset` for users who want a complete clean slate.

**Size:** S
**Files:** `src/containai.sh`, `src/lib/container.sh`, `src/README.md`

## Approach

### Semantic clarification

Document clearly:
- `cai run`: Ensure container exists and is running. Optionally launch agent. One container per workspace.
- `cai shell`: Open interactive SSH shell to existing container.
- `--agent X`: Changes which agent runs in the workspace container (doesn't create separate container)

### --reset flag

Add `--reset` flag that:
1. Stops container
2. Removes container
3. **Removes data volume** (this is the difference from `--fresh`)
4. Creates fresh container with new volume

Require confirmation: `Are you sure you want to wipe all data for this workspace? [y/N]`
Or skip with `--yes` flag.

### Reuse points

- Follow `--fresh` implementation at `src/lib/container.sh:1051-1058` and `1510-1550`
- Use `_containai_ensure_volumes()` pattern for volume recreation
- Follow `_cai_uninstall_volumes_from_array()` pattern for volume removal at `src/lib/uninstall.sh:380-432`
## Acceptance
- [ ] `cai run --reset` wipes data volume and recreates container
- [ ] `cai run --reset` prompts for confirmation (unless `--yes`)
- [ ] `cai run --fresh` behavior unchanged (keeps volume)
- [ ] `src/README.md` documents run vs shell semantics clearly
- [ ] `src/README.md` documents --fresh vs --reset distinction
- [ ] `--agent` flag documented as changing agent, not creating new container
- [ ] Passes `shellcheck -x src/containai.sh src/lib/container.sh`
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
