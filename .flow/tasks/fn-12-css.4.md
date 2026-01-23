# fn-12-css.4 Add import prompting for new volumes

## Description

When ContainAI creates a new data volume, prompt the user whether to import host configs before starting. This provides a better first-run experience while respecting automation needs.

**Prompt flow:**

1. Detect that this is a new volume (doesn't exist in Docker yet)
2. If interactive terminal (`[ -t 0 ]`) and `import.auto_prompt` is true (default):
   - Display: "New volume 'containai-myapp-data' will be created."
   - Prompt: "Import host configs to volume? [Y/n]: "
   - Y/enter: Run import before container start
   - n: Skip import, proceed with empty volume
3. If non-interactive or `--no-prompt`: skip prompt, no import

**Implementation location:**
- Add to container creation flow in `_containai_start_container()`
- Check for volume existence before `docker volume create`
- Insert prompt and optional import call

**Config key:**
```toml
[import]
auto_prompt = true  # Default: prompt on new volume
```

**CLI override:**
- `--no-prompt` flag on `cai run`, `cai shell`, `cai exec`
- Disables prompt for that invocation regardless of config

**Edge cases:**
- Non-interactive (cron, scripts): never prompt, no import
- Volume already exists: no prompt (not new)
- Import fails: show error but continue with container creation
- User presses Ctrl-C at prompt: abort command

## Acceptance

- [ ] First `cai shell` on new workspace prompts for import (interactive)
- [ ] Answering Y runs import before container starts
- [ ] Answering n skips import, creates empty volume
- [ ] `--no-prompt` flag skips prompt entirely
- [ ] Non-interactive shells never prompt
- [ ] Second `cai shell` (volume exists) does not prompt
- [ ] `import.auto_prompt = false` in config disables prompt

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
