# fn-34-fk5.12: Document handy aliases

## Goal
Add alias documentation to quickstart showing shell shortcuts.

## Content
```markdown
## Shell Aliases

For frequent agent usage, add aliases to your shell configuration:

### Bash/Zsh (~/.bashrc or ~/.zshrc)
```bash
alias claude='cai run claude --'
alias gemini='cai run gemini --'
alias codex='cai run codex --'
```

### Usage
```bash
claude "Fix the bug in main.py"
gemini "Explain this code"
```

### Important: Quoting
Always quote arguments with spaces or special characters:
```bash
# Good
claude "What does this function do?"

# Bad - splits into multiple arguments
claude What does this function do?
```
```

## Files
- `docs/quickstart.md`: Add "Shell Aliases" section

## Acceptance
- [x] bash/zsh alias examples documented
- [x] Quoting requirements explained
- [x] Common workflow examples shown

## Done summary
# fn-34-fk5.12: Document handy aliases

## Summary

Added "Shell Aliases" section to `docs/quickstart.md` providing convenient shell shortcuts for frequently used agents.

## Changes

**docs/quickstart.md** - Added new section:
- Function-based aliases for bash/zsh: `claude()`, `gemini()`, `codex()`
- Usage examples showing how to invoke agents with quoted arguments
- Quoting requirements explanation (avoiding word splitting)
- Alternative configuration methods (CONTAINAI_AGENT env var, cai config)

## Acceptance Criteria Met

- [x] bash/zsh alias examples documented - Added function aliases for both shells
- [x] Quoting requirements explained - Dedicated section showing good vs bad patterns
- [x] Common workflow examples shown - Usage examples with realistic commands

## Technical Notes

- Used function syntax instead of simple aliases for cleaner argument handling
- Aliases use CONTAINAI_AGENT env var which is the documented API
- The `--` separator passes remaining arguments to the agent
## Evidence
- Commits: 202e06a6c70ced61eecd3dc5bbc8976e43c9e29c
- Tests:
- PRs:
