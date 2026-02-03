# fn-49-devcontainer-integration.9 VS Code server-env-setup scripts

## Description

Create VS Code Server environment setup scripts that export `DOCKER_CONFIG` to use the ContainAI Docker configuration.

### Problem

When VS Code Remote (Server) connects to a devcontainer or remote machine, it needs to use the ContainAI Docker configuration instead of the default `~/.docker/`. VS Code Server sources `server-env-setup` scripts before launching, making this the ideal hook point.

### Scripts to Create

**`~/.vscode-server/server-env-setup`**:
```bash
#!/bin/bash
# ContainAI: Use isolated Docker config with correct context socket paths
export DOCKER_CONFIG="$HOME/.docker-cai"
```

**`~/.vscode-insiders/server-env-setup`**:
```bash
#!/bin/bash
# ContainAI: Use isolated Docker config with correct context socket paths
export DOCKER_CONFIG="$HOME/.docker-cai"
```

### Implementation

**Location**: Add to `src/lib/devcontainer.sh`

### Core Functions

1. **`_cai_install_vscode_server_env_setup()`**
   - Creates both scripts
   - Sets executable permission (`chmod +x`)
   - Creates parent directories if needed
   - Idempotent (safe to run multiple times)

2. **`_cai_remove_vscode_server_env_setup()`**
   - Removes the scripts (for uninstall)
   - Only removes if it's our script (check for ContainAI marker comment)

3. **`_cai_doctor_vscode_server_env()`**
   - Checks if scripts exist and are executable
   - Verifies they contain the correct DOCKER_CONFIG export
   - Reports status in `cai doctor` output

### Script Requirements

- Must be `chmod +x` (executable)
- Must be owned by the user
- Uses `#!/bin/bash` shebang (VS Code Server expects this)
- Single export statement for simplicity
- Contains marker comment for identification

### Integration Points

1. **`cai setup`**: Calls `_cai_install_vscode_server_env_setup()`
2. **Devcontainer feature `init.sh`**: Creates scripts inside container
3. **`cai doctor`**: Verifies scripts exist and are correct

### Directory Creation

Both directories may not exist on fresh systems:
```bash
mkdir -p ~/.vscode-server
mkdir -p ~/.vscode-insiders
```

### Edge Cases

1. **Script already exists with different content**:
   - Check if our marker comment is present
   - If yes: overwrite (update)
   - If no: append our export (preserve user's customizations)

2. **VS Code Server not installed**:
   - Still create scripts (they'll be ready when VS Code connects)
   - No error, just informational message

3. **Permissions issues**:
   - Scripts must be in user's home directory
   - Should work even if run as different user in container

### Doctor Output

```
Devcontainer support:
  ✓ cai-docker wrapper installed
  ✓ containai-docker context exists
  ✓ Docker context sync configured
  ✓ VS Code server-env-setup scripts installed
    - ~/.vscode-server/server-env-setup (executable)
    - ~/.vscode-insiders/server-env-setup (executable)
```

## Acceptance

- [ ] `~/.vscode-server/server-env-setup` created with correct content
- [ ] `~/.vscode-insiders/server-env-setup` created with correct content
- [ ] Both scripts are executable (`chmod +x`)
- [ ] Scripts export `DOCKER_CONFIG="$HOME/.docker-cai"`
- [ ] Parent directories created if missing
- [ ] Idempotent (running twice is safe)
- [ ] `cai doctor` verifies scripts
- [ ] Works in devcontainer feature `init.sh`
- [ ] Handles existing scripts gracefully (append vs overwrite)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
