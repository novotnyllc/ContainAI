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
Added "Shell Functions" section to `docs/quickstart.md` providing convenient shell shortcuts.

## Changes

**docs/quickstart.md** - Added new section with:
- Function wrappers for `claude` and `gemini` agents (bash only)
- Usage examples showing how to invoke agents with quoted arguments
- Quoting requirements explanation (avoiding word splitting)
- Alternative configuration methods (CONTAINAI_AGENT env var, cai config)
- Note explaining why functions go in ~/.bashrc (ContainAI requires bash 4+)

## Deviations from Spec

The spec suggested `alias claude='cai run claude --'` syntax, but this doesn't work with the actual CLI API:
- `cai run <agent>` is not valid syntax (no positional agent argument)
- Agent selection uses `CONTAINAI_AGENT` env var or `cai config set agent.default`
- Functions with env var are the correct pattern: `claude() { CONTAINAI_AGENT=claude cai -- "$@"; }`
- Removed `codex` agent as it's not defined in `_CONTAINAI_AGENT_TAGS` (only claude/gemini supported)
- Changed from zsh to bash-only since ContainAI requires bash 4+ (per quickstart prerequisites)

## Acceptance Criteria Met

- [x] bash alias/function examples documented - Function wrappers for supported agents
- [x] Quoting requirements explained - Dedicated section with good/bad examples
- [x] Common workflow examples shown - Usage examples with realistic commands
## Evidence
- Commits: 932c08b (fixed version after review feedback)
- Tests: N/A (documentation-only task)
- PRs: N/A
