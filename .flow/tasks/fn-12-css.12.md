# fn-12-css.12 Delete scripts/install-containai-docker.sh

## Description

Remove the redundant `scripts/install-containai-docker.sh` script now that its functionality has been merged into `cai setup --docker` (task 11).

**Cleanup steps:**

1. Delete `scripts/install-containai-docker.sh`
2. Check for and update any references:
   - README.md mentions
   - Documentation references
   - CI/CD scripts
   - Makefile targets

**Files to check:**
- `README.md`
- `docs/setup-guide.md`
- `docs/quickstart.md`
- `.github/workflows/*.yml`
- `Makefile` (if exists)

**Update pattern:**
Replace references to `scripts/install-containai-docker.sh` with:
```
cai setup --docker
```

**Note:** Since nothing has shipped, there's no need for deprecation period or backwards compatibility. Just delete and update references.

## Acceptance

- [ ] `scripts/install-containai-docker.sh` is deleted
- [ ] No remaining references in documentation
- [ ] No remaining references in CI/CD
- [ ] `cai setup --docker` is the documented way to install

## Done summary
Superseded by fn-36-rb7 or fn-31-gib
## Evidence
- Commits:
- Tests:
- PRs:
