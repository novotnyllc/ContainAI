# fn-12-css.3 Implement cai exec one-shot command

## Description

Add a new `cai exec <command> [args...]` subcommand for one-shot command execution. This enables scripts and automation to run commands in containers without managing lifecycle manually.

**Command signature:**
```
cai exec [options] <command> [args...]
```

**Options:**
- `--no-prompt` - Skip import prompt (for automation)
- `--workspace <path>` - Override workspace detection
- `--data-volume <name>` - Override volume (same as run/shell)
- `--dry-run` - Show what would be done without executing

**Behavior:**

1. **Container lifecycle:**
   - Auto-create container if it doesn't exist (same as `cai shell`)
   - Auto-start container if stopped
   - Does NOT stop container after command (leave running for next exec)

2. **Command execution:**
   - Execute via SSH (reuse existing SSH infrastructure from shell)
   - Stream stdout/stderr to caller in real-time
   - Return command's exit code as cai's exit code

3. **Import prompting:**
   - On new volume creation, prompt "Import host configs? [Y/n]"
   - Skip prompt if `--no-prompt` flag or non-interactive (`[ -t 0 ]` false)
   - Controlled by `import.auto_prompt` config

**Examples:**
```bash
# Run single command
cai exec echo "Hello from container"

# Run with args
cai exec ls -la /workspace

# Non-interactive (automation)
cai exec --no-prompt npm test

# Explicit workspace
cai exec --workspace /path/to/project make build
```

## Acceptance

- [ ] `cai exec echo hello` returns "hello" and exit code 0
- [ ] `cai exec false` returns exit code 1
- [ ] `cai exec --no-prompt <cmd>` skips import prompt
- [ ] Container is auto-created if missing
- [ ] Container is auto-started if stopped
- [ ] stdout/stderr are streamed properly
- [ ] Works in non-interactive environment (no TTY)

## Done summary
Superseded by fn-36-rb7 or fn-31-gib
## Evidence
- Commits:
- Tests:
- PRs:
