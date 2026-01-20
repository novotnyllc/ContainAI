# fn-6-aaz.2 Add env config resolution to lib/config.sh

## Description
Add `_containai_resolve_env_config()` function to `lib/config.sh` for **dedicated** env import configuration resolution, independent of volume/excludes.

**Size:** S  
**Files:** `agent-sandbox/lib/config.sh`

## Approach

- Create `_containai_resolve_env_config()` as SEPARATE function (not tied to volume resolution)
- Call `parse-toml.py` and extract `[env]` section
- Return JSON with: `import` (array), `from_host` (bool), `env_file` (string or null)
- Handle missing `[env]` gracefully (return defaults)
- Handle missing/invalid `import` with `[WARN]` and treat as `[]`
- This runs even if `--data-volume` or `--no-excludes` is used
## Approach

- Follow pattern at `lib/config.sh:441-512` (`_containai_resolve_volume`)
- Call `parse-toml.py` and extract env section
- Return JSON with: `import` (array), `from_host` (bool), `env_file` (string or null)
- Handle missing config gracefully (return empty/defaults)
## Acceptance
- [ ] `_containai_resolve_env_config` function exists (separate from volume resolution)
- [ ] Returns JSON with `import`, `from_host`, `env_file` keys
- [ ] Missing `[env]` section: returns defaults `import=[]`, `from_host=false`, `env_file=null`
- [ ] `[env]` exists but `import` missing/invalid: `[WARN]`, returns `import=[]`
- [ ] Runs independently of `--data-volume` and `--no-excludes` flags
- [ ] Calls `parse-toml.py` with correct arguments
- [ ] Error handling follows existing patterns (if/else guards for set -e)
- [ ] Python unavailable (discovered config): returns defaults with `[WARN]`
- [ ] Python unavailable (explicit config): return 1 (fail fast per epic spec)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
