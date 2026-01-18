# fn-4-vet.12 Create containai.sh - main CLI entry point

## Description
Create `agent-sandbox/containai.sh` - a sourced shell script (not executable wrapper).

**Usage:** `source agent-sandbox/containai.sh` then `cai` / `containai` are available as shell functions.

(No `bin/cai` wrapper yet — will refactor to proper CLI later.)

## Structure

```bash
#!/usr/bin/env bash
# ContainAI CLI

_CAI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CAI_SCRIPT_DIR/lib/config.sh"
source "$_CAI_SCRIPT_DIR/lib/container.sh"
source "$_CAI_SCRIPT_DIR/lib/import.sh"
source "$_CAI_SCRIPT_DIR/lib/export.sh"

containai() {
    local subcommand="${1:-}"
    shift 2>/dev/null || true
    
    case "$subcommand" in
        shell)   _containai_shell "$@" ;;
        import)  _containai_import_cmd "$@" ;;
        export)  _containai_export_cmd "$@" ;;
        stop)    _containai_stop_all "$@" ;;
        help|-h|--help) _containai_help ;;
        *)       _containai_run "$subcommand" "$@" ;;  # Default: start container
    esac
}

# Short alias
cai() { containai "$@"; }
```

## Subcommand Handlers

### `_containai_run(args...)`
Parse common flags (`--data-volume`, `--config`, `--workspace`), resolve volume,
start/attach to container. Core logic from aliases.sh `asb()`.

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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
