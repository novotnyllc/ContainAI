# fn-4-vet.5 Add containai and cai CLI aliases

## Description
## Overview
Add `containai` and `cai` as primary CLI aliases for all commands, keeping `asb*` functions as deprecated but working aliases with one-time warning.

## Implementation

### New Primary Aliases
```bash
# Primary commands - no deprecation warning
containai() { _containai_main "$@"; }
cai() { _containai_main "$@"; }

containai-stop-all() { asb-stop-all "$@"; }
cai-stop-all() { asb-stop-all "$@"; }

containai-shell() { asb-shell "$@"; }
cai-shell() { asb-shell "$@"; }

containaid() { asbd "$@"; }
caid() { asbd "$@"; }
```

### Deprecation Policy
One-time warning per shell session, suppressible:

```bash
_containai_deprecation_warned=""

_containai_deprecation_warn_asb() {
    [[ "${CONTAINAI_NO_DEPRECATION_WARNING:-}" == "1" ]] && return 0
    [[ -n "$_containai_deprecation_warned" ]] && return 0
    
    echo "[WARN] 'asb' commands are deprecated. Use 'containai' or 'cai' instead." >&2
    echo "       Suppress: export CONTAINAI_NO_DEPRECATION_WARNING=1" >&2
    _containai_deprecation_warned=1
}

asb() {
    _containai_deprecation_warn_asb
    _containai_main "$@"
}
```

### Help Text
```
Usage: containai [OPTIONS] [-- AGENT_ARGS...]
       cai [OPTIONS] [-- AGENT_ARGS...]

Options:
  --data-volume <name>   Use specified Docker volume for agent data
  --config <path>        Use explicit config file (disables discovery)
  --volume, -v <mount>   Add additional bind mount
  --workspace <path>     Use specified host workspace

Volume is automatically selected based on workspace path from config.
Use --data-volume to override.
```

## Key Files
- Modify: `agent-sandbox/aliases.sh` (add aliases, deprecation)
## Overview
Add `containai` and `cai` as primary CLI aliases for all commands, keeping `asb*` functions as deprecated but working aliases with one-time warning.

## Implementation

### New Primary Aliases (all mapping to asb equivalents)
```bash
# Primary commands
containai() { _containai_deprecation_warn_asb; _containai_main "$@"; }
cai() { _containai_main "$@"; }

# Stop all
containai-stop-all() { asb-stop-all "$@"; }
cai-stop-all() { asb-stop-all "$@"; }

# Shell access
containai-shell() { asb-shell "$@"; }
cai-shell() { asb-shell "$@"; }

# Detached mode
containaid() { asbd "$@"; }
caid() { asbd "$@"; }
```

### Deprecation Policy
One-time warning per shell session, suppressible:

```bash
_containai_deprecation_warned=""

_containai_deprecation_warn_asb() {
    [[ "${CONTAINAI_NO_DEPRECATION_WARNING:-}" == "1" ]] && return 0
    [[ -n "$_containai_deprecation_warned" ]] && return 0
    
    echo "[WARN] 'asb' commands are deprecated. Use 'containai' or 'cai' instead." >&2
    echo "       Suppress this warning: export CONTAINAI_NO_DEPRECATION_WARNING=1" >&2
    _containai_deprecation_warned=1
}

# Deprecated commands show warning
asb() {
    _containai_deprecation_warn_asb
    _containai_main "$@"
}
```

### Help Text Updates
```
Usage: containai [OPTIONS] [-- AGENT_ARGS...]
       cai [OPTIONS] [-- AGENT_ARGS...]
       asb [OPTIONS] [-- AGENT_ARGS...]  (deprecated)

Options:
  --data-volume <name>   Use specified Docker volume for agent data
  --profile <name>       Use named profile from config file
  --config <path>        Use explicit config file (disables discovery)
  --volume, -v <mount>   Add additional bind mount (unchanged)
  --workspace <path>     Use specified host workspace (unchanged)
  
Related Commands:
  cai-stop-all           Stop all sandbox containers
  cai-shell              Open shell in running sandbox
  caid                   Run in detached mode
```

## Key Files
- Modify: `agent-sandbox/aliases.sh` (add new aliases near end)
- Modify: `agent-sandbox/aliases.sh:404` (asb function → add deprecation)
- Modify: Help/usage text for new flags
## Overview
Add `containai` and `cai` as primary CLI aliases, keeping `asb*` functions as deprecated but working aliases with one-time warning.

## Implementation

### New Primary Aliases
```bash
# Primary aliases - these are the recommended commands
containai() { _containai_main "$@"; }
cai() { _containai_main "$@"; }

containai-stop-all() { asb-stop-all "$@"; }
cai-stop-all() { asb-stop-all "$@"; }

containai-shell() { asb-shell "$@"; }
cai-shell() { asb-shell "$@"; }

containaid() { asbd "$@"; }
caid() { asbd "$@"; }
```

### Deprecation Policy
One-time warning per shell session, suppressible:

```bash
_containai_deprecation_warned=""

_containai_deprecation_check() {
    if [[ "${CONTAINAI_NO_DEPRECATION_WARNING:-}" == "1" ]]; then
        return 0
    fi
    if [[ -z "$_containai_deprecation_warned" ]]; then
        echo "[WARN] 'asb' commands are deprecated. Use 'containai' or 'cai' instead." >&2
        echo "       Suppress this warning: export CONTAINAI_NO_DEPRECATION_WARNING=1" >&2
        _containai_deprecation_warned=1
    fi
}

asb() {
    _containai_deprecation_check
    _containai_main "$@"
}
```

### Help Text Updates
Update usage text to show both old and new command names:
```
Usage: containai [OPTIONS] COMMAND [ARGS...]
       cai [OPTIONS] COMMAND [ARGS...]
       asb [OPTIONS] COMMAND [ARGS...]  (deprecated)

Options:
  --data-volume <name>   Use specified Docker volume for agent data
  --profile <name>       Use named profile from config file
  --volume, -v <mount>   Add additional bind mount (unchanged)
  --workspace <path>     Use specified host workspace (unchanged)
  ...
```

### v1 Alias Strategy
For v1, `containai`/`cai` are shell function aliases only. If a future `containai` binary is added to PATH, functions will shadow it. Acceptable for v1.

## Key Files
- Modify: `agent-sandbox/aliases.sh` (add new aliases at end)
- Modify: `agent-sandbox/aliases.sh` (asb function → add deprecation check)
- Modify: Help/usage text throughout
## Overview
Add `containai` and `cai` as primary CLI aliases, keeping `asb*` functions as deprecated but working aliases.

## Implementation

### New Primary Aliases
```bash
# Primary aliases - these are the recommended commands
containai() { asb "$@"; }
cai() { asb "$@"; }

containai-stop-all() { asb-stop-all "$@"; }
cai-stop-all() { asb-stop-all "$@"; }

containai-shell() { asb-shell "$@"; }
cai-shell() { asb-shell "$@"; }

containaid() { asbd "$@"; }
caid() { asbd "$@"; }
```

### Deprecation Notice
Add a one-time deprecation notice when `asb` is used directly:

```bash
_asb_deprecation_warned=false

asb() {
    if [[ "$_asb_deprecation_warned" != "true" ]]; then
        echo "[WARN] 'asb' is deprecated, use 'containai' or 'cai' instead" >&2
        _asb_deprecation_warned=true
    fi
    _containai_main "$@"
}
```

### Internal Rename
Optionally rename internal `_asb_*` functions to `_containai_*` for consistency. Keep `_asb_*` as aliases if changed.

## Key Files
- Modify: `agent-sandbox/aliases.sh` (add new aliases at end)
- Modify: `agent-sandbox/aliases.sh:404` (asb function - add deprecation)
## Acceptance
- [ ] `containai` works identically to core functionality
- [ ] `cai` works identically to core functionality
- [ ] `containai-stop-all` and `cai-stop-all` work
- [ ] `containai-shell` and `cai-shell` work
- [ ] `containaid` and `caid` work
- [ ] `asb` shows one-time deprecation warning to stderr
- [ ] Warning only shown once per shell session
- [ ] `CONTAINAI_NO_DEPRECATION_WARNING=1` suppresses warning
- [ ] `cai` does NOT show deprecation warning
- [ ] Help text shows volume selection is automatic by workspace
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
