# fn-36-rb7 CLI UX Consistency & Workspace State

## Overview

Make the ContainAI CLI consistent, intuitive, and predictable. This epic consolidates UX improvements from fn-12-css, fn-18-g96, and fn-34-fk5, with a focus on:

1. **Consistent parameter semantics** - same flag means same thing everywhere (command-appropriate)
2. **Workspace state persistence** - remember settings, don't require re-specifying
3. **Better container naming** - human-readable, predictable names
4. **Shell completions** - everywhere, including for `cai docker`
5. **`cai exec`** - general command execution inside containers via SSH
6. **Nested workspace detection** - find parent workspace if exists

**Priority:** HIGH - Do this FIRST

## Scope

### In Scope
- Workspace state persistence in user config (always read regardless of repo config)
- Consistent `--container` semantics (command-appropriate: create for shell/run/exec, require-exists for stop/export/import)
- `--fresh` vs `--reset` clarification with safe volume handling
- Human-readable container naming (repo-branch format with fallbacks)
- `cai exec <command>` for general command execution inside containers
- Shell completion for all cai commands (bash/zsh) with fast startup
- `cai docker` passthrough with auto-injected `--context` (including `logs`, `exec`, etc.)
- `cai config` command for managing settings (workspace-aware, explicit layering)
- Nested workspace detection with parent container handling (config + labels)
- `cai setup` installs shell completion to `.bashrc.d/`

### Out of Scope
- Agent-specific execution (that's `cai run <agent>` in fn-34-fk5)
- Import reliability (fn-31-gib)
- User templates (fn-33-lp4) - NOTE: `template` key removed from workspace state
- Base image contract documentation (separate epic)

## Approach

### Design Principles

1. **Predictable**: Same inputs always produce same behavior
2. **Remembering**: Once you specify something, we remember it
3. **Intuitive**: Flag names match what they do
4. **Progressive disclosure**: Simple commands work simply, options add power

### Config Layering (CRITICAL)

Workspace state is stored in **user config** (`~/.config/containai/config.toml`) and is **always read** regardless of repo-local config presence.

**Precedence order (highest to lowest):**
1. CLI flags (`--container`, `--data-volume`, etc.)
2. Environment variables (`CONTAINAI_DATA_VOLUME`, etc.)
3. User workspace state (`~/.config/containai/config.toml` `[workspace."path"]` section)
4. Repo-local config (`.containai/config.toml` in workspace)
5. User global config (`~/.config/containai/config.toml` top-level settings)
6. Built-in defaults

**Implementation:**
- `_containai_find_config()` continues to find repo-local config for general settings
- NEW: `_containai_read_workspace_state()` always reads user config workspace section
- Workspace state and repo config are **merged**, not mutually exclusive
- Writes to workspace state always go to user config (never repo-local)

**TOML writing strategy:**
- Use `src/parse-toml.py` extended with `--set-workspace-key` mode for atomic updates
- Read existing config, modify workspace section, write to temp file, rename (atomic)
- Preserve comments and non-workspace sections
- Create config file with `0600` permissions, directory with `0700`
- Path normalization via `_cai_normalize_path` (not raw `realpath` - platform-aware)

### Workspace State Persistence

Store workspace settings in user config (`~/.config/containai/config.toml`):

```toml
# Auto-managed by cai commands
[workspace."/home/user/projects/myapp"]
data_volume = "myapp-agent-data"
container_name = "containai-myapp-main"
agent = "claude"
created_at = "2026-01-23T10:00:00Z"
```

**Note:** `template` key removed - templates are out of scope (fn-33-lp4).

**Behavior:**
- First time running `cai shell`, `cai run`, or `cai exec` in a workspace: auto-generate names, save to config
- Subsequent times: use saved settings
- `--data-volume`, `--container`, `--agent`: override AND save to config
- `--fresh`: recreate container using SAME saved settings (preserves volume)
- `--reset`: clear workspace config, remove container, generate NEW unique volume name (never fall back to shared default)

### Consistent Parameter Semantics

**`--container NAME`** - Target a specific container (command-appropriate behavior):

| Command | Container Exists | Container Missing |
|---------|------------------|-------------------|
| `shell` | Use it | Create it |
| `run` | Use it | Create it |
| `exec` | Use it | Create it |
| `import` | Use it | **Error**: "Container NAME not found" |
| `export` | Use it | **Error**: "Container NAME not found" |
| `stop` | Stop it | **Error**: "Container NAME not found" |

The flag **means** "I want this container identity" - but the **action** is command-appropriate.

**Migration from current behavior:**
- Current `cai run --container` requires container NOT exist (create-only)
- Current `cai shell --container` requires container exist (attach-only)
- **New unified behavior:** use-or-create for shell/run/exec
- **No `--name` alias needed** - the semantic shift is intentional
- **Help text update:** clearly document "uses existing or creates new"
- **Error messages:** guide users if they expected old behavior
- Scripts relying on "must not exist" behavior should use `docker inspect` check first

**`--data-volume NAME`** - Use specific data volume:
- If volume exists: use it
- If volume doesn't exist: create it
- Saved to workspace config after first use
- **If container already exists with different volume:** Error with guidance:
  ```
  [ERROR] Container myapp already uses volume 'old-volume'.
          Use --fresh to recreate with new volume, or remove container first.
  ```

**`--fresh`** - Recreate container:
- Stop and remove existing container
- Create new container with SAME saved settings (preserves data volume)
- Does NOT change workspace config
- Useful for: picking up image updates, fixing broken container state

**`--reset`** - Reset workspace to defaults:
- Stop and remove existing container
- Generate NEW unique volume name (`{repo}-{branch}-{timestamp}` format)
- **Write new state immediately** to workspace config (keep section, just reset values)
- **Never falls back to shared default volume** (prevents cross-workspace data mixing)
- Next command creates fresh container using the newly persisted volume name

**Note:** `--reset` does NOT remove the workspace section entirely - it clears and regenerates values. This ensures the new volume name is persisted before any command runs.

### Better Container Naming

**Format:** `containai-{repo}-{branch}`

Examples:
- `/home/user/projects/myapp` on `main` branch → `containai-myapp-main`
- `/home/user/work/frontend` on `feature/login` → `containai-frontend-feature-login`

**Rules:**
- **Repo name:** Directory name (last path component), sanitized
- **Branch name:** From `git rev-parse --abbrev-ref HEAD`, sanitized
- **Sanitization:** Replace `/` with `-`, remove non-alphanumeric except `-`, lowercase
- Max 63 chars total (Docker limit), with 4 chars reserved for collision suffix

**Edge cases:**
- Non-git directory: use `nogit` as branch → `containai-myapp-nogit`
- Detached HEAD: use short SHA → `containai-myapp-abc1234`
- Git worktree: resolve to actual branch of worktree
- Empty/failed git lookup: fall back to `nogit`

**Truncation:**
- If `containai-{repo}-{branch}` > 59 chars, truncate from end
- Reserve 4 chars for collision suffix (`-NN`)
- Final name max 63 chars

**Architecture (separation of concerns):**
- `_containai_container_name(path)` - **pure function**, returns base name only (no docker calls)
- `_cai_resolve_container_name(path, context)` - handles collision detection via docker, returns final name
- This keeps naming logic testable and avoids tight coupling with docker

**Collision handling (in `_cai_resolve_container_name`):**
- Check if name exists with different workspace label
- If collision: append `-2`, `-3`, etc. up to `-99`
- Store final name in workspace config to avoid re-computation

**Lookup order:** (1) workspace config, (2) workspace label, (3) new format, (4) legacy hash format

### `cai exec` Command

General command execution **inside the container** via SSH:

```bash
# Run any command inside the container
cai exec ls -la
cai exec npm test
cai exec -- echo "hello world"  # Use -- to separate cai flags from command

# With options
cai exec --workspace /path/to/project npm install
cai exec --container my-project make build
```

**Key Features:**
- Auto-creates/starts container if needed (same as `cai shell`)
- Runs command via SSH with proper TTY handling (allocate PTY if stdin is TTY)
- Streams stdout/stderr to host
- Returns command's exit code (ssh exit code passthrough)
- Uses `bash -lc '<command>'` inside container for proper environment

**Argument parsing:**
- Everything after `--` is treated as the command (recommended for complex commands)
- Without `--`, first non-flag argument starts the command
- Quoting: `cai exec "echo hello"` runs the command in container

**Implementation (SSH runner integration):**
- Extend `_cai_ssh_run` with a `--login-shell` flag for login shell execution
- When `--login-shell`, wrap command as `bash -lc '<escaped-command>'`
- Use `printf %q` for safe command escaping to prevent injection
- `cai exec` always uses `--login-shell` mode for proper environment
- Existing `_cai_ssh_run` callers unchanged (no `--login-shell` = current behavior)

**Exit codes:**
- Command exit code passes through directly
- SSH connection failure: exit 255 (standard ssh behavior)
- Container create/start failure: exit 1 with error message

**How it differs from other commands:**
- `cai exec`: Run any command inside container (general purpose, via SSH)
- `cai run`: Run an AI agent with a prompt (agent-focused)
- `cai docker exec`: Run command via docker exec (host-side, uses docker context)

**Note:** `cai exec` runs commands **inside** the container via SSH. For host-side docker operations with the ContainAI context, use `cai docker` instead.

### Shell Completions

**`cai completion bash/zsh`** - Generate completion scripts

**Performance requirement:** `cai completion` MUST be fast (<100ms) and silent. It bypasses update checks and does no network I/O.

Completions for:
- Subcommands: `shell`, `run`, `exec`, `import`, `export`, `stop`, `status`, `gc`, `doctor`, `config`, `docker`
- Flags: `--container`, `--data-volume`, `--workspace`, `--fresh`, `--reset` (no `--template`)
- Static values: agent names (from built-in list)
- Dynamic values (only when completing that specific flag): container names, volume names

**Dynamic completion strategy:**
- Container/volume completion calls docker only when user is completing `--container` or `--data-volume` value
- Cache results for 5 seconds to avoid repeated docker calls during rapid tab completions
- If docker call fails/times out (>500ms), fall back to no completions (don't block shell)

**Special handling for `cai docker`:**
- Attempt to delegate to docker's completion if available
- Set `DOCKER_CONTEXT=containai-docker` before calling docker completion
- Fallback if docker completion unavailable: complete subcommands only (ps, logs, exec, etc.)
- Do NOT filter `--context` or `-u` - user can override if needed, we just inject defaults

```bash
# These work:
cai docker ps<TAB>
cai docker exec <TAB>  # Shows container names from containai-docker context

# We auto-inject defaults, but user can override:
# cai docker exec foo -> docker --context containai-docker exec -u agent foo
# cai docker exec -u root foo -> docker --context containai-docker exec -u root foo
```

### Setup Installs Completions

`cai setup` automatically adds completion to user's shell:

**For bash:**
```bash
# Generates STATIC completion script (not eval at runtime)
# Writes to ~/.bashrc.d/containai-completion.bash
# If ~/.bashrc.d/ doesn't exist, appends source line to ~/.bashrc
```

**Contents of completion file (static, not eval):**
```bash
# ContainAI shell completion - static script
# Auto-installed by cai setup
# Regenerate with: cai completion bash > ~/.bashrc.d/containai-completion.bash

_cai_completions() {
    # ... static completion logic ...
}
complete -F _cai_completions cai
```

**For zsh:**
```bash
# Creates ~/.zsh/completions/_cai (static compdef file)
# Ensures fpath includes ~/.zsh/completions
```

**Why static, not eval:**
- Avoids running `cai` on every shell startup
- No risk of update check latency
- User can inspect/modify the completion script
- Regenerate explicitly with `cai completion bash > path`

This ensures completions work immediately after setup without manual configuration.

### Nested Workspace Detection

When detecting the implicit workspace (from cwd), check if a parent directory has an existing container:

```bash
# User is in /foo/bar/zaz, but there's already a container for /foo/bar
$ cd /foo/bar/zaz
$ cai shell
[INFO] Using existing workspace at /foo/bar (parent of /foo/bar/zaz)
Starting shell in containai-bar-main...
```

**Detection checks BOTH sources:**
1. **Workspace config:** Walk up from cwd checking user config `[workspace."path"]` entries
2. **Container labels:** For each parent, also check for containers with `containai.workspace=<parent-path>` label

This catches both persisted state AND pre-existing containers that were created before workspace state was implemented.

**Efficient implementation (avoid N docker calls):**
1. Parse user config once, extract all workspace paths into a set
2. Compute ancestor list of cwd (once)
3. Query docker ONCE: list all containers with `containai.workspace` labels (`docker ps -a --filter label=containai.workspace --format '{{.Labels}}'`)
4. Check ancestors in-memory against both the config set and label set
5. Return nearest matching parent

**Rules:**
1. Walk up from cwd to filesystem root (in memory)
2. For each parent, check: (a) workspace config entry exists, OR (b) container with matching label exists
3. Use nearest matching parent as the implicit workspace
4. Log INFO message: "Using existing workspace at /foo/bar (parent of /foo/bar/zaz)"

**Path normalization:**
- Use existing `_cai_normalize_path` helper (NOT raw `realpath` - preserves platform semantics)
- Store normalized paths in workspace config
- On macOS, preserves Lima mount symlinks as needed

**Explicit `--workspace` with nested path = ERROR:**
```bash
$ cai shell --workspace /foo/bar/zaz
[ERROR] Cannot use /foo/bar/zaz as workspace.
        A container already exists at parent path /foo/bar.
        Use --workspace /foo/bar or remove the existing container first.
```

This prevents accidentally creating overlapping containers for nested directories.

### `cai docker` Passthrough

All `cai docker` commands automatically inject `--context containai-docker`:

```bash
# User types:
cai docker ps
cai docker logs containai-myapp-main
cai docker exec containai-myapp-main bash

# Actually runs:
docker --context containai-docker ps
docker --context containai-docker logs containai-myapp-main
docker --context containai-docker exec -u agent containai-myapp-main bash
```

**Important:** This ensures `cai docker logs`, `cai docker inspect`, and all other docker commands work correctly with the ContainAI Docker context.

### `cai config` Command

```bash
cai config list                        # Show all settings with source
cai config get <key>                   # Get effective value with source
cai config set <key> <value>           # Set (workspace if in one, else global)
cai config set --global|-g <key> <value>  # Force global
cai config set --workspace <path> <key> <value>  # Explicit workspace
cai config unset <key>                 # Remove setting
cai config unset --workspace <path> <key>  # Remove from specific workspace
```

**Workspace scope detection:**
- If in a workspace directory (or nested child): workspace-specific keys apply to that workspace
- If `--global` or `-g` specified: force global scope
- If `--workspace <path>` specified: apply to that specific workspace
- Outside any workspace and no flags: apply globally

**Write target:** Always user config (`~/.config/containai/config.toml`), never repo-local.

**Workspace-specific keys:**
- `data_volume` - Data volume name
- `container_name` - Container name
- `agent` - Default agent for this workspace

**Global keys:**
- `agent.default` - Default agent (global)
- `ssh.forward_agent` - Enable SSH agent forwarding
- `ssh.port_range_start` / `ssh.port_range_end` - SSH port range
- `import.auto_prompt` - Prompt for import on new volume

**`cai config list` output format:**
```
KEY                  VALUE                 SOURCE
───────────────────────────────────────────────────────────
data_volume          myapp-data           workspace:/home/user/myapp
container_name       containai-myapp-main workspace:/home/user/myapp
agent                claude               workspace:/home/user/myapp
agent.default        claude               user-global
ssh.forward_agent    true                 repo-local
ssh.port_range_start 2222                 default
```

Source values: `cli`, `env`, `workspace:<path>`, `repo-local`, `user-global`, `default`

**Implementation (source tracking):**
- NEW: `_containai_resolve_with_source <key>` returns `value\tsource` (tab-separated)
- Resolution pipeline checks each source in precedence order, returns first hit with source
- Avoids short-circuiting that loses provenance information
- `cai config list` calls resolver for each known key

**`cai config unset` behavior:**
- For workspace keys: removes key from workspace section
- If workspace section becomes empty: removes entire `[workspace."path"]` table
- For global keys: removes from user config top-level

## Tasks

### fn-36-rb7.1: Implement workspace state persistence

**Description:** Add functions to read/write workspace state in user config, independent of repo-local config. Create `_containai_read_workspace_state()` and `_containai_write_workspace_state()` in `src/lib/config.sh`. Extend `parse-toml.py` with atomic write capability.

**Files to modify:** `src/lib/config.sh`, `src/parse-toml.py`

**Acceptance:**
- [ ] `_containai_read_workspace_state <path>` returns workspace section from user config
- [ ] `_containai_write_workspace_state <path> <key> <value>` writes to user config atomically
- [ ] `parse-toml.py --set-workspace-key <path> <key> <value>` mode for atomic updates
- [ ] TOML write uses temp file + rename for atomicity
- [ ] Preserves comments and non-workspace sections in config
- [ ] Works even when repo-local config exists (doesn't conflict)
- [ ] Creates user config file with 0600 permissions if missing
- [ ] Creates config directory with 0700 permissions if missing
- [ ] Creates `[workspace."<normalized-path>"]` TOML table correctly
- [ ] Path is normalized via `_cai_normalize_path` (NOT raw realpath)

**Verification:** `cai shell` in a new workspace creates entry in `~/.config/containai/config.toml` with correct permissions

---

### fn-36-rb7.2: Implement consistent --container semantics

**Description:** Update `--container` flag handling to be command-appropriate: auto-create for shell/run/exec, require-exists for stop/export/import. This is a behavior change from current code.

**Files to modify:** `src/containai.sh` (shell, run commands), `src/lib/container.sh`

**Acceptance:**
- [ ] `cai shell --container foo`: creates if missing, uses if exists
- [ ] `cai run --container foo`: creates if missing, uses if exists
- [ ] `cai stop --container foo`: errors "Container foo not found" if missing
- [ ] `cai export --container foo`: errors if missing
- [ ] `cai import --container foo`: errors if missing
- [ ] Container name saved to workspace config on successful create/use
- [ ] Help text updated to document "uses existing or creates new" behavior
- [ ] Error messages guide users who expected old behavior

**Migration notes:**
- Current `cai run --container` requires container NOT exist (breaking change)
- Current `cai shell --container` requires container exist (breaking change)
- Scripts relying on "must not exist" should use `docker inspect` check first

**Verification:** Run each command with non-existent container, verify correct behavior; test help text

---

### fn-36-rb7.3: Implement --fresh flag

**Description:** Add `--fresh` flag to recreate container with same saved settings, preserving data volume.

**Files to modify:** `src/containai.sh` (shell command)

**Acceptance:**
- [ ] `--fresh` stops and removes existing container
- [ ] Creates new container with same name from workspace config
- [ ] Uses same data volume (does NOT create new volume)
- [ ] Does NOT modify workspace config entries
- [ ] Works correctly when no container exists (just creates)
- [ ] Logs "[INFO] Recreating container..."

**Verification:** Create container, `cai shell --fresh`, verify new container ID, same volume

---

### fn-36-rb7.4: Implement --reset flag

**Description:** Add `--reset` flag to regenerate workspace config values (container name, volume) while keeping the workspace section.

**Files to modify:** `src/containai.sh`, `src/lib/config.sh`

**Acceptance:**
- [ ] `--reset` stops and removes existing container
- [ ] **Keeps workspace section** but clears and regenerates all values
- [ ] Generates NEW unique volume name (format: `{repo}-{branch}-{timestamp}`)
- [ ] Writes new values to workspace config **immediately** (before any container ops)
- [ ] Never falls back to `sandbox-agent-data` default
- [ ] Next command uses the newly persisted values
- [ ] Logs "[INFO] Resetting workspace state..."

**Note:** `--reset` does NOT remove the workspace section entirely - it resets values within it. This ensures the new volume name is persisted before any subsequent command runs.

**Verification:** `cai shell`, note volume, `cai shell --reset`, verify different volume name AND verify config still has workspace section

---

### fn-36-rb7.5: Implement human-readable container naming

**Description:** Replace hash-based naming with `containai-{repo}-{branch}` format. Keep `_containai_container_name` as pure function (no docker calls). Collision handling stays in `_cai_resolve_container_name`.

**Files to modify:** `src/lib/container.sh` (`_containai_container_name`)

**Acceptance:**
- [ ] Format: `containai-{repo}-{branch}`, max 63 chars
- [ ] Repo = directory name (last path component)
- [ ] Branch from `git rev-parse --abbrev-ref HEAD`
- [ ] Non-git: use `nogit` as branch
- [ ] Detached HEAD: use short SHA (7 chars)
- [ ] Sanitization: lowercase, `/` → `-`, remove non-alphanum except `-`
- [ ] Truncate to 59 chars, reserve 4 for collision suffix
- [ ] `_containai_container_name` is pure function (no docker calls, no collision logic)
- [ ] Collision detection remains in `_cai_resolve_container_name` (fn-36-rb7.11)

**Verification:** Test with git repo, non-git dir, detached HEAD, long names; unit test naming function in isolation

---

### fn-36-rb7.6: Implement cai exec command

**Description:** Add `cai exec <command>` for running arbitrary commands inside container via SSH. Extend `_cai_ssh_run` with `--login-shell` mode.

**Files to modify:** `src/containai.sh`, `src/lib/ssh.sh`

**Acceptance:**
- [ ] `cai exec ls -la` runs command inside container
- [ ] Auto-creates/starts container if needed
- [ ] Allocates PTY if stdin is TTY (`ssh -t`)
- [ ] Streams stdout/stderr correctly
- [ ] Exit code passes through (command's exit code returned)
- [ ] `--` separates cai flags from command
- [ ] Extends `_cai_ssh_run` with `--login-shell` flag
- [ ] When `--login-shell`, wraps as `bash -lc '<escaped-command>'`
- [ ] Uses `printf %q` for safe command escaping (prevent injection)
- [ ] `--workspace` and `--container` flags work
- [ ] Existing `_cai_ssh_run` callers unchanged (backward compatible)

**Verification:** `cai exec echo hello`, `cai exec false` (exit 1), `cai exec -- --help`, test command with special chars

---

### fn-36-rb7.7: Implement cai config command

**Description:** Add `cai config` subcommand for get/set/list/unset with workspace-aware scope. Requires new `_containai_resolve_with_source` helper for provenance tracking.

**Files to modify:** `src/containai.sh`, `src/lib/config.sh`

**Acceptance:**
- [ ] `cai config list` shows all settings with source column
- [ ] `cai config get <key>` returns effective value with source
- [ ] `cai config set <key> <value>` writes to appropriate scope
- [ ] `cai config set -g <key> <value>` forces global scope
- [ ] `cai config set --workspace <path> <key> <value>` explicit workspace
- [ ] `cai config unset <key>` removes setting
- [ ] Auto-detects workspace from cwd using nested detection
- [ ] Output format matches spec (KEY, VALUE, SOURCE columns)
- [ ] NEW: `_containai_resolve_with_source <key>` returns `value\tsource` (tab-separated)
- [ ] Resolution pipeline tracks provenance without short-circuiting

**Verification:** Set workspace value, verify in `list` with correct source, verify in `~/.config/containai/config.toml`

---

### fn-36-rb7.8: Implement shell completion for cai commands

**Description:** Add `cai completion bash` and `cai completion zsh` that output static completion scripts. Must bypass update checks for performance.

**Files to modify:** `src/containai.sh`

**Acceptance:**
- [ ] `cai completion bash` outputs complete bash completion script
- [ ] `cai completion zsh` outputs complete zsh completion script
- [ ] Completes subcommands: shell, run, exec, import, export, stop, status, gc, doctor, config, docker
- [ ] Completes flags for each subcommand
- [ ] Dynamic container/volume completion (only when completing those flags)
- [ ] Fast: < 100ms, no update checks, no network I/O
- [ ] `completion` subcommand added to update-check skip list (like help/version)
- [ ] Script is static (can be saved to file)

**Verification:** `source <(cai completion bash)`, verify `cai <TAB>` works, verify no network calls

---

### fn-36-rb7.9: Implement shell completion for cai docker

**Description:** Add completion for `cai docker` subcommand that delegates to docker completion.

**Files to modify:** `src/containai.sh` (completion function)

**Acceptance:**
- [ ] `cai docker <TAB>` completes docker subcommands
- [ ] `cai docker ps <TAB>` works
- [ ] Sets `DOCKER_CONTEXT=containai-docker` before calling docker completion
- [ ] Graceful fallback if docker completion not available
- [ ] Does not filter `--context` or `-u` (user can override)

**Verification:** `cai docker <TAB>`, `cai docker exec <TAB>` shows container names

---

### fn-36-rb7.10: Update cai setup to install shell completions

**Description:** Make `cai setup` generate and install static completion script.

**Files to modify:** `src/containai.sh` (setup command)

**Acceptance:**
- [ ] Bash: writes to `~/.bashrc.d/containai-completion.bash` if dir exists
- [ ] Bash: otherwise adds source line to `~/.bashrc`
- [ ] Zsh: writes to `~/.zsh/completions/_cai`
- [ ] Script is static (not `eval "$(cai completion bash)"`)
- [ ] Creates parent directories if needed
- [ ] Logs where completion was installed

**Verification:** Run `cai setup`, start new shell, verify `cai <TAB>` works

---

### fn-36-rb7.11: Update container lookup helper

**Description:** Update `_cai_find_workspace_container()` to check workspace config first. Update `_cai_resolve_container_name()` to handle collision detection (called from fn-36-rb7.5 naming).

**Files to modify:** `src/lib/container.sh`

**Acceptance:**
- [ ] Lookup order: (1) workspace config, (2) workspace label, (3) new naming, (4) legacy hash
- [ ] If workspace config has `container_name`, check if it exists first
- [ ] Falls through to label/naming only if config entry missing or container gone
- [ ] Returns container name (not ID)
- [ ] `_cai_resolve_container_name` handles collision detection (append `-2`, `-3`, etc.)
- [ ] Collision check: name exists with different workspace label → increment suffix
- [ ] Max suffix `-99`, error if exceeded

**Verification:** Create container, verify lookup finds it via each method; test collision with conflicting workspace

---

### fn-36-rb7.12: Update all commands to use workspace state

**Description:** Update shell, run, exec, import, export, stop to read/write workspace state.

**Files to modify:** `src/containai.sh`

**Acceptance:**
- [ ] `cai shell` reads workspace state, creates if missing, saves on first use
- [ ] `cai run` same as shell
- [ ] `cai exec` same as shell
- [ ] `cai import` reads workspace state to find container/volume
- [ ] `cai export` reads workspace state
- [ ] `cai stop` reads workspace state
- [ ] CLI flags override workspace state
- [ ] Overrides are saved back to workspace state

**Verification:** `cai shell` in new dir, exit, `cai import`, verify uses same container

---

### fn-36-rb7.13: Implement nested workspace detection

**Description:** When resolving implicit workspace, check parent directories for existing workspaces. Use efficient strategy (single docker query, in-memory checks).

**Files to modify:** `src/lib/config.sh` or `src/containai.sh`

**Acceptance:**
- [ ] Walk up from cwd checking workspace config entries
- [ ] Also check for containers with `containai.workspace` label on parent paths
- [ ] Use nearest matching parent as workspace
- [ ] Log INFO: "Using existing workspace at /parent (parent of /parent/child)"
- [ ] Normalize paths via `_cai_normalize_path` (NOT raw realpath)
- [ ] Explicit `--workspace` with nested path: error if parent has workspace
- [ ] **Efficient implementation:** parse config once, compute ancestors once, single docker query
- [ ] Do NOT call docker per-ancestor (would be slow in deep trees)

**Verification:** Create container in /tmp/foo, cd /tmp/foo/bar, `cai shell` uses /tmp/foo; verify no excessive docker calls

---

### fn-36-rb7.14: Fix cai docker passthrough for all commands

**Description:** Ensure all `cai docker` subcommands work with context injection.

**Files to modify:** `src/containai.sh` (docker passthrough)

**Acceptance:**
- [ ] `cai docker ps` works
- [ ] `cai docker logs <container>` works
- [ ] `cai docker exec <container> <cmd>` works (injects `-u agent` for containai containers)
- [ ] `cai docker inspect <container>` works
- [ ] `cai docker rm <container>` works
- [ ] User-supplied `--context` overrides auto-injection
- [ ] User-supplied `-u` overrides auto-injection for exec

**Verification:** `cai docker logs containai-*`, `cai docker exec containai-* whoami`

## Quick commands

```bash
# Test workspace state persistence
cd /tmp/test-project && git init
cai shell  # Creates with auto-generated names
cai shell  # Uses saved names (no flags needed)

# Test --fresh
cai shell --fresh  # Recreate with same settings

# Test --reset
cai shell --reset  # Clear config, start fresh

# Test exec
cai exec ls -la
cai exec npm test

# Test config (workspace-aware)
cd /tmp/test-project
cai config list              # Shows workspace settings
cai config set agent claude  # Sets for this workspace
cai config set -g agent.default claude  # Sets globally

# Test cai docker passthrough
cai docker ps
cai docker logs containai-test-project-main

# Test nested workspace detection
mkdir -p /tmp/test-project/subdir
cd /tmp/test-project/subdir
cai shell  # Should use /tmp/test-project container

# Test completions
source <(cai completion bash)
cai <TAB>
cai shell --<TAB>
cai docker ps <TAB>
```

## Acceptance

- [ ] Config layering works: user workspace state always read regardless of repo config
- [ ] Workspace settings saved to user config on first use
- [ ] Subsequent commands use saved settings (no flags needed)
- [ ] `--container` works command-appropriately: create for shell/run/exec, error for stop/export/import
- [ ] `--data-volume` saved to workspace config; errors if container exists with different volume
- [ ] `--fresh` recreates container with same settings (preserves volume)
- [ ] `--reset` clears workspace config, generates NEW unique volume (no shared default fallback)
- [ ] Container names use repo-branch format with edge case handling (non-git, detached, truncation)
- [ ] `cai exec` runs commands inside container via SSH with proper TTY/exit code
- [ ] `cai config list` shows source column (cli/env/workspace/repo-local/user-global/default)
- [ ] `cai config --global` forces global scope
- [ ] Shell completion is static (not eval), fast (<100ms), no network I/O
- [ ] `cai setup` installs static completion to ~/.bashrc.d/ or ~/.bashrc
- [ ] `cai docker logs` works (context injected)
- [ ] `cai docker` completion delegates to docker completion with fallback
- [ ] Nested workspace detection checks BOTH config entries AND container labels
- [ ] Explicit --workspace /nested/path errors if parent has existing workspace

## Supersedes

- **fn-12-css** workspace state, config command, cai exec
- **fn-18-g96** container naming, --container semantics, shell completion
- **fn-34-fk5** --container, --reset, container lookup (keep session detection, gc, run)

## Dependencies

None - this should be done FIRST

## References

- fn-12-css spec: `.flow/specs/fn-12-css.md`
- fn-18-g96 spec: `.flow/specs/fn-18-g96.md`
- Bash completion: https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion.html
- Docker completion: https://docs.docker.com/compose/completion/
