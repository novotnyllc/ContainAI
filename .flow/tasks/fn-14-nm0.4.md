# fn-14-nm0.4 Add cai --version flag

## Description
Add `--version` flag handling to the main `containai()` function so users can run `cai --version`.

**Size:** S
**Files:** `src/containai.sh`

## Current State

Only `cai version` subcommand works (`containai.sh:1917-1919`). The `--version` flag is not handled.

## Approach

Add flag parsing before the subcommand case statement in `containai()` function (around line 1868).

**Pattern to follow:** Standard bash flag handling:
```bash
# At start of containai() function, before case statement
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version|-v)
            _cai_version
            return 0
            ;;
        -*)
            # Unknown flag, let subcommand handle it
            break
            ;;
        *)
            # Not a flag, proceed to subcommand
            break
            ;;
    esac
done
```

**Reuse:** `_cai_version()` in `src/lib/version.sh:43-139` - already implemented
## Acceptance
- [ ] `cai --version` prints version info and exits 0
- [ ] `cai -v` also works (short flag)
- [ ] `cai version` still works (subcommand)
- [ ] `shellcheck -x src/containai.sh` passes
## Done summary
Added --version and -v flag handling to the main containai() function, consolidated with the existing version subcommand into a single pattern match.
## Evidence
- Commits: 2978c0e056bb444e2c29756a1c0023480518513b
- Tests: cai --version, cai -v, cai version, shellcheck -x src/containai.sh
- PRs:
