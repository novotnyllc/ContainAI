# fn-32-2mq.7 Implement cai --refresh command

## Description

Add `cai --refresh` (or `cai refresh`) command to pull latest base image and optionally rebuild the user's template image, using the correct Docker context.

**Command Behavior:**
```bash
cai --refresh [--rebuild]
```

**Docker Context:**
The refresh command must use the same Docker context selection logic as container creation. The selected context must be passed explicitly to all docker operations:
1. `_cai_select_context` to determine context (same as container creation)
2. Pass context to `docker pull`: `docker --context "$context" pull "$base_image"`
3. Pass context to `_cai_build_template`: `_cai_build_template "default" "$context"`

The `_cai_build_template` function already accepts `docker_context` as its second argument.

**Flow:**
1. Select Docker context: `context=$(_cai_select_context)` (same as container creation)
2. Determine base image from channel config:
   - stable: `ghcr.io/novotnyllc/containai:latest`
   - nightly: `ghcr.io/novotnyllc/containai:nightly`
3. Pull the base image with context: `docker --context "$context" pull "$base_image"`
4. Show what changed (before/after version):
```
[INFO] Refreshing ContainAI base image...
       Channel: stable
       Pulling: ghcr.io/novotnyllc/containai:latest
[OK] Updated from 0.1.0 to 0.2.0
```
5. If `--rebuild` flag passed, rebuild template image:
   - Always rebuilds the `default` template
   - Call: `_cai_build_template "default" "$context"`
   - Template located at `~/.config/containai/templates/default/Dockerfile`
   - Show result
6. Without `--rebuild`, remind user if template exists:
```
[INFO] Template image may need rebuild. Run 'cai --refresh --rebuild' to update.
```
7. Clear registry cache for refreshed image

**Template Selection:**
- `--rebuild` always rebuilds the `default` template
- Future enhancement: `--rebuild --template <name>` for named templates (out of scope for this task)
- If no default template exists, skip rebuild step with info message

**Implementation Location:**
- Add to `src/containai.sh` command dispatch
- Create handler in `src/lib/update.sh` or add to existing update module

**Edge Cases:**
- No template configured: just pull base, skip rebuild step
- Template uses hardcoded FROM: warn and suggest `cai template upgrade`
- Network failure: exit with error (refresh is explicit action, should fail loudly)

## Acceptance

- [ ] `cai --refresh` command exists and is documented in help
- [ ] Calls `_cai_select_context` to determine Docker context
- [ ] Docker pull uses selected context: `docker --context "$context" pull`
- [ ] Passes context to `_cai_build_template`: `_cai_build_template "default" "$context"`
- [ ] Pulls base image for configured channel (stable or nightly)
- [ ] Shows before/after version on successful pull
- [ ] `--rebuild` flag triggers default template image rebuild
- [ ] Correctly locates default template in `~/.config/containai/templates/default/`
- [ ] Without `--rebuild`, reminds user about template rebuild if template exists
- [ ] Skips rebuild with info message if no default template exists
- [ ] Warns if template has hardcoded FROM (suggests `cai template upgrade`)
- [ ] Network failure exits with error (non-zero exit code)
- [ ] Works correctly for both stable and nightly channels
- [ ] Clears registry cache for refreshed image after pull

## Done summary
Implemented `cai --refresh` (and `cai refresh`) command to pull the latest base image and optionally rebuild the default template, using the same Docker context selection as container creation.
## Evidence
- Commits: 2c160a8, 0cb78bc, 6adaaac
- Tests: shellcheck -x src/lib/update.sh src/containai.sh
- PRs:
