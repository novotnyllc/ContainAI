# Configurable Volumes & ContainAI CLI

## Overview

Replace hardcoded `sandbox-agent-data` with configurable volumes. Rename to ContainAI with unified CLI.

## Key Decisions

- No backwards compat
- Python optional (only required when config parsing needed for the specific operation)
- Absolute paths only
- Label ownership

## TOML Schema

```toml
[agent]
data_volume = "sandbox-agent-data"
import_excludes = [".vscode-server/data/User/settings.json"]

[workspace."/home/user/project"]
data_volume = "project-data"
import_excludes = [".custom/path"]
```

## When Config is Parsed

| Command | Volume from Config? | Excludes from Config? |
|---------|---------------------|----------------------|
| `cai` (run) | Yes (unless CLI/env set) | No |
| `cai shell` | Yes (unless CLI/env set) | No |
| `cai import` | Yes (unless CLI/env set) | Yes (unless `--no-excludes`) |
| `cai export` | Yes (unless CLI/env set) | N/A |
| `cai stop` | No | No |

**Python required only when config is actually parsed** for the operation. If `--data-volume` set for `cai` run, no config parsed, no Python needed.

## Config Discovery

**Search order:**
1. `--config <path>` → Error if missing/invalid
2. Walk up from workspace to git root or `/`
3. User config

### Errors

- `--config` missing → error
- `--workspace` invalid → error
- Python unavailable when config needed → error with workaround

## Workspace Path Matching

1. Normalize: Absolute paths, no trailing `/`
2. Segment boundary: `P` matches `W` if `W == P` or `W == P/*`
3. Longest match wins
4. Fallback: `[agent]`, then default

## Import Exclude Translation Algorithm

**Source-relative excludes to per-entry rsync excludes:**

```bash
# SYNC_MAP entry format: "/source/<src>:/target/<tgt>:<flags>"
#
# For each entry:
#   source_path = <src> (e.g., ".vscode-server/data/User")
#
# For each import_exclude pattern:
#   If pattern == source_path → skip entire entry
#   If pattern starts with source_path/ → 
#     remainder = pattern after source_path/
#     pass --exclude remainder to rsync
#   Else → pattern doesn't apply to this entry

_containai_translate_excludes() {
    local source_path="$1"
    shift
    local -a excludes=("$@")
    
    local -a result=()
    for pattern in "${excludes[@]}"; do
        if [[ "$pattern" == "$source_path" ]]; then
            echo "SKIP_ENTRY"
            return
        elif [[ "$pattern" == "$source_path/"* ]]; then
            result+=("${pattern#$source_path/}")
        fi
        # else: pattern doesn't apply
    done
    
    printf '%s\n' "${result[@]}"
}
```

**Examples:**

| SYNC_MAP Source | Exclude Pattern | Result |
|-----------------|-----------------|--------|
| `.vscode-server/data/User` | `.vscode-server/data/User/settings.json` | `--exclude settings.json` |
| `.vscode-server/data/User` | `.vscode-server/data` | No match |
| `.claude.json` | `.claude.json` | **Skip entry** |
| `.claude/plugins` | `.claude.json` | No match |

## CLI Design

**Usage:** `source agent-sandbox/containai.sh` first, then `cai` / `containai` are available as shell functions.

(No `bin/cai` wrapper yet — will refactor to proper CLI later.)

### Parse Order

```
cai [global] [subcommand] [sub-flags] -- [args]
```

### Global Flags

| Flag | Scope | Description |
|------|-------|-------------|
| `--data-volume` | All | Volume (skips config volume lookup) |
| `--config` | All | Config file |
| `--workspace` | All | Workspace path |

### Subcommands

| Subcommand | Description |
|------------|-------------|
| (default) | Run |
| `shell` | Shell |
| `import` | Import |
| `export` | Export |
| `stop` | Stop |

### Import/Export Flags

| Flag | Description |
|------|-------------|
| `--no-excludes` | Skip exclude patterns (no config parsing for excludes) |
| `--dry-run` | (import) Show only |
| `-o` | (export) Output path |

## Preflight Checks

**Order (sequential):**

1. **Docker availability**
   ```bash
   if ! command -v docker >/dev/null 2>&1; then
       echo "[ERROR] Docker not found" >&2
       return 1
   fi
   if ! docker info >/dev/null 2>&1; then
       echo "[ERROR] Cannot connect to Docker" >&2
       return 1
   fi
   ```

2. **Sandbox availability** (adapted from `_asb_check_sandbox`)
   ```bash
   local output rc
   output=$(docker sandbox ls 2>&1)
   rc=$?
   if [[ $rc -ne 0 ]]; then
       if echo "$output" | grep -qiE "docker desktop.*required|feature.*disabled"; then
           echo "[ERROR] Docker sandbox feature disabled" >&2
           return 1
       fi
       # "No sandboxes" is OK
   fi
   ```

3. **Label support**
   ```bash
   docker sandbox run --help 2>&1 | grep -q '\-\-label'
   ```

4. **Image availability**

5. **Isolation warning** (non-blocking)

## Export Directory Handling

Output directory must exist:
```bash
if [[ ! -d "$output_dir" ]]; then
    echo "[ERROR] Output directory doesn't exist: $output_dir" >&2
    return 1
fi
```

## Label

`containai.sandbox=containai`

## Platform Support

| Command | Linux/WSL | macOS | Win (WSL) | Win (native) |
|---------|-----------|-------|-----------|--------------|
| run | ✓ | ✓ | ✓ | ✓ |
| shell | ✓ | ✓ | ✓ | ✓ |
| import | ✓ | ✗ | ✓ | ✗ |
| export | ✓ | ✓* | ✓* | ✗ |
| stop | ✓ | ✓ | ✓ | ✓ |

## Value Precedence

| Priority | Source |
|----------|--------|
| 1 | `--data-volume` |
| 2 | `CONTAINAI_DATA_VOLUME` |
| 3 | Config workspace |
| 4 | Config agent |
| 5 | Default |

## Container Naming

Format: `cai-<repo>-<branch>`
Sanitization from aliases.sh:28-87.

## Files

### Remove
- `aliases.sh`, `sync-agent-plugins.sh`

### Create
- `containai.sh` (sourced, not executable), `parse-toml.py`, `lib/*.sh`

### Update
- `README.md`, `test-sync-integration.sh`

## Acceptance Criteria

1. `asb*` removed
2. `cai` works
3. Preflight: Docker → sandbox → label (in order)
4. Label enforced
5. `cai stop` label-based
6. Config discovery works
7. `--config` missing → error
8. `--workspace` invalid → error
9. Volume from CLI skips config volume lookup
10. Excludes parsed only for import
11. `--no-excludes` skips exclude parsing
12. Python only required when parsing config
13. Workspace matching: segment boundary, longest wins
14. Import exclude translation: source-path relative, prefix match
15. Import exclude: file-only entry (`.claude.json`) can be skipped
16. Export excludes: volume-relative
17. Export: Output dir must exist
18. Import: Linux/WSL only
19. Safety checks preserved
20. Container naming sanitized
21. containai.sh must be sourced (no bin wrapper yet)

## References

- `agent-sandbox/sync-agent-plugins.sh`
- `agent-sandbox/aliases.sh`
