# fn-14-nm0.2 Refactor WSL2 setup for isolated Docker

## Description

Refactor `_cai_setup_wsl2()` to use a completely isolated Docker daemon with Sysbox. **Critical:** Detect and block WSL2 mirrored networking mode which is incompatible with our isolated Docker setup.

**Size:** M
**Files:** `src/lib/setup.sh`

## Current State

WSL2 setup (`setup.sh:844-931`) has been partially refactored but:
1. Does not detect WSL2 mirrored networking mode (breaks our setup)
2. Needs to block setup if mirrored mode is active
3. Should offer to fix by disabling mirrored mode (requires WSL restart)

## Approach

### Step 0: Detect WSL2 Mirrored Networking Mode (NEW - BLOCKING)

Before any setup, detect if WSL2 is running in mirrored networking mode:

**Detection strategy:**
```bash
_cai_detect_wsl2_mirrored_mode() {
    # Get Windows user profile path
    local win_userprofile
    win_userprofile=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')
    [[ -z "$win_userprofile" ]] && return 1  # Can't detect, assume OK

    # Convert to WSL path
    local wsl_userprofile
    wsl_userprofile=$(wslpath "$win_userprofile" 2>/dev/null)
    [[ -z "$wsl_userprofile" ]] && return 1

    local wslconfig="${wsl_userprofile}/.wslconfig"
    [[ ! -f "$wslconfig" ]] && return 1  # No config, default is NAT (OK)

    # Parse [wsl2] section for networkingMode=mirrored
    # Must handle: networkingMode=mirrored, networkingMode = mirrored, etc.
    if grep -qiE '^\s*networkingMode\s*=\s*mirrored' "$wslconfig" 2>/dev/null; then
        return 0  # Mirrored mode detected
    fi
    return 1  # Not mirrored
}
```

**If mirrored mode detected:**
1. Print clear error explaining mirrored mode is incompatible with ContainAI
2. Offer to fix: "Would you like to disable mirrored networking? This will require WSL to restart. (y/n)"
3. If yes:
   - Modify `.wslconfig` to comment out or change `networkingMode=mirrored` to `networkingMode=nat`
   - Run `wsl.exe --shutdown` to restart WSL
   - Print: "WSL has been shut down. Please restart your terminal and re-run `cai setup`."
   - Exit with specific code (e.g., 75 for "WSL restart required")
4. If no:
   - Print: "Cannot continue setup with mirrored networking mode. Please disable it manually and re-run setup."
   - Exit with error

**Why mirrored mode breaks us:** Mirrored networking changes how Docker networking works - the WSL2 VM shares Windows network interfaces directly, which conflicts with Docker's bridge networking and our isolated daemon's network configuration.

### Steps 1-5: Existing isolated Docker setup (already implemented)

1. Clean up legacy paths (`_cai_cleanup_legacy_paths()`)
2. Create isolated directories
3. Create isolated daemon.json at `/etc/containai/docker/daemon.json`
4. Create isolated systemd service at `/etc/systemd/system/containai-docker.service`
5. Start isolated Docker service, create context, verify

**Reuse existing functions:**
- `_cai_create_isolated_daemon_json()`
- `_cai_create_isolated_docker_service()`
- `_cai_create_isolated_docker_dirs()`
- `_cai_start_isolated_docker_service()`
- `_cai_create_isolated_docker_context()`
- `_cai_verify_isolated_docker()`

## Key Context

- **WSL2 .wslconfig location:** `%USERPROFILE%\.wslconfig` on Windows, accessed via `cmd.exe /c "echo %USERPROFILE%"` + `wslpath`
- **Mirrored mode setting:** `networkingMode=mirrored` under `[wsl2]` section
- **WSL restart:** `wsl.exe --shutdown` shuts down all WSL instances; user must restart terminal
- **No fallback:** Sysbox is required, mirrored mode is a hard blocker
- Ref: [Microsoft WSL networking docs](https://learn.microsoft.com/en-us/windows/wsl/networking)

## Acceptance

- [ ] **`_cai_detect_wsl2_mirrored_mode()` function exists and works**
- [ ] **Setup fails early if mirrored mode detected**
- [ ] **User is offered the choice to disable mirrored mode**
- [ ] **If user accepts, .wslconfig is modified and WSL is shut down**
- [ ] **Clear messaging about needing to restart terminal and re-run setup**
- [ ] `_cai_setup_wsl2()` creates `/etc/containai/docker/daemon.json`
- [ ] `_cai_setup_wsl2()` creates unit file at `/etc/systemd/system/containai-docker.service`
- [ ] `_cai_setup_wsl2()` never adds to `/etc/docker/daemon.json`
- [ ] Isolated Docker uses socket at `$_CAI_CONTAINAI_DOCKER_SOCKET`
- [ ] Context created as `$_CAI_CONTAINAI_DOCKER_CONTEXT`
- [ ] `cai setup --dry-run` on WSL2 shows mirrored mode check
- [ ] **Running `cai setup` twice is idempotent**

## Done summary

TBD

## Evidence

- Commits:
- Tests:
- PRs:
