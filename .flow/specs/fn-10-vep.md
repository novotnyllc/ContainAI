# fn-10-vep: Sysbox-Only Sandbox Runtime (Docker Desktop Independence)

## Overview

**Architectural Pivot**: Remove all Docker Desktop/ECI dependency. ContainAI will always use our own Sysbox installation and provide sandbox-equivalent security features ourselves.

**Value Proposition**: Users get Docker Desktop sandbox-like isolation WITHOUT requiring Docker Desktop Business subscription.

## Problem Statement

- Docker Desktop Business subscription required for sandbox/ECI features
- Users want isolation without enterprise licensing costs
- Lima socket issue: "socket exists but docker info failed"

## Scope

### Phase 1: Remove ECI Dependency
- Remove `docker sandbox run` code path from lib/container.sh
- Remove ECI detection logic (lib/eci.sh deprecated)
- Update `_cai_select_context()` to always prefer Sysbox context
- Update `cai doctor` to not require Docker Desktop
- Remove/deprecate `cai sandbox` subcommands
- Update all docs and tests

**Acceptance**:
- [ ] `docker sandbox run` code path removed
- [ ] Context selection prefers Sysbox unconditionally
- [ ] ECI-specific flags removed
- [ ] `cai run` works without Docker Desktop
- [ ] `cai sandbox` deprecated
- [ ] All docs updated
- [ ] Tests updated

### Phase 2: Sysbox Installation & Configuration
- Automated Sysbox installation in `cai setup`
- Configure daemon.json with `sysbox-runc` runtime
- Keep `runc` as default runtime

**Acceptance**:
- [ ] `cai setup` installs Sysbox
- [ ] daemon.json configured
- [ ] runc remains default
- [ ] `cai doctor` verifies Sysbox

### Phase 3: Security Hardening
- Rely on Docker's default MaskedPaths/ReadonlyPaths
- Never pass `--security-opt systempaths=unconfined`
- Defer aggressive cap-drop and NNP (future work)

**Acceptance**:
- [ ] Docker defaults relied upon
- [ ] NO `systempaths=unconfined`
- [ ] Validation via mount metadata
- [ ] NNP and cap-drop deferred

### Phase 4: Workspace UID/GID Mapping
- Sysbox with kernel 5.12+ uses ID-mapped mounts automatically
- Keep existing mount path `/home/agent/workspace`
- Pass original path via `CAI_HOST_WORKSPACE` env var
- Entrypoint workspace logic is NON-FATAL

**Acceptance**:
- [ ] Workspace at `/home/agent/workspace`
- [ ] `CAI_HOST_WORKSPACE` env var used
- [ ] Entrypoint NON-FATAL
- [ ] Kernel check skipped on macOS

### Phase 5: Lima VM Fixes
- Fix docker group membership in provision script
- Add repair path for existing VMs
- Enhanced diagnostics

**Acceptance**:
- [ ] Docker group fixed
- [ ] Existing VM repair works
- [ ] Failure mode diagnostics

### Phase 6: Git Configuration
- Import git user.name and user.email
- Entrypoint creates symlink (not copy)

**Acceptance**:
- [ ] Git config imported
- [ ] Symlink in entrypoint
- [ ] Updates visible immediately

### Phase 7: Container Persistence (Sandbox-Like)

**Container lifecycle model**:
- Container runs detached with PID 1 as `sleep infinity`
- Agent sessions always use `docker exec`
- Container stays running between sessions

**Container naming** (includes full image reference):
- Name incorporates workspace path AND **full image reference** (repo+tag)
- Formula: `containai-$(hash "$workspace_path:$full_image_ref")`

**Environment variable handling**:

**Key change**: Disable entrypoint `.env` loading for Sysbox containers. All `.env` handling moves to exec-time.

Rationale:
- Entrypoint runs once at container creation (PID 1 = sleep infinity)
- With exec-based model, entrypoint env vars don't propagate to exec sessions
- Moving `.env` to exec-time makes updates take effect immediately and allows removals

**Implementation**:
- Add env var `CAI_SKIP_ENV_LOAD=1` at container creation
- Entrypoint checks this and skips `_load_env_file()` when set
- All `.env` loading happens at `docker exec` time via CLI

**Precedence** (session flags win):
1. `--env` flags (session-only, highest priority)
2. `/mnt/agent-data/.env` (persistent, lower priority)

**Parser** (mirrors entrypoint exactly, populates array by reference):
```bash
# Mirror src/entrypoint.sh:_load_env_file parsing rules exactly
# Populates array by reference to avoid NUL truncation in command substitution
_cai_parse_env_file() {
  local env_content="$1"
  local -n _out_array="$2"  # nameref to output array
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip CRLF line endings (Windows .env files)
    line="${line%$'\r'}"
    
    # Skip empty lines and whitespace-only lines (matches entrypoint)
    [[ -z "${line// /}" ]] && continue
    
    # Skip comments (matches entrypoint)
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Strip 'export' with optional whitespace (matches entrypoint)
    if [[ "$line" =~ ^export[[:space:]]+ ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"
    fi
    
    # Validate KEY=VALUE format (matches entrypoint)
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      local key="${line%%=*}"
      local value="${line#*=}"
      # Session env takes precedence - only add if not in session
      if [[ -z "${_session_env[$key]:-}" ]]; then
        _out_array+=(-e "$key=$value")
      fi
    fi
  done <<< "$env_content"
}
```

**CLI and container selection**:

When multiple containers exist for same workspace (different images):
- `cai run` and `cai shell` require `--agent` or `--image-tag` to disambiguate
- Error if multiple containers match and no agent/image specified:
  "Multiple containers exist for this workspace. Specify --agent or --image-tag."
- `--agent` maps to image via config (e.g., `--agent claude` → `ghcr.io/containai/claude:latest`)

**CLI modes**:

| CLI Flag | Execution | .env Applied? |
|----------|-----------|---------------|
| `cai run <ws>` | `docker exec -it <ctr> <agent>` | Yes |
| `cai run <ws> -- <cmd>` | `docker exec -it <ctr> <cmd> <args...>` | Yes |
| `cai run --shell <ws>` | `docker exec -it <ctr> bash` | Yes |
| `cai run --detached <ws> -- <cmd>` | `docker exec -d <ctr> <cmd>` | Yes |
| `cai shell <ws>` | `docker exec -it <ctr> bash` | Yes |
| `cai shell --agent claude <ws>` | Select container for claude agent | Yes |
| `cai shell --fresh <ws>` | Recreate container then bash | Yes |

**Container recreation triggers** (require `--fresh` or error):
- `--data-volume` mismatch (via label)
- `--volume` mismatch (via label)
- Image mismatch (automatic - different hash)

**Volume mismatch detection**:
```bash
# Store mounts as label at creation
extra_mounts_label=$(printf '%s\n' "${extra_mounts[@]}" | sort | tr '\n' '|')
--label "containai.mounts=$extra_mounts_label"

# Compare at reuse time
existing_mounts=$(docker inspect -f '{{index .Config.Labels "containai.mounts"}}' "$container")
if [[ "$existing_mounts" != "$requested_mounts" ]]; then
  _cai_error "Container exists with different mounts. Use --fresh to recreate."
  return 1
fi
```

**`--name` flag is DEPRECATED**

**Acceptance**:
- [ ] Detached with `sleep infinity`
- [ ] `docker exec` for all sessions
- [ ] NO `--rm` flag
- [ ] Default command is configured agent
- [ ] Container name includes full image reference (repo+tag)
- [ ] `--data-volume` mismatch errors without `--fresh`
- [ ] `--volume` mismatch errors without `--fresh` (via labels)
- [ ] **Entrypoint `.env` loading disabled** (`CAI_SKIP_ENV_LOAD=1`)
- [ ] **All `.env` loading at exec-time**
- [ ] **`.env` removals take effect** (no stale entrypoint env)
- [ ] `--env` has precedence over .env
- [ ] Parser mirrors entrypoint exactly (CRLF, whitespace-only lines)
- [ ] Parser uses nameref to avoid NUL truncation
- [ ] All CLI modes apply .env consistently
- [ ] **`cai shell` accepts `--agent`/`--image-tag`**
- [ ] **`cai shell` accepts `--fresh`**
- [ ] **Error if multiple containers for workspace without agent specified**
- [ ] Arguments passed with proper quoting
- [ ] `--name` deprecated with warning
- [ ] Portable hashing works
- [ ] `--fresh` recreates container
- [ ] Docker context passed to all container queries

### Phase 8: DinD Support
- dockerd auto-start inside Sysbox container
- Inner containers use runc

**Acceptance**:
- [ ] dockerd starts in Sysbox
- [ ] Inner containers use runc
- [ ] DinD verification test passes

### Phase 9: Distribution & Updates
- GHCR publishing
- install.sh script
- cai update command

**Acceptance**:
- [ ] GHCR images published
- [ ] install.sh works Linux/macOS
- [ ] `cai update` works

### Out of Scope
- Docker Desktop ECI support
- Windows native (WSL2 only)
- Aggressive capability dropping (future)
- `cai stop --remove` command
- Hot-reload of config without `--fresh`

## Technical Details

### Container Naming

```bash
_cai_container_name() {
  local workspace="$1"
  local image_ref="$2"  # Full: ghcr.io/containai/claude:latest
  local normalized hash_input
  normalized=$(cd "$workspace" 2>/dev/null && pwd -P || printf '%s' "$workspace")
  hash_input="${normalized}:${image_ref}"
  
  if command -v shasum >/dev/null 2>&1; then
    printf 'containai-%s' "$(printf '%s' "$hash_input" | shasum -a 256 | cut -c1-12)"
  elif command -v sha256sum >/dev/null 2>&1; then
    printf 'containai-%s' "$(printf '%s' "$hash_input" | sha256sum | cut -c1-12)"
  else
    printf 'containai-%s' "$(printf '%s' "$hash_input" | openssl dgst -sha256 | awk '{print substr($NF,1,12)}')"
  fi
}
```

### Container Creation

```bash
docker run -d \
  --runtime=sysbox-runc \
  -e CAI_HOST_WORKSPACE="$workspace_resolved" \
  -e CAI_SKIP_ENV_LOAD=1 \
  -v "$workspace_resolved:/home/agent/workspace:rw" \
  -v "$data_volume:/mnt/agent-data:rw" \
  "${extra_mount_args[@]}" \
  -w /home/agent/workspace \
  --label "containai.workspace=$workspace_resolved" \
  --label "containai.image=$image_ref" \
  --label "containai.data-volume=$data_volume" \
  --label "containai.mounts=$extra_mounts_label" \
  --name "$(_cai_container_name "$workspace_resolved" "$image_ref")" \
  "$image_ref" \
  sleep infinity
```

### Entrypoint Update

```bash
# In src/entrypoint.sh
# Skip .env loading for Sysbox exec-based model
if [[ "${CAI_SKIP_ENV_LOAD:-}" != "1" ]]; then
  _load_env_file
fi
```

### Agent Execution

```bash
_cai_exec_agent() {
  local container="$1"
  shift
  local -a cmd_args=("$@")
  
  # Build env args: session first (they have priority)
  local -a env_args=()
  for key in "${!_session_env[@]}"; do
    env_args+=(-e "$key=${_session_env[$key]}")
  done
  
  # Add persistent env via nameref (avoids NUL truncation)
  local env_file
  env_file=$(docker exec "$container" cat /mnt/agent-data/.env 2>/dev/null || true)
  _cai_parse_env_file "$env_file" env_args
  
  docker exec -it "${env_args[@]}" "$container" "${cmd_args[@]}"
}
```

### Multi-Container Selection

```bash
_cai_find_container() {
  local workspace="$1"
  local agent="${2:-}"  # Optional: specific agent
  local context="${_selected_context:-}"  # Docker context to use
  
  local normalized
  normalized=$(cd "$workspace" 2>/dev/null && pwd -P || printf '%s' "$workspace")
  
  # Build context args if set
  local -a ctx_args=()
  [[ -n "$context" ]] && ctx_args=(--context "$context")
  
  # If agent specified, resolve directly by container name (most efficient)
  if [[ -n "$agent" ]]; then
    local image_ref
    image_ref=$(_cai_resolve_agent_image "$agent")
    local target_name
    target_name=$(_cai_container_name "$normalized" "$image_ref")
    
    if docker "${ctx_args[@]}" ps -aq --filter "name=^${target_name}$" | grep -q .; then
      echo "$target_name"
      return 0
    else
      return 1  # No container for this agent
    fi
  fi
  
  # No agent specified - find all containers for this workspace
  local containers
  containers=$(docker "${ctx_args[@]}" ps -aq --filter "label=containai.workspace=$normalized")
  
  local count
  count=$(echo "$containers" | grep -c . || echo 0)
  
  if [[ "$count" -eq 0 ]]; then
    return 1  # No container
  elif [[ "$count" -eq 1 ]]; then
    echo "$containers"
    return 0
  else
    # Multiple containers - need agent to disambiguate
    _cai_error "Multiple containers exist for this workspace. Specify --agent or --image-tag."
    return 1
  fi
}
```

## Quick Commands

```bash
cai setup
cai doctor
cai run /path/to/workspace  # Launches agent with .env applied
cai run --shell /path/to/workspace  # Bash with .env applied
cai run --env DEBUG=1 /path/to/workspace  # DEBUG=1 overrides .env
cai run --fresh /path/to/workspace  # Recreate container
cai shell --agent claude /path/to/workspace  # Select specific agent container
cai shell --fresh /path/to/workspace  # Recreate container then bash
```

## Migration Notes

- New lifecycle model (sleep infinity + exec)
- Different agent/image → different container
- `.env` changes take effect immediately
- Session `--env` always overrides persistent `.env`
- Entrypoint no longer loads `.env` (exec-time loading only)

## Future Enhancements (Out of Scope)

- Entrypoint restructure for NNP
- Aggressive capability dropping
- `cai stop --remove` command
