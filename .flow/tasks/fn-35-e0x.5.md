# fn-35-e0x.5 Create E2E test for Pi

## Description
Basic smoke test: verify Pi and Kimi symlinks work after build. Comprehensive sync testing is in fn-39-ua0.

**Size:** S
**Files:** None (verification only)

## Approach

```bash
# Start container
cai shell

# Verify symlinks exist and resolve
ls -la ~/.pi/agent/
ls -la ~/.kimi/
readlink ~/.pi/agent/settings.json
readlink ~/.kimi/config.toml

# Verify agents work
pi --version
kimi --version
```

## Key context

- This is a smoke test, not comprehensive testing
- Full E2E sync testing: fn-39-ua0
## Approach

Test from user perspective: build container, create mock HOME with test configs for all agents, run cai import/export, verify everything syncs correctly.

### Agents & Tools to Test

**AI Agents:**
| Agent | Config Location | Key Files |
|-------|-----------------|-----------|
| Claude Code | ~/.claude/ | .credentials.json (s), settings.json, plugins/, skills/, hooks/ |
| Gemini | ~/.gemini/ | google_accounts.json (s), oauth_creds.json (s), settings.json |
| Codex | ~/.codex/ | config.toml, auth.json (s), skills/ |
| Copilot | ~/.copilot/ | config.json, mcp-config.json, skills/ |
| OpenCode | ~/.config/opencode/ | opencode.json, auth.json (s), agents/, commands/ |
| Aider | ~/ | .aider.conf.yml, .aider.model.settings.yml |
| Continue | ~/.continue/ | config.yaml, config.json |
| Cursor | ~/.cursor/ | mcp.json, rules/, extensions/ |
| Pi | ~/.pi/agent/ | settings.json, models.json (s), skills/, extensions/ |
| Kimi | ~/.kimi/ | config.toml (s), mcp.json (s) |

**Dev Tools:**
| Tool | Config Location | Key Files |
|------|-----------------|-----------|
| Git | ~/ | .gitconfig, .gitignore_global |
| GitHub CLI | ~/.config/gh/ | hosts.yml (s), config.yml |
| SSH | ~/.ssh/ | config, known_hosts, id_* (s) |
| VS Code Server | ~/.vscode-server/ | extensions/, data/Machine/, data/User/mcp/ |
| tmux | ~/ | .tmux.conf, .config/tmux/, .local/share/tmux/ |
| vim/neovim | ~/ | .vimrc, .vim/, .config/nvim/ |
| Starship | ~/.config/ | starship.toml |
| Oh My Posh | ~/.config/ | oh-my-posh/ |

**Shell Customization:**
| Item | Location | Notes |
|------|----------|-------|
| .bashrc.d/ | ~/.bashrc.d/ | Custom shell scripts - MUST source on login |
| .bash_aliases | ~/ | Alias definitions |
| .zshrc | ~/ | Zsh config |
| .zprofile | ~/ | Zsh profile |
| .inputrc | ~/ | Readline config |
| .oh-my-zsh/custom | ~/ | Oh My Zsh customizations |

**Other:**
- ~/.agents/ - shared agent configuration
- ~/.local/share/fonts/ - custom fonts

### Test Categories

**1. Import Tests (host → container):**
- Each agent's config files sync correctly
- Secret files have 600 permissions in container
- Directories sync recursively
- Symlinks resolve to /mnt/agent-data/

**2. Export Tests (container → host):**
- Modified configs export back to host
- New files created in container export correctly
- Permissions preserved on export

**3. Shell Customization Tests:**
- .bashrc.d/ scripts sourced on container login
- Custom aliases available in container shell
- .inputrc readline bindings work

**4. Secret Handling:**
- `--no-secrets` excludes: .credentials.json, oauth_creds.json, auth.json, hosts.yml, id_*, models.json, config.toml (Kimi)
- Secret files get 600 permissions
- Non-secret files keep original permissions

**5. Flag Behavior:**
- `j` (json-init): Creates `{}` for missing JSON files
- `R` (remove): Cleans directory before sync
- `x` (exclude): Skips .system/ subdirectories
- `d` (directory): Recursive directory sync

**6. Dry-Run Tests:**
- `cai import --dry-run` shows what would sync
- `cai export --dry-run` shows what would export
- No actual changes made in dry-run

**7. Edge Cases:**
- Agent not installed on host (no config) → no empty dirs in container
- Partial config (some files exist, others don't)
- Concurrent container instances
- Large files (fonts directory)
- Broken symlinks handling

### Test Structure

```bash
#!/usr/bin/env bash
set -euo pipefail

# === Setup ===
setup_mock_home()      # Create temp HOME with mock configs for all agents
build_test_container() # Ensure image is built with all agents
start_test_container() # Start container with test- prefix

# === Agent Tests ===
test_claude_sync()
test_gemini_sync()
test_codex_sync()
test_copilot_sync()
test_opencode_sync()
test_aider_sync()
test_continue_sync()
test_cursor_sync()
test_pi_sync()
test_kimi_sync()

# === Tool Tests ===
test_git_sync()
test_gh_sync()
test_ssh_sync()
test_vscode_sync()
test_tmux_sync()
test_vim_sync()

# === Shell Tests ===
test_bashrc_d_sourced()  # Verify .bashrc.d scripts run on login
test_aliases_available() # Verify custom aliases work
test_inputrc_bindings()  # Verify readline config applied

# === Flag Tests ===
test_secret_flag()
test_json_init_flag()
test_remove_flag()
test_exclude_flag()
test_no_secrets_option()

# === Dry Run Tests ===
test_import_dry_run()
test_export_dry_run()

# === Edge Case Tests ===
test_no_config_no_pollution()
test_partial_config()
test_large_directory()

# === Cleanup ===
teardown()
```

## Key context

- Use temp directory as mock HOME, not user's actual config
- Pattern: `tests/integration/test-sync-integration.sh` for existing sync tests
- Test containers use `test-` prefix for cleanup
- SSH tests may need special handling (disabled by default in sync-manifest)
- VS Code Server tests only if installed in image
## Approach

Test the full sync system from user perspective: build container, create test scenarios with mock configs, run cai import/export, verify results.

### Sync Operations to Test

1. **Import** (`cai import`) - host → container
2. **Export** (`cai export`) - container → host
3. **Dry-run modes** (`--dry-run`) - verify without changes

### Flag Combinations to Test

| Flag | Meaning | Test Case |
|------|---------|-----------|
| `f` | file | Basic file sync |
| `d` | directory | Directory sync (recursive) |
| `s` | secret | Permissions (600), --no-secrets exclusion |
| `j` | json-init | Create empty `{}` if missing |
| `R` | remove existing | Clean directory before sync |
| `x` | exclude .system/ | Skip .system/ subdirs |
| `fj` | file + json-init | Config files |
| `fs` | file + secret | Credential files |
| `fjs` | file + json + secret | Secret configs |
| `dR` | dir + remove | Skills/extensions dirs |

### Test Scenarios

**Basic Sync:**
- File exists on host only → import → appears in container
- File exists in container only → export → appears on host
- File exists on both → verify correct direction wins

**Secret Handling (`s` flag):**
- Secret file synced with 600 permissions
- `cai import --no-secrets` skips secret files
- `cai export --no-secrets` skips secret files

**JSON Init (`j` flag):**
- File missing on host → container gets empty `{}`
- File exists on host → synced as-is (not overwritten with `{}`)

**Directory Sync (`d`, `dR` flags):**
- Directory with files → all contents synced
- `dR` flag → existing contents removed before sync
- Nested directories work correctly

**Edge Cases:**
- Symlink resolution in container
- File with spaces in name
- Empty directory handling
- Large file handling
- Permission preservation (non-secret files)
- Unicode in filenames/content

**Agent-Specific (Pi + Kimi):**
- Pi: settings.json, models.json (secret), skills/, extensions/
- Kimi: config.toml (secret), mcp.json (secret)
- No-config scenario: verify no pollution when user has no Pi/Kimi

### Test Structure

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-helpers.sh"

# Setup: Build container, create temp HOME with mock configs
setup_test_environment() { ... }

# Teardown: Clean containers, temp dirs
teardown_test_environment() { ... }

# Test groups
test_basic_import() { ... }
test_basic_export() { ... }
test_secret_handling() { ... }
test_json_init() { ... }
test_directory_sync() { ... }
test_dry_run() { ... }
test_pi_sync() { ... }
test_kimi_sync() { ... }
test_edge_cases() { ... }

# Run all tests
main() {
    setup_test_environment
    trap teardown_test_environment EXIT

    run_test_group "Basic Import" test_basic_import
    run_test_group "Basic Export" test_basic_export
    run_test_group "Secret Handling" test_secret_handling
    run_test_group "JSON Init" test_json_init
    run_test_group "Directory Sync" test_directory_sync
    run_test_group "Dry Run" test_dry_run
    run_test_group "Pi Sync" test_pi_sync
    run_test_group "Kimi Sync" test_kimi_sync
    run_test_group "Edge Cases" test_edge_cases

    print_summary
}
```

## Key context

- Use temp directory as mock HOME, not user's actual home
- Pattern: `tests/integration/test-sync-integration.sh` for existing sync tests
- Test containers use `test-` prefix for cleanup
- Mock configs should exercise all flag types
- Run `./src/build.sh` first to get image with Pi/Kimi entries
## Approach

Follow existing test patterns in `tests/integration/test-containai.sh`.

### Test Scenarios

**Pi Sync Tests:**
1. User has `~/.pi/agent/settings.json` on host → `cai import` → verify synced to container
2. User has `~/.pi/agent/models.json` (secret) → verify synced with correct permissions
3. User has `~/.pi/agent/skills/` directory → verify directory synced
4. User has `~/.pi/agent/extensions/` directory → verify directory synced
5. User has NO Pi config → verify no empty `.pi/` created in container
6. Verify `pi --version` works after sync

**Kimi Sync Tests:**
1. User has `~/.kimi/config.toml` on host → `cai import` → verify synced to container
2. User has `~/.kimi/mcp.json` (secret) → verify synced with correct permissions
3. User has NO Kimi config → verify no empty `.kimi/` created in container
4. Verify `kimi --version` works after sync

**Symlink Tests:**
1. Verify symlinks point to `/mnt/agent-data/pi/` and `/mnt/agent-data/kimi/`
2. Verify symlinks resolve correctly (not broken)
3. Verify agents can read config through symlinks

### Test Structure

```bash
#!/usr/bin/env bash
set -euo pipefail

# Setup: Build container, create temp test directory
# Scenario 1: Pi config sync
# Scenario 2: Kimi config sync
# Scenario 3: No config (verify no pollution)
# Scenario 4: Both configs together
# Teardown: Clean up test containers and temp dirs
```

## Key context

- Use `cai import` to sync configs from host to container
- Test containers should use test- prefix for cleanup
- Create mock config files in temp directory, not user's actual ~/.pi or ~/.kimi
- Pattern: `tests/integration/test-containai.sh` Scenario 4 (agent verification)
## Acceptance
- [ ] Pi symlinks exist in container
- [ ] Kimi symlinks exist in container
- [ ] pi --version works
- [ ] kimi --version works
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
