# fn-31-gib.16 Add .priv. file filtering to import

## Description
Exclude `.bashrc.d/*.priv.*` files during import to prevent accidental secret leakage.

## Acceptance
- [ ] Import excludes files matching `*.priv.*` pattern in `.bashrc.d/`
- [ ] `--no-excludes` flag does NOT disable `.priv.` filtering (security requirement)
- [ ] Filtering applies to `--from <dir>` import path
- [ ] Filtering applies to `--from <tgz>` restore path
- [ ] Config option `import.exclude_priv` exists (default: true)
- [ ] Config option documented in config reference
- [ ] Test case: create `.bashrc.d/secrets.priv.sh`, run import, verify NOT synced
- [ ] Test case: same with `--no-excludes`, verify `.priv.` STILL not synced

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
