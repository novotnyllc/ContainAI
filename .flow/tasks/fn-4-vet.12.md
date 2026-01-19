# fn-4-vet.12 Create containai.sh - main CLI entry point

<!-- Updated by plan-sync: fn-4-vet.4 architecture note -->
<!-- No _containai_main() exists - main logic is in asb() in aliases.sh -->
<!-- lib/*.sh files don't exist yet - all functions in aliases.sh -->
<!-- May need to create containai.sh that sources aliases.sh + adds subcommands -->

## Description
Create `agent-sandbox/containai.sh` - a sourced shell script (not executable wrapper).

**Usage:** `source agent-sandbox/containai.sh` then `cai` / `containai` are available as shell functions.

(No `bin/cai` wrapper yet — will refactor to proper CLI later.)

## Structure

<!-- Updated by plan-sync: fn-4-vet.4 architecture - source aliases.sh for now -->
<!-- lib/*.sh files are planned for future extraction -->
```bash
#!/usr/bin/env bash
# ContainAI CLI

_CAI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Option A: Source libs if they exist (post fn-4-vet.8/9/10/11)
# source "$_CAI_SCRIPT_DIR/lib/config.sh"
# source "$_CAI_SCRIPT_DIR/lib/container.sh"
# source "$_CAI_SCRIPT_DIR/lib/import.sh"
# source "$_CAI_SCRIPT_DIR/lib/export.sh"

# Option B: Source aliases.sh which contains all functions (current state)
source "$_CAI_SCRIPT_DIR/aliases.sh"

containai() {
    local subcommand="${1:-}"
    shift 2>/dev/null || true

    case "$subcommand" in
        shell)   asb-shell "$@" ;;  # Use existing asb-shell
        import)  _containai_import_cmd "$@" ;;  # New subcommand
        export)  _containai_export_cmd "$@" ;;  # New subcommand
        stop)    asb-stop-all "$@" ;;  # Use existing asb-stop-all
        help|-h|--help) _containai_help ;;
        *)       asb "$subcommand" "$@" ;;  # Default: delegate to asb()
    esac
}

# Short alias
cai() { containai "$@"; }
```

## Subcommand Handlers

<!-- Updated by plan-sync: fn-4-vet.4 note - asb() already handles flags, delegate to it -->
### Default case (no subcommand)
Delegate to `asb()` which already handles `--data-volume`, `--config`, `--workspace` flags.

### `_containai_shell(args...)`
Open shell in running container. Logic from `asb-shell()`.

### `_containai_import_cmd(args...)`
Parse `--dry-run`, `--no-excludes`. Call `_containai_import()` from lib/import.sh.

### `_containai_export_cmd(args...)`
Parse `-o/--output`, `--no-excludes`. Call `_containai_export()` from lib/export.sh.

### `_containai_help()`
Print usage help.

## Common Flag Parsing

```bash
_containai_parse_common_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --data-volume) _CAI_CLI_VOLUME="$2"; shift 2 ;;
            --config)      _CAI_CLI_CONFIG="$2"; shift 2 ;;
            --workspace)   _CAI_CLI_WORKSPACE="$2"; shift 2 ;;
            --)            shift; break ;;
            *)             break ;;
        esac
    done
    # Return remaining args
    printf '%s\n' "$@"
}
```
## Acceptance
- [ ] File exists at `agent-sandbox/containai.sh`
- [ ] `containai` function routes to subcommands
- [ ] `cai` alias works
- [ ] `cai` (no args) starts/attaches container
- [ ] `cai shell` opens shell in running container
- [ ] `cai import` syncs configs with exclude support
- [ ] `cai export` creates .tgz archive
- [ ] `cai stop` stops all containers
- [ ] Common flags parsed correctly across subcommands
## Done summary
Created containai.sh as the main CLI entry point that sources lib/*.sh modules and provides subcommand routing for shell, import, export, stop commands. Implements Option A/B library loading (libs if exist, else aliases.sh fallback) for backward compatibility.
## Evidence
- Commits: a75ab80, cf7d0a6, 0062fe0
- Tests: bash -c 'source agent-sandbox/containai.sh && type containai', bash -c 'cai help', bash -c 'cai import --help', bash -c 'cai export --help', bash -c 'cai import --data-volume='
- PRs: