# fn-4-vet.5 Add containai and cai CLI aliases

## Description

Add `containai` and `cai` as primary CLI aliases for all commands, keeping `asb*` functions as deprecated but working aliases with one-time warning.

## Implementation

### New Primary Aliases

Primary commands call the implementation directly (no deprecation warning):

```bash
containai() { _asb_impl "$@"; }
cai() { _asb_impl "$@"; }

containai-stop-all() { _asb_stop_all_impl "$@"; }
cai-stop-all() { _asb_stop_all_impl "$@"; }

containai-shell() { _asb_impl --shell "$@"; }
cai-shell() { _asb_impl --shell "$@"; }

containaid() { _asb_impl --detached "$@"; }
caid() { _asb_impl --detached "$@"; }
```

### Deprecation Policy

One-time warning per shell session, suppressible via `CONTAINAI_NO_DEPRECATION_WARNING=1`:

```bash
# Only initialize if unset (re-sourcing doesn't reset)
: "${_containai_deprecation_warned:=}"

_containai_deprecation_check() {
    [[ "${CONTAINAI_NO_DEPRECATION_WARNING:-}" == "1" ]] && return 0
    [[ -n "$_containai_deprecation_warned" ]] && return 0
    echo "[WARN] 'asb' commands are deprecated. Use 'containai' or 'cai' instead." >&2
    echo "       Suppress this warning: export CONTAINAI_NO_DEPRECATION_WARNING=1" >&2
    _containai_deprecation_warned=1
}

# Deprecated wrappers show warning then delegate
asb() { _containai_deprecation_check; _asb_impl "$@"; }
asb-stop-all() { _containai_deprecation_check; _asb_stop_all_impl "$@"; }
asbd() { _containai_deprecation_check; _asb_impl --detached "$@"; }
asb-shell() { _containai_deprecation_check; _asb_impl --shell "$@"; }
asbs() { asb-shell "$@"; }
```

### Help Text

Shows all command variants with deprecated markers:

```
Usage: containai [options] -- [claude-options]
       cai [options] -- [claude-options]
       asb [options] -- [claude-options]  (deprecated)
```

Volume selection note included in help:
```
Volume Selection:
  Volume is automatically selected based on workspace path from config.
  Use --data-volume to override automatic selection.
```

### Additional Changes

- Bash version guard at top of aliases.sh for non-bash shells
- README updated to document cai/containai as primary commands
- User-facing error messages updated to say "ContainAI" not "asb"
- Help-scan loops stop at `--` delimiter

## Key Files

- Modified: `agent-sandbox/aliases.sh` (add aliases, deprecation)
- Modified: `agent-sandbox/README.md` (document new commands)
- Modified: `agent-sandbox/sync-agent-plugins.sh` (update command suggestions)

## Acceptance

- [x] `containai` works identically to core functionality
- [x] `cai` works identically to core functionality
- [x] `containai-stop-all` and `cai-stop-all` work
- [x] `containai-shell` and `cai-shell` work
- [x] `containaid` and `caid` work
- [x] `asb` shows one-time deprecation warning to stderr
- [x] Warning only shown once per shell session
- [x] `CONTAINAI_NO_DEPRECATION_WARNING=1` suppresses warning
- [x] `cai` does NOT show deprecation warning
- [x] Help text shows volume selection is automatic by workspace

## Done summary

Added containai and cai as primary CLI aliases for all agent-sandbox commands. The asb* commands remain functional but now show a one-time deprecation warning per shell session that can be suppressed via CONTAINAI_NO_DEPRECATION_WARNING=1. Updated help text, README, and error messages to document and use the new command names.

## Evidence

- Commits: 46722d7, bdfdc16, 34a0f30
- Tests: bash -n aliases.sh, function definition checks, deprecation warning tests
- PRs: (none yet)
