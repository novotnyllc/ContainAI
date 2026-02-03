# ContainAI Skills Plugin

A Claude Code skills plugin that teaches AI agents how to use the ContainAI CLI effectively. This plugin provides comprehensive documentation for AI agents running inside ContainAI containers or orchestrating them from outside.

## Installation

### From ContainAI Repository

If you have ContainAI cloned locally:

```bash
claude plugins install ./plugins/containai-skills
```

### From npm (if published)

```bash
claude plugins install containai-skills
```

## Available Skills

| Skill | Description | When to Use |
|-------|-------------|-------------|
| `containai-overview` | What ContainAI is, concepts, safety model | Learning about ContainAI, explaining sandbox benefits |
| `containai-quickstart` | Start a sandbox, run commands, stop | First-time setup, quick tasks |
| `containai-lifecycle` | run, shell, exec, stop, status, gc | Managing container state |
| `containai-sync` | import, export, sync operations | Data persistence, backups, config sync |
| `containai-setup` | doctor, setup, validate | System setup, diagnostics |
| `containai-customization` | Templates, hooks, network config | Custom container configurations |
| `containai-troubleshooting` | Common errors and solutions | When things go wrong |

## Usage

Once installed, AI agents can invoke skills like:

```
/containai-quickstart
/containai-lifecycle
/containai-troubleshooting
```

Or reference them in conversation:

```
I need help starting a ContainAI sandbox for my project.
```

The agent will automatically use the relevant skill to provide accurate CLI guidance.

## Skill Content Structure

Each skill follows a consistent format:

1. **When to use** - Trigger phrases and scenarios
2. **Key commands** - Actual CLI commands with examples
3. **Common patterns** - Typical workflows and best practices
4. **Gotchas** - Things that trip people up

## Requirements

- Claude Code (or compatible agent with skills support)
- ContainAI installed and configured on the host system
- Docker with Sysbox runtime (see `cai doctor` for setup)

## Development

To modify skills or add new ones:

1. Edit markdown files in `skills/`
2. Update `plugin.json` to register new skills
3. Reinstall the plugin: `claude plugins install ./plugins/containai-skills --force`

## License

Same license as ContainAI (see repository root).
