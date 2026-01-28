# fn-12-css.8 Remove host env import behavior

## Description

Remove the `from_host = true` env import behavior from lib/env.sh. This feature is a security risk - too easy to accidentally export sensitive environment variables from the host.

**Current behavior (to remove):**
```toml
[env]
import = ["GITHUB_TOKEN", "AWS_*"]
from_host = true  # Reads from host's environment
```

When `from_host = true`, the import mechanism reads from the host's `printenv` output and filters by the allowlist. This is dangerous because:
- Host may have unexpected env vars (secrets from other tools)
- Wildcards like `AWS_*` could match more than intended
- No audit trail of what was actually imported

**New behavior (after this task):**
- `from_host` config key is ignored (with deprecation warning)
- Environment variables ONLY come from .env file hierarchy (task 7)
- `[env].import` still works as an allowlist but filters the merged .env files

**Implementation:**

1. In lib/env.sh `_containai_import_env()`:
   - Remove the `printenv | grep` host env reading code
   - Remove `_env_read_host_env()` function if exists
   - Update to only read from file hierarchy

2. In lib/config.sh `_containai_resolve_env_config()`:
   - Ignore `from_host` key
   - Log warning if `from_host = true` is in config: "Warning: from_host is deprecated, use .env files"

3. In docs/configuration.md (separate doc task):
   - Mark `from_host` as deprecated
   - Document .env file hierarchy

**Migration path:**
Users who relied on `from_host` need to:
1. Create `~/.config/containai/default.env`
2. Add their needed env vars explicitly
3. More secure and auditable

## Acceptance

- [ ] `from_host = true` in config does not import host env vars
- [ ] Warning logged when `from_host` is found in config
- [ ] Env import only reads from .env file hierarchy
- [ ] `[env].import` allowlist still filters the .env file contents
- [ ] No host `printenv` calls in env import flow

## Done summary
Superseded by fn-36-rb7 or fn-31-gib
## Evidence
- Commits:
- Tests:
- PRs:
