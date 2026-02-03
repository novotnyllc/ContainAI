# Configuration Examples

Copy-paste examples for common ContainAI setups. Each example includes a complete configuration file with inline comments explaining the settings.

## Examples Index

| Example | Use Case | Key Features |
|---------|----------|--------------|
| [multi-agent.toml](multi-agent.toml) | Teams using multiple AI agents | Separate volumes per agent, environment variables for different API keys |
| [custom-sync.toml](custom-sync.toml) | Adding custom dotfiles | Sync additional tool configs beyond defaults |
| [isolated-workspace.toml](isolated-workspace.toml) | Security-sensitive work | Minimal sync, no secrets, project isolation |
| [power-user.toml](power-user.toml) | VS Code Remote-SSH workflow | SSH agent forwarding, port forwarding, custom ports |
| [ci-ephemeral.toml](ci-ephemeral.toml) | CI/CD environments | No persistence, environment-based config |
| [team-shared.toml](team-shared.toml) | Shared repository setup | Workspace-checked config, network policies |

## How to Use

**Option 1: Workspace config (recommended for project-specific settings)**
```bash
mkdir -p .containai
cp docs/examples/isolated-workspace.toml .containai/config.toml
```

**Option 2: User config (for global defaults)**
```bash
mkdir -p ~/.config/containai
cp docs/examples/power-user.toml ~/.config/containai/config.toml
```

## Config Discovery

ContainAI discovers **one** config file (not merged):

1. Workspace config (`.containai/config.toml`) - checked first
2. User config (`~/.config/containai/config.toml`) - fallback if no workspace config

**Overrides** (apply regardless of which config is found):
- CLI flags: `--data-volume`, `--config`
- Environment: `CONTAINAI_AGENT`, `CONTAINAI_DATA_VOLUME`

See [Configuration Reference](../configuration.md) for the complete schema.

## Validation

After creating your config, verify it works:

```bash
cai doctor           # Check overall health
cai import --dry-run # Preview what will be synced
```

## Using Multiple Configs

ContainAI discovers a **single** config file by default (workspace `.containai/config.toml` is checked first, then user `~/.config/containai/config.toml`). To use settings from different examples:

**Option 1: Single user config with workspace overrides**
```bash
# Copy example to user config, then add [workspace."..."] sections
cp docs/examples/power-user.toml ~/.config/containai/config.toml
# Edit to add workspace-specific volume overrides
```

**Option 2: Separate workspace configs**
```bash
# Each project gets its own complete config
cp docs/examples/isolated-workspace.toml /path/to/project-a/.containai/config.toml
cp docs/examples/team-shared.toml /path/to/project-b/.containai/config.toml
```

**Note:** `[env]` and `[ssh]` sections are global and cannot vary per-workspace. Use `[workspace."path"]` only for `data_volume` and `excludes` overrides.
