# fn-49-devcontainer-integration.1 Implement cai-docker wrapper

## Description

Create the smart docker wrapper (`cai-docker`) that detects ContainAI devcontainers and routes them to the sysbox runtime context.

### Location
`src/devcontainer/cai-docker` (shell script)

### Core Functions

1. **Devcontainer detection**: Parse `--workspace-folder` arg, find `devcontainer.json`
2. **ContainAI marker detection**: Check for `containai` in feature references
3. **Data volume injection**: Add `-v containai-data-<name>:/mnt/agent-data:rw` to run/create
4. **Label injection**: Add `containai.type`, `containai.workspace`, `containai.created`
5. **User injection**: Add `-u agent` for ContainAI images (unless devcontainer specifies user)
6. **SSH config management**: Update `~/.ssh/config` with host alias for workspace
7. **Context routing**: Exec to `docker --context containai-docker`

### Key Functions

See epic spec for full implementation. Key elements:
- `find_devcontainer_json()` - locate devcontainer.json
- `is_containai_devcontainer()` - check for containai marker
- `get_data_volume_name()` - extract or derive volume name
- `inject_containai_args()` - insert volume mount, labels, and user flag
- `update_ssh_config()` - manage SSH host entries
- `is_containai_image()` - check if image is a ContainAI image
- `get_devcontainer_user()` - extract remoteUser/containerUser from devcontainer.json

### User Injection Logic

When running a ContainAI image, inject `-u agent` unless the devcontainer specifies a different user:

```bash
# Check if devcontainer.json specifies a user
get_devcontainer_user() {
    local config="$1"
    # Check remoteUser first, then containerUser
    local user
    user=$(jq -r '.remoteUser // .containerUser // empty' "$config" 2>/dev/null)
    echo "$user"
}

# Check if image is ContainAI
is_containai_image() {
    local image="$1"
    [[ "$image" == *"containai"* ]] || [[ "$image" == "ghcr.io/novotnyllc/containai"* ]]
}

# In inject_containai_args():
if is_containai_image "$image"; then
    local specified_user
    specified_user=$(get_devcontainer_user "$config")
    if [[ -z "$specified_user" ]]; then
        args+=("-u" "agent")
    fi
fi
```

**Precedence**:
1. If `remoteUser` set in devcontainer.json → use that (no injection)
2. If `containerUser` set in devcontainer.json → use that (no injection)
3. If ContainAI image and no user specified → inject `-u agent`
4. If not ContainAI image → no injection (let image default apply)

### Installation Path
- `~/.local/bin/cai-docker` (installed by `cai setup`)

## Acceptance

- [ ] Detects ContainAI marker in devcontainer.json (with/without JSONC comments)
- [ ] Routes to `containai-docker` context when marker found
- [ ] Passes through to regular docker when no marker
- [ ] Injects data volume mount if volume exists
- [ ] Adds containai labels for GC integration
- [ ] Injects `-u agent` for ContainAI images when no user specified in devcontainer.json
- [ ] Respects `remoteUser`/`containerUser` from devcontainer.json (no `-u` injection)
- [ ] Updates ~/.ssh/config with workspace SSH alias
- [ ] Works with VS Code Dev Containers extension

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
