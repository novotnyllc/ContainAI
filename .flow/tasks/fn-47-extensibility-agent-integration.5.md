# fn-47-extensibility-agent-integration.5 Skills Plugin - Create containai-skills plugin with CLI documentation

## Description

Create a Claude Code skills plugin that teaches AI agents how to use the ContainAI CLI effectively. Agents running inside ContainAI containers (or orchestrating them from outside) can use these skills to understand available commands.

### Plugin Structure

```
containai-skills/
├── plugin.json
├── README.md
└── skills/
    ├── containai-overview.md      # What is ContainAI, when to use it
    ├── containai-quickstart.md    # Start a sandbox, run commands, stop
    ├── containai-lifecycle.md     # run, shell, exec, stop, status, gc
    ├── containai-sync.md          # import, export, sync operations
    ├── containai-setup.md         # doctor, setup, validate
    ├── containai-customization.md # templates, hooks, network config
    └── containai-troubleshooting.md # Common errors and solutions
```

### Skill Content Guidelines

Each skill should include:
1. **When to use** - Trigger phrases for the skill
2. **Key commands** - Actual CLI commands with examples
3. **Common patterns** - Typical workflows
4. **Gotchas** - Things that trip people up

Example content for `containai-quickstart.md`:
```markdown
# ContainAI Quickstart

Use this skill when: starting a sandbox, running commands in isolation

## Start a sandbox
\`\`\`bash
cai run                    # Start/attach in current workspace
cai run --detached         # Start in background
cai run --workspace /path  # Specific workspace
\`\`\`

## Run commands
\`\`\`bash
cai exec -- npm test       # Run single command
cai shell                  # Interactive shell
\`\`\`

## Stop
\`\`\`bash
cai stop                   # Stop current workspace container
cai stop --all             # Stop all containers
\`\`\`
```

### Plugin Metadata

`plugin.json`:
```json
{
  "name": "containai-skills",
  "version": "1.0.0",
  "description": "Skills for using ContainAI sandboxed containers",
  "skills": [
    { "name": "containai-overview", "path": "skills/containai-overview.md" },
    { "name": "containai-quickstart", "path": "skills/containai-quickstart.md" },
    ...
  ]
}
```

### Distribution

- Publish to Claude Code plugin registry (if available)
- Or include in ContainAI repo under `plugins/containai-skills/`
- Users install via: `claude plugins install containai-skills`

## Acceptance

- [ ] Plugin structure follows Claude Code plugin conventions
- [ ] 5+ skills covering all major CLI commands
- [ ] Each skill has clear trigger phrases
- [ ] Commands include realistic examples
- [ ] Troubleshooting skill covers common errors
- [ ] Plugin installable and functional
- [ ] README explains installation and usage

## Done summary
Created containai-skills Claude Code plugin with 7 skills covering all major CLI commands. Plugin includes overview, quickstart, lifecycle, sync, setup, customization, and troubleshooting skills with clear trigger phrases, realistic examples, and common gotchas.
## Evidence
- Commits: fd800b8, c890053, f953621, a07293e, e9f2be5
- Tests:
- PRs:
