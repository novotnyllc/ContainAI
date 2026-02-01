# fn-33-lp4.3 Implement template installation during setup

## Description
Copy template files from repo to user's config directory during `cai setup`. Also trigger copy on first use if templates are missing. Don't overwrite if user has customized.

## Acceptance
- [ ] `cai setup` copies `src/templates/*.Dockerfile` to `~/.config/containai/templates/*/Dockerfile`
- [ ] Installation skips if template already exists (preserve user customizations)
- [ ] First-use detection triggers install for missing default template
- [ ] First-use detection triggers install for missing example-ml template
- [ ] `cai setup --skip-templates` option to skip template installation
- [ ] Installation logs what it copies with `_cai_info()`

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
