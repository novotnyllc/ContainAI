# fn-33-lp4.1 Define template directory structure

## Description
Create directory structure helper in `src/lib/template.sh`. Use `~/.config/containai` (matching existing `_CAI_CONFIG_DIR` in ssh.sh). Define constants for template paths and provide functions to get/create template directories. Update `src/containai.sh` to source the new library.

## Acceptance
- [ ] `src/lib/template.sh` created with proper header and guard
- [ ] `_CAI_TEMPLATE_DIR` constant defined as `~/.config/containai/templates`
- [ ] `_cai_get_template_path()` function returns path to template Dockerfile
- [ ] `_cai_ensure_template_dir()` function creates template directory if missing
- [ ] `src/containai.sh` sources `lib/template.sh`
- [ ] `_containai_libs_exist` check updated to include template.sh
- [ ] Unit tests pass for path resolution

## Done summary
Created `src/lib/template.sh` with template directory structure management:
- Defined `_CAI_TEMPLATE_DIR` constant at `~/.config/containai/templates`
- Implemented `_cai_get_template_dir()`, `_cai_get_template_path()`, `_cai_ensure_template_dir()`, and `_cai_template_exists()` functions
- Updated `src/containai.sh` to include template.sh in libs check and source it
- All functions follow existing codebase patterns (source guards, printf, local variables)
- shellcheck passes, unit tests verify path resolution
## Evidence
- Commits:
- Tests: Unit tests for path resolution functions passed (6/6)
- PRs:
