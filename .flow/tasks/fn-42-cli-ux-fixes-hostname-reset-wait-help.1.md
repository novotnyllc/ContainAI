# fn-42-cli-ux-fixes-hostname-reset-wait-help.1 Add container hostname flag to docker run

## Description
Redesign container naming to `{repo}-{branch_leaf}` (max 24 chars). Branch uses last segment of `/` path; on conflict, include parent segment.

**Size:** M
**Files:** `src/lib/container.sh`

## Approach

1. Modify `_containai_container_name()` at line 313:

   **Branch leaf extraction:**
   ```bash
   # feature/oauth → oauth
   # feat/ui/button → button
   branch_leaf="${branch_name##*/}"
   branch_parent="${branch_name%/*}"
   [[ "$branch_parent" == "$branch_name" ]] && branch_parent=""
   ```

2. **Collision detection** (in `_cai_resolve_container_name`):
   ```bash
   candidate="${repo_s}-${branch_leaf}"
   if container_exists_for_different_workspace "$candidate"; then
       # Include parent: feature/oauth → feature-oauth
       if [[ -n "$branch_parent" ]]; then
           parent_leaf="${branch_parent##*/}"
           candidate="${repo_s}-${parent_leaf}-${branch_leaf}"
       fi
   fi
   ```

3. **Truncation** to fit 24 chars:
   - Repo up to 16 chars
   - Branch gets remainder (at least 4)
   - Trim from end of each segment

4. Add hostname at line 2306:
   ```bash
   args+=(--hostname "$container_name")
   ```

## Key context

- Current naming at `src/lib/container.sh:313-391`
- Collision check needs to query existing containers
- Must preserve legacy lookup for migration
## Approach

1. Modify `_containai_container_name()` at line 313:
   ```bash
   # Sanitize
   repo_s="${repo_name,,}"  # lowercase
   repo_s=$(printf '%s' "$repo_s" | tr -cd 'a-z0-9-')
   branch_s="${branch_name,,}"
   branch_s=$(printf '%s' "$branch_s" | tr -cd 'a-z0-9-')

   # Truncate to fit 16 chars total
   # Budget: 16 - 1 (dash) = 15 for repo+branch
   # Give repo up to 12, branch at least 3
   repo_s="${repo_s:0:12}"
   local remaining=$((15 - ${#repo_s}))
   branch_s="${branch_s:0:$remaining}"

   name="${repo_s}-${branch_s}"
   ```

2. Update `_cai_resolve_container_name()` for collision handling:
   - If `{repo}-{branch}` exists for different workspace, try `{repo}-{bran}-2`, `-3`, etc.

3. Add hostname at line 2306:
   ```bash
   args+=(--hostname "$container_name")
   ```

## Key context

- Current naming at `src/lib/container.sh:313-391`
- Must preserve legacy lookup for migration
- Collision counter goes after truncated name, still within 16 chars
## Approach

1. Modify `_containai_container_name()` at line 313:
   - Extract first 4 chars of sanitized repo name
   - Generate 4-char hash from `{workspace_path}:{branch}`
   - Format: `cai-{repo4}-{hash4}`

2. Hash function (use existing `_cai_hash_path` or similar):
   ```bash
   # Example: use sha256 and take first 4 chars
   local hash_input="${workspace_path}:${branch_name}"
   local hash4=$(printf '%s' "$hash_input" | sha256sum | cut -c1-4)
   ```

3. Update `_cai_resolve_container_name()` at line 635:
   - Keep legacy name lookup for migration
   - New containers get short names

4. Add `--hostname` flag at line 2306:
   ```bash
   args+=(--hostname "$container_name")
   ```

## Key context

- Current naming at `src/lib/container.sh:313-391`
- Container creation at `src/lib/container.sh:2306`
- Must preserve legacy lookup for existing containers
- Memory convention: "Printf over echo" for shell logging
## Approach

1. Find container creation at `src/lib/container.sh:2299-2306` (Sysbox mode)
2. Add hostname flag after the `--name` flag:
   ```bash
   local hostname="${container_name:0:63}"  # Max 63 chars for hostname
   args+=(--hostname "$hostname")
   ```
3. Also check non-Sysbox paths if they exist

## Key context

- Hostnames limited to 63 characters (RFC 1123)
- Container names can be longer; truncate if needed
- Pattern at line 2306: `args+=(--name "$container_name")`
## Acceptance
- [ ] Max 24 chars
- [ ] Format: `{repo}-{branch_leaf}`
- [ ] Branch leaf = last segment after `/`
- [ ] Conflict → include parent segment (e.g., `feature-oauth`)
- [ ] Final fallback: `-2`, `-3` counter
- [ ] Hostname flag added to docker run
- [ ] Legacy long names still discoverable
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
