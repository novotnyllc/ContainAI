# fn-36-rb7.7 Implement cai config command

## Description
Add `cai config` subcommand for get/set/list/unset with workspace-aware scope. Implement `_containai_resolve_with_source` to return value + provenance.

## Acceptance
- [ ] `cai config list` shows settings with source column
- [ ] `cai config get <key>` returns effective value with source
- [ ] `cai config set <key> <value>` writes to appropriate scope
- [ ] `cai config set -g <key> <value>` forces global scope
- [ ] `cai config set --workspace <path> <key> <value>` explicit workspace
- [ ] `cai config unset <key>` removes setting
- [ ] Auto-detects workspace from cwd using nested detection
- [ ] Output format matches spec (KEY, VALUE, SOURCE)
- [ ] `_containai_resolve_with_source <key>` returns `value\tsource`
- [ ] Source labels include: `cli`, `env`, `workspace:<path>`, `repo-local`, `user-global`, `default`
- [ ] Resolution pipeline tracks provenance without losing source info

## Verification
- [ ] Set workspace value and confirm in `cai config list` with correct source
- [ ] Verify `~/.config/containai/config.toml` reflects changes

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
