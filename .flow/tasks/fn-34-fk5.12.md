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
- [ ] bash/zsh alias examples documented
- [ ] Quoting requirements explained
- [ ] Common workflow examples shown
