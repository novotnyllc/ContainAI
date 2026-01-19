# ContainAI Secure Sandboxed Agent Runtime

## Overview

Secure CLI wrapper for AI coding agents in Docker Sandboxes.

## Platform Support

| Platform | `cai setup` Sysbox Support |
|----------|---------------------------|
| Linux (Ubuntu/Debian) | **Full** - Auto-install |
| Linux (Fedora/RHEL/Arch) | **Manual** - Guidance only |
| WSL2 (with systemd) | **Full** - Dedicated dockerd |
| WSL2 (without systemd) | **Not supported** |
| macOS | **N/A** - Use ECI instead |
| Windows (native) | **Not supported** |

## Requirements Hierarchy

| Requirement | Level |
|-------------|-------|
| Docker Sandbox OR Sysbox | **Hard** (one required) |
| `--label` support | **Hard** |

## Execution Modes

ContainAI supports two mutually exclusive execution modes:

| Mode | Context | Isolation | Command |
|------|---------|-----------|---------|
| **Sandbox** | `default` (Docker Desktop) | ECI | `docker sandbox run` |
| **Sysbox** | `containai-secure` | Sysbox | `docker run --runtime=sysbox-runc` |

**Note:** `docker sandbox` is a Docker Desktop feature. The `containai-secure` context uses standalone dockerd with Sysbox and regular `docker run`.

**Mode selection:**
- `--context containai-secure` → Sysbox mode (requires `cai setup`)
- `--context default` or unset → Sandbox mode (Docker Desktop)

## Agent Image Mapping

| Agent | Repo |
|-------|------|
| claude | `docker/sandbox-templates` |
| gemini | `docker/sandbox-templates` |

| Agent | Default Tag |
|-------|-------------|
| claude | `claude-code` |
| gemini | `gemini-cli` |

**Tag precedence:** `--image-tag` > `CONTAINAI_AGENT_TAG` > agent default tag

**Image construction:** `${REPO}:${TAG}` (never string surgery on existing tag)

## Config Discovery

**Exit codes:**
- 0: Config found
- 1: No config (use defaults)
- 2: Explicit config missing (fatal, error already printed)

```bash
_cai_find_config() {
    local workspace="${1:-$(pwd)}"
    local explicit_config="${2:-}"
    
    # Validate workspace first
    [[ -d "$workspace" ]] || {
        echo "[ERROR] Workspace not found: $workspace" >&2
        return 2
    }
    
    # 1. Explicit --config
    if [[ -n "$explicit_config" ]]; then
        [[ -f "$explicit_config" ]] || {
            echo "[ERROR] Config not found: $explicit_config" >&2
            return 2
        }
        echo "$explicit_config"
        return 0
    fi
    
    # 2. CONTAINAI_CONFIG env
    if [[ -n "${CONTAINAI_CONFIG:-}" ]]; then
        [[ -f "$CONTAINAI_CONFIG" ]] || {
            echo "[ERROR] CONTAINAI_CONFIG not found: $CONTAINAI_CONFIG" >&2
            return 2
        }
        echo "$CONTAINAI_CONFIG"
        return 0
    fi
    
    # 3. Walk up to git root or / (per fn-4-vet spec)
    local dir="$workspace"
    local git_root=""
    if command -v git >/dev/null 2>&1; then
        git_root=$(cd "$workspace" && git rev-parse --show-toplevel 2>/dev/null) || true
    fi

    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/.containai/config.toml" ]] && {
            echo "$dir/.containai/config.toml"
            return 0
        }
        # Stop at git root to avoid picking configs from outside repo
        [[ -n "$git_root" && "$dir" == "$git_root" ]] && break
        dir=$(dirname "$dir")
    done
    
    # 4. User config (XDG)
    local user_config="${XDG_CONFIG_HOME:-$HOME/.config}/containai/config.toml"
    [[ -f "$user_config" ]] && { echo "$user_config"; return 0; }
    
    return 1  # No config
}
```

## Volume Resolution

```bash
_cai_resolve_volume() {
    local workspace="${1:-$(pwd)}"
    local explicit_config="${2:-}"
    local data_volume="${3:-}"
    
    # 1. Explicit --data-volume
    [[ -n "$data_volume" ]] && { echo "$data_volume"; return 0; }
    
    # 2. CONTAINAI_DATA_VOLUME env
    [[ -n "${CONTAINAI_DATA_VOLUME:-}" ]] && { echo "$CONTAINAI_DATA_VOLUME"; return 0; }
    
    # 3. Config file
    local config_path find_rc
    config_path=$(_cai_find_config "$workspace" "$explicit_config" 2>&1)
    find_rc=$?
    
    case $find_rc in
        0)
            # Check Python availability and version
            # Config parsing requires Python 3.11+ (tomllib) or tomli package
            if ! command -v python3 >/dev/null 2>&1; then
                echo "[ERROR] Config found but Python 3 unavailable" >&2
                echo "[ERROR] Install python3 or pass --data-volume" >&2
                return 1
            fi
            # Check for tomllib (3.11+) or tomli
            if ! python3 -c "
try:
    import tomllib
except ImportError:
    try:
        import tomli
    except ImportError:
        exit(1)
" 2>/dev/null; then
                echo "[ERROR] Python TOML support unavailable" >&2
                echo "[ERROR] Python 3.11+ required, or install: pip install tomli" >&2
                return 1
            fi
            local result
            result=$(_cai_parse_config_volume "$workspace" "$config_path") || {
                echo "[ERROR] Config parse failed" >&2
                return 1
            }
            echo "${result:-sandbox-agent-data}"
            ;;
        1)
            echo "sandbox-agent-data"
            ;;
        2)
            # Error already printed by _cai_find_config, propagate it
            echo "$config_path" >&2  # Contains error message
            return 1
            ;;
    esac
}
```

## Sandbox Error Classification (shared)

Reusable function for consistent error handling in both preflight and doctor:

```bash
# Returns: ok, not_available, disabled, unknown
# Sets: SANDBOX_MSG with actionable message
_cai_classify_sandbox_error() {
    local output="$1"
    local rc="$2"

    # Success: rc==0 is ideal
    if [[ $rc -eq 0 ]]; then
        SANDBOX_MSG="[OK]"
        echo "ok"
        return
    fi

    # rc!=0 from here - classify the error

    # Command not available (sandbox subcommand doesn't exist)
    if echo "$output" | grep -qiE "not a docker command|unknown command|is not a docker command"; then
        SANDBOX_MSG="[ERROR] Command not available - install Docker Desktop 4.50+"
        echo "not_available"
        return
    fi

    # Feature disabled (command exists but feature off)
    if echo "$output" | grep -qiE "feature.*disabled|experimental|not enabled"; then
        SANDBOX_MSG="[ERROR] Feature disabled - enable in Docker Desktop Settings > Features in development"
        echo "disabled"
        return
    fi

    # Special case: explicit empty-list messages with non-zero rc
    # Return "empty" to signal "no sandboxes but with non-zero rc"
    # Callers can decide how to handle (warn vs fail-open)
    # This aligns with agent-sandbox/aliases.sh behavior
    if echo "$output" | grep -qiE "^no sandboxes$|no sandboxes found|0 sandboxes|sandbox list is empty"; then
        SANDBOX_MSG="[WARN] No sandboxes (rc=$rc - unusual)"
        echo "empty"
        return
    fi

    # Empty output with non-zero rc is suspicious - treat as unknown
    # (matches agent-sandbox/aliases.sh behavior)

    # Unknown error
    SANDBOX_MSG="[ERROR] Check failed (rc=$rc): $output"
    echo "unknown"
}
```

## Preflight Checks

```bash
_cai_preflight() {
    local ctx="${OPT_CONTEXT:-${DOCKER_CONTEXT:-default}}"

    command -v docker >/dev/null 2>&1 || { echo "[ERROR] Docker not found"; return 1; }

    # Validate context is honored by sandbox command
    # Only allow: "default" (Docker Desktop) or "containai-secure" (our dedicated daemon)
    # Other contexts are risky because sandbox may not honor them
    if [[ "$ctx" != "default" && "$ctx" != "containai-secure" ]]; then
        echo "[WARN] Context '$ctx' is not verified for sandbox operations" >&2
        echo "[WARN] Use 'default' (Docker Desktop) or 'containai-secure' (after cai setup)" >&2
    fi

    # For containai-secure, check socket FIRST (provides actionable error message)
    # Then verify docker connectivity and Sysbox runtime
    if [[ "$ctx" == "containai-secure" ]]; then
        local socket="/var/run/containai-docker.sock"
        # Socket check first - actionable error message
        if [[ ! -S "$socket" ]]; then
            echo "[ERROR] ContainAI Docker socket not found at $socket" >&2
            echo "[ERROR] Run 'cai setup' first to configure the secure context" >&2
            return 1
        fi
        # Now check docker connectivity
        if ! docker --context "$ctx" info >/dev/null 2>&1; then
            echo "[ERROR] Cannot connect to ContainAI Docker daemon" >&2
            echo "[ERROR] Check if containai-docker.service is running" >&2
            return 1
        fi
        # Verify Sysbox runtime is available
        if ! docker --context "$ctx" info 2>/dev/null | grep -q "sysbox-runc"; then
            echo "[ERROR] Sysbox runtime not found on containai-secure context" >&2
            return 1
        fi
        return 0  # Skip sandbox checks for Sysbox mode
    fi

    # For other contexts, check docker connectivity
    docker --context "$ctx" info >/dev/null 2>&1 || {
        echo "[ERROR] Cannot connect to Docker context '$ctx'"
        return 1
    }

    # Sandbox mode (Docker Desktop): check sandbox availability
    local output rc classification
    output=$(docker --context "$ctx" sandbox ls 2>&1)
    rc=$?
    classification=$(_cai_classify_sandbox_error "$output" "$rc")

    case "$classification" in
        ok) : ;;  # Success
        empty)
            # "empty" means no sandboxes but with unusual rc - warn but proceed
            echo "[WARN] $SANDBOX_MSG" >&2
            ;;
        *)
            echo "$SANDBOX_MSG" >&2
            return 1
            ;;
    esac

    if ! docker --context "$ctx" sandbox run --help 2>&1 | grep -q '\-\-label'; then
        echo "[ERROR] --label not supported - upgrade Docker Desktop" >&2
        return 1
    fi

    return 0
}

# Image check (called after image is resolved in cai run)
_cai_check_image() {
    local ctx="$1"
    local image="$2"

    if ! docker --context "$ctx" image inspect "$image" >/dev/null 2>&1; then
        echo "[ERROR] Image not found: $image" >&2
        # Include context in pull instruction (important for Sysbox mode)
        if [[ "$ctx" == "default" ]]; then
            echo "[INFO] Pull the image with: docker pull $image" >&2
        else
            echo "[INFO] Pull the image with: docker --context $ctx pull $image" >&2
        fi
        return 1
    fi
    return 0
}
```

## `cai doctor` Command

Checks system capabilities and reports status of both execution modes.

**Per Requirements Hierarchy:** Docker Sandbox OR Sysbox is the hard requirement - doctor passes if EITHER is viable. Always checks both modes to give a complete picture.

```bash
_cai_doctor() {
    local ctx="${OPT_CONTEXT:-${DOCKER_CONTEXT:-default}}"
    local sandbox_ok=false sysbox_ok=false
    local sandbox_msg sysbox_msg label_msg

    echo "ContainAI Doctor"
    echo "================"
    echo "Requested context: $ctx"
    echo ""

    # === Check Docker availability ===
    if ! command -v docker >/dev/null 2>&1; then
        echo "[ERROR] Docker not found"
        echo "[INFO] Install Docker Desktop from: https://www.docker.com/products/docker-desktop/"
        echo "[INFO] Or install Docker Engine: https://docs.docker.com/engine/install/"
        return 1
    fi
    echo "Docker CLI:     [OK]"
    echo ""

    # === Check Sandbox mode (Docker Desktop on default context) ===
    echo "--- Sandbox Mode (Docker Desktop) ---"
    local output rc classification
    output=$(docker --context default sandbox ls 2>&1)
    rc=$?
    classification=$(_cai_classify_sandbox_error "$output" "$rc")
    sandbox_msg="$SANDBOX_MSG"

    case "$classification" in
        ok) sandbox_ok=true ;;
        empty)
            # "empty" means no sandboxes but with unusual rc - warn but consider OK
            sandbox_ok=true
            echo "[WARN] Sandbox feature may have issues (check rc=$rc)" >&2
            ;;
    esac

    echo "Sandbox:        $sandbox_msg"

    # Check label support for sandbox mode
    if [[ "$sandbox_ok" == "true" ]]; then
        if docker --context default sandbox run --help 2>&1 | grep -q '\-\-label'; then
            label_msg="[OK]"
        else
            label_msg="[ERROR] Not supported - upgrade Docker Desktop"
            sandbox_ok=false
        fi
        echo "Label support:  $label_msg"
    fi

    echo ""

    # === Check Sysbox mode (containai-secure context) ===
    echo "--- Sysbox Mode (containai-secure) ---"
    local socket="/var/run/containai-docker.sock"

    if [[ ! -S "$socket" ]]; then
        sysbox_msg="[NOT CONFIGURED] Socket not found at $socket"
        echo "Sysbox:         $sysbox_msg"
        echo "[INFO] Run 'cai setup' to configure Sysbox mode"
    elif ! docker --context containai-secure info >/dev/null 2>&1; then
        sysbox_msg="[ERROR] Cannot connect to ContainAI Docker daemon"
        echo "Sysbox:         $sysbox_msg"
    elif ! docker --context containai-secure info 2>/dev/null | grep -q "sysbox-runc"; then
        sysbox_msg="[ERROR] Sysbox runtime not available"
        echo "Sysbox:         $sysbox_msg"
        echo "[INFO] Run 'cai setup' to install Sysbox"
    else
        sysbox_ok=true
        sysbox_msg="[OK] Sysbox runtime available"
        echo "Sysbox:         $sysbox_msg"
    fi

    echo ""

    # === Summary ===
    echo "--- Summary ---"
    if [[ "$sandbox_ok" == "true" && "$sysbox_ok" == "true" ]]; then
        echo "[OK] Both modes available"
        echo "  - Sandbox mode: cai run (or --context default)"
        echo "  - Sysbox mode:  cai --context containai-secure run"
    elif [[ "$sandbox_ok" == "true" ]]; then
        echo "[OK] Sandbox mode available (Sysbox not configured)"
        echo "  - Use: cai run"
        echo "  - For enhanced isolation, run: cai setup"
    elif [[ "$sysbox_ok" == "true" ]]; then
        echo "[OK] Sysbox mode available (Sandbox not available)"
        echo "  - Use: cai --context containai-secure run"
    else
        echo "[ERROR] No execution mode available"
        echo "  - Install Docker Desktop 4.50+ for Sandbox mode, OR"
        echo "  - Run 'cai setup' to configure Sysbox mode"
        return 1
    fi

    return 0
}
```

## `cai run` Command

**Entry point flow:** Validate explicit config BEFORE preflight to ensure consistent error paths.

```bash
_cai_run() {
    local workspace="${OPT_WORKSPACE:-$(pwd)}"
    local explicit_config="${OPT_CONFIG:-}"

    # Validate workspace BEFORE anything else
    [[ -d "$workspace" ]] || {
        echo "[ERROR] Workspace not found: $workspace"
        return 1
    }
    workspace=$(cd "$workspace" && pwd)

    # Validate explicit config EARLY (before preflight)
    # This ensures --config / CONTAINAI_CONFIG errors are caught before Docker checks
    if [[ -n "$explicit_config" ]]; then
        [[ -f "$explicit_config" ]] || {
            echo "[ERROR] Config not found: $explicit_config"
            return 1
        }
    elif [[ -n "${CONTAINAI_CONFIG:-}" ]]; then
        [[ -f "$CONTAINAI_CONFIG" ]] || {
            echo "[ERROR] CONTAINAI_CONFIG not found: $CONTAINAI_CONFIG"
            return 1
        }
        explicit_config="$CONTAINAI_CONFIG"
    fi

    _cai_preflight || return 1

    local ctx=$(_cai_get_context)
    local agent="${OPT_AGENT:-claude}"
    local credentials="${OPT_CREDENTIALS:-none}"

    # Acknowledgement for docker socket (applies to both modes)
    [[ "$OPT_MOUNT_DOCKER_SOCKET" == "true" && "$OPT_ACKNOWLEDGE_DOCKER_SOCKET_RISK" != "true" ]] && {
        echo "[ERROR] --mount-docker-socket requires --acknowledge-docker-socket-risk"; return 1
    }

    # Credential acknowledgement - mode-specific validation happens later in mode branches
    # (Sysbox mode rejects non-none credentials entirely)

    # Resolve volume (pass explicit_config for consistent handling)
    local data_volume
    data_volume=$(_cai_resolve_volume "$workspace" "$explicit_config" "${OPT_DATA_VOLUME:-}") || return 1

    # Resolve image from repo + tag (no string surgery)
    local repo default_tag image_tag image
    case "$agent" in
        claude) repo="docker/sandbox-templates"; default_tag="claude-code" ;;
        gemini) repo="docker/sandbox-templates"; default_tag="gemini-cli" ;;
        *) echo "[ERROR] Unknown agent: $agent"; return 1 ;;
    esac
    image_tag="${OPT_IMAGE_TAG:-${CONTAINAI_AGENT_TAG:-$default_tag}}"
    image="${repo}:${image_tag}"

    # Check image exists
    _cai_check_image "$ctx" "$image" || return 1

    # Select execution mode based on context
    local -a cmd
    if [[ "$ctx" == "containai-secure" ]]; then
        # Sysbox mode: use docker run with sysbox runtime
        # Note: docker sandbox is Docker Desktop only
        cmd=(
            docker --context "$ctx" run -it --rm
            --runtime=sysbox-runc
            --label "containai.sandbox=containai"
            -v "${data_volume}:/mnt/agent-data"
            -v "${workspace}:${workspace}"
            -w "$workspace"
        )
        # Sysbox mode: reject --credentials (not supported - this is a docker sandbox feature)
        if [[ "$credentials" != "none" ]]; then
            echo "[ERROR] --credentials=$credentials not supported in Sysbox mode" >&2
            echo "[ERROR] Sysbox mode does not support Docker Sandbox credential forwarding" >&2
            echo "[INFO] Use --context default for Sandbox mode with credentials, or" >&2
            echo "[INFO] manually mount credentials into the container" >&2
            return 1
        fi

        # Sysbox mode: mount the ContainAI daemon socket (not default /var/run/docker.sock)
        if [[ "$OPT_MOUNT_DOCKER_SOCKET" == "true" ]]; then
            local containai_socket="/var/run/containai-docker.sock"
            if [[ -S "$containai_socket" ]]; then
                cmd+=(-v "${containai_socket}:/var/run/docker.sock")
                echo "[INFO] Mounting ContainAI Docker socket (Sysbox mode)" >&2
            else
                echo "[ERROR] --mount-docker-socket: ContainAI socket not found at $containai_socket" >&2
                return 1
            fi
        fi
    else
        # Sandbox mode: use docker sandbox run (Docker Desktop)
        # Validate credentials acknowledgement (sandbox mode supports --credentials)
        if [[ "$credentials" == "host" && "$OPT_ACKNOWLEDGE_CREDENTIAL_RISK" != "true" ]]; then
            echo "[ERROR] --credentials=host requires --acknowledge-credential-risk" >&2
            return 1
        fi

        cmd=(
            docker --context "$ctx" sandbox run
            --label "containai.sandbox=containai"
            --credentials "$credentials"
            -v "${data_volume}:/mnt/agent-data"
            -v "${workspace}:${workspace}"
            -w "$workspace"
        )
        [[ "$OPT_MOUNT_DOCKER_SOCKET" == "true" ]] && cmd+=(--mount-docker-socket)
    fi
    cmd+=("$image")

    echo "[INFO] ${cmd[*]}"
    "${cmd[@]}"
}
```

## Sysbox/ECI Detection

```bash
# Returns: sysbox, eci, none
_cai_detect_isolation() {
    local ctx="${OPT_CONTEXT:-${DOCKER_CONTEXT:-default}}"

    # Check for Sysbox runtime
    if docker --context "$ctx" info 2>/dev/null | grep -q "sysbox-runc"; then
        echo "sysbox"
        return
    fi

    # Check for ECI (Enhanced Container Isolation) via Docker Desktop
    if docker --context "$ctx" info 2>/dev/null | grep -qiE "enhanced.*container.*isolation|eci.*enabled"; then
        echo "eci"
        return
    fi

    echo "none"
}
```

## `cai setup` Command

Installs Sysbox for enhanced isolation. Platform-specific behavior:

```bash
_cai_setup() {
    local force="${OPT_FORCE:-false}"
    local dry_run="${OPT_DRY_RUN:-false}"
    local platform
    platform=$(uname -s)

    case "$platform" in
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                _cai_setup_wsl2 "$force" "$dry_run"
            else
                _cai_setup_linux "$dry_run"
            fi
            ;;
        Darwin)
            _cai_setup_macos "$dry_run"
            ;;
        *)
            echo "[ERROR] Unsupported platform: $platform"
            return 1
            ;;
    esac
}

_cai_setup_wsl2() {
    local force="$1"
    local dry_run="$2"

    # Check WSL2 networking mode
    local wsl_conf="/etc/wsl.conf"
    local network_mode="nat"  # default
    if [[ -f "$wsl_conf" ]] && grep -qiE "networkingMode.*=.*mirrored" "$wsl_conf"; then
        network_mode="mirrored"
    fi

    # Test seccomp availability and compatibility for Sysbox
    # Sysbox requires seccomp support, but WSL2's filter mode (Seccomp: 2) can conflict
    local seccomp_status="unknown"

    # Check /proc/1/status for Seccomp field
    if grep -q "^Seccomp:" /proc/1/status 2>/dev/null; then
        local seccomp_mode
        seccomp_mode=$(grep "^Seccomp:" /proc/1/status | awk '{print $2}')
        case "$seccomp_mode" in
            0) seccomp_status="disabled" ;;
            1) seccomp_status="strict" ;;   # Strict mode - Sysbox works
            2) seccomp_status="filter" ;;   # Filter mode - may conflict with Sysbox
            *) seccomp_status="unknown" ;;
        esac
    fi

    # Fallback: Try unshare test if status is unknown
    if [[ "$seccomp_status" == "unknown" ]]; then
        if unshare --map-root-user true 2>/dev/null; then
            seccomp_status="available"
        else
            seccomp_status="unavailable"
        fi
    fi

    # Evaluate seccomp status for Sysbox compatibility
    case "$seccomp_status" in
        strict|available)
            echo "[OK] Seccomp support verified (mode: $seccomp_status)"
            ;;
        filter)
            # WSL2 filter mode can conflict with Sysbox's own seccomp policies
            echo "[WARN] WSL2 seccomp filter mode detected (Seccomp: 2)"
            echo "[WARN] This mode MAY conflict with Sysbox - installation will proceed"
            echo "[WARN] If Sysbox fails to start, consider using Docker Sandbox instead"
            if [[ "$force" != "true" ]]; then
                echo "[INFO] Use --force to skip this warning"
                read -p "Continue with Sysbox installation? [y/N]: " confirm
                if [[ ! "$confirm" =~ ^[Yy] ]]; then
                    echo "[INFO] Aborted. Docker Sandbox will still work without Sysbox."
                    return 1
                fi
            fi
            ;;
        disabled|unavailable)
            echo "[WARN] Seccomp not available - Sysbox will NOT work on this WSL2 instance"
            echo "[WARN] Docker Sandbox will still work (without Sysbox isolation)"
            if [[ "$force" != "true" ]]; then
                echo "[ERROR] Use --force to continue without Sysbox"
                return 1
            fi
            echo "[INFO] Continuing with Sysbox installation (--force specified)"
            ;;
        *)
            echo "[WARN] Seccomp status could not be determined"
            echo "[WARN] Sysbox installation may or may not succeed"
            if [[ "$force" != "true" ]]; then
                echo "[ERROR] Use --force to continue"
                return 1
            fi
            ;;
    esac

    if [[ "$network_mode" == "mirrored" ]]; then
        echo "[WARN] WSL2 mirrored networking may cause Sysbox issues"
    fi

    [[ "$dry_run" == "true" ]] && { echo "[DRY-RUN] Would install Sysbox for WSL2 with dedicated dockerd"; return 0; }

    # WSL2 needs its own dockerd (Docker Desktop's daemon is outside WSL2)
    echo "[INFO] WSL2 requires a dedicated Docker daemon for Sysbox"
    echo "[INFO] This will install dockerd inside WSL2 alongside Docker Desktop"

    # Install Docker daemon in WSL2
    _cai_install_docker_wsl2 || return 1

    # Install Sysbox and configure
    _cai_install_sysbox || return 1
    _cai_configure_sysbox_runtime_wsl2 || return 1
    _cai_create_secure_context_wsl2
}

_cai_install_docker_wsl2() {
    echo "[INFO] Installing Docker daemon in WSL2..."

    # Check if systemd is RUNNING (not just installed)
    if [[ ! -d /run/systemd/system ]]; then
        echo "[ERROR] systemd is not running in this WSL2 instance"
        echo "[INFO] To enable systemd:"
        echo "[INFO]   1. Edit /etc/wsl.conf and add:"
        echo "[INFO]      [boot]"
        echo "[INFO]      systemd=true"
        echo "[INFO]   2. Run: wsl --shutdown"
        echo "[INFO]   3. Restart WSL2"
        echo "[INFO] Then re-run: cai setup"
        return 1
    fi

    # Install docker-ce if not present
    if ! command -v dockerd >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com | sh || {
            echo "[ERROR] Failed to install Docker"
            return 1
        }
    fi

    echo "[OK] Docker daemon installed"
}

_cai_setup_linux() {
    local dry_run="$1"
    [[ "$dry_run" == "true" ]] && { echo "[DRY-RUN] Would install Sysbox for Linux"; return 0; }

    # Install Sysbox and configure with dedicated daemon
    _cai_install_sysbox || return 1
    _cai_configure_sysbox_daemon_linux || return 1
    _cai_create_secure_context_linux
}

_cai_setup_macos() {
    local dry_run="$1"
    echo "[INFO] macOS: Docker Desktop's ECI provides isolation without Sysbox"
    echo "[INFO] For Sysbox on macOS, use Lima VM: https://github.com/lima-vm/lima"

    [[ "$dry_run" == "true" ]] && { echo "[DRY-RUN] Would check Docker Desktop ECI"; return 0; }

    # Check if ECI is enabled
    local isolation
    isolation=$(_cai_detect_isolation)
    if [[ "$isolation" == "eci" ]]; then
        echo "[OK] Docker Desktop ECI is enabled"
        return 0
    fi

    echo "[WARN] ECI not detected - enable in Docker Desktop Settings > Security"
    echo "[INFO] ContainAI will work but with reduced isolation"
    return 0
}

# Distro detection for package manager selection
_cai_detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${ID:-unknown}"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

_cai_install_sysbox() {
    local distro
    distro=$(_cai_detect_distro)
    local arch version url

    # Check if Sysbox is already installed
    if command -v sysbox-runc >/dev/null 2>&1; then
        echo "[OK] Sysbox already installed: $(sysbox-runc --version 2>&1 | head -1)"
        echo "[INFO] Skipping installation, proceeding to configuration"
        return 0
    fi

    case "$distro" in
        ubuntu|debian)
            arch=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
            version="${SYSBOX_VERSION:-0.6.7}"
            url="https://downloads.nestybox.com/sysbox/releases/v${version}/sysbox-ce_${version}-0.linux_${arch}.deb"

            echo "[INFO] Downloading Sysbox ${version} for ${distro}/${arch}..."
            wget -q -O /tmp/sysbox.deb "$url" || {
                echo "[ERROR] Failed to download Sysbox"
                return 1
            }

            echo "[INFO] Installing Sysbox..."
            sudo apt-get install -y /tmp/sysbox.deb || {
                echo "[ERROR] Failed to install Sysbox"
                return 1
            }

            rm -f /tmp/sysbox.deb
            ;;
        fedora|rhel|centos|rocky|alma)
            echo "[ERROR] Sysbox on ${distro} requires manual installation"
            echo "[INFO] See: https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md#installing-sysbox-on-redhat-based-distros"
            return 1
            ;;
        arch|manjaro)
            echo "[ERROR] Sysbox on ${distro} requires AUR installation"
            echo "[INFO] See: https://aur.archlinux.org/packages/sysbox-ce"
            echo "[INFO] After installing Sysbox manually, run this script again to configure the daemon"
            return 1
            ;;
        *)
            echo "[ERROR] Unsupported distro: ${distro}"
            echo "[INFO] ContainAI setup supports: Ubuntu, Debian"
            echo "[INFO] For other distros:"
            echo "[INFO]   1. Manually install Sysbox from: https://github.com/nestybox/sysbox"
            echo "[INFO]   2. Run 'cai setup' again to configure the daemon"
            return 1
            ;;
    esac

    echo "[OK] Sysbox installed successfully"
}

# Linux: Create dedicated daemon with Sysbox as default runtime
_cai_configure_sysbox_daemon_linux() {
    local containai_socket="/var/run/containai-docker.sock"
    local containai_data="/var/lib/docker-containai"
    local daemon_json="/etc/containai/daemon.json"

    echo "[INFO] Configuring dedicated Docker daemon for ContainAI on Linux..."

    # Create containai-docker group for socket access
    if ! getent group containai-docker >/dev/null 2>&1; then
        sudo groupadd containai-docker
        echo "[INFO] Created group: containai-docker"
    fi

    # Add current user to group
    sudo usermod -aG containai-docker "$USER" || true
    echo "[INFO] Added $USER to containai-docker group"

    # Create directories
    sudo mkdir -p /etc/containai
    sudo mkdir -p "$containai_data"

    # Create daemon.json with:
    # - Separate data-root to avoid conflicts with default Docker
    # - Sysbox as DEFAULT runtime
    # - Group for socket permissions (no socket unit needed)
    cat <<EOF | sudo tee "$daemon_json" > /dev/null
{
  "hosts": ["unix://${containai_socket}"],
  "data-root": "${containai_data}",
  "group": "containai-docker",
  "runtimes": {
    "sysbox-runc": {
      "path": "/usr/bin/sysbox-runc"
    }
  },
  "default-runtime": "sysbox-runc"
}
EOF

    # Create systemd service for ContainAI's dockerd
    # Note: No socket activation - dockerd manages the socket directly with --group
    cat <<'EOF' | sudo tee /etc/systemd/system/containai-docker.service > /dev/null
[Unit]
Description=ContainAI Docker daemon with Sysbox (default runtime)
After=network.target sysbox.service
Requires=sysbox.service
# Conflicts with default docker to avoid data-root confusion
Conflicts=docker.service

[Service]
Type=notify
ExecStart=/usr/bin/dockerd --config-file=/etc/containai/daemon.json
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Check if default docker is running/enabled (for later disabling)
    local docker_active=false docker_enabled=false socket_enabled=false
    systemctl is-active --quiet docker 2>/dev/null && docker_active=true
    systemctl is-enabled --quiet docker 2>/dev/null && docker_enabled=true
    systemctl is-enabled --quiet docker.socket 2>/dev/null && socket_enabled=true

    local needs_docker_disable=false
    if [[ "$docker_active" == "true" || "$docker_enabled" == "true" || "$socket_enabled" == "true" ]]; then
        needs_docker_disable=true
        echo ""
        echo "[WARN] Default Docker daemon/socket conflicts with ContainAI daemon"
        echo "[WARN] After success, this will stop/disable: docker.service docker.socket"
        echo "[INFO] To revert later: sudo systemctl stop containai-docker && sudo systemctl enable --now docker"

        if [[ "${OPT_FORCE:-false}" != "true" ]]; then
            read -p "Proceed? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy] ]]; then
                echo "[INFO] Aborted. Use --force to skip confirmation."
                return 1
            fi
        fi
    fi

    # Start containai-docker FIRST (before disabling default docker)
    sudo systemctl daemon-reload
    sudo systemctl enable containai-docker.service
    echo "[INFO] Starting ContainAI Docker daemon..."
    if ! sudo systemctl start containai-docker.service; then
        echo "[ERROR] Failed to start ContainAI Docker daemon" >&2
        echo "[ERROR] Default Docker daemon was NOT modified (rollback safe)" >&2
        echo "[INFO] Check logs: journalctl -u containai-docker.service" >&2
        # Disable containai-docker so it doesn't interfere on future boots
        sudo systemctl disable containai-docker.service 2>/dev/null || true
        return 1
    fi

    # Only disable default docker AFTER containai-docker succeeds
    if [[ "$needs_docker_disable" == "true" ]]; then
        # Stop and disable docker.service
        if [[ "$docker_active" == "true" ]]; then
            echo "[INFO] Stopping docker.service..."
            sudo systemctl stop docker
        fi
        if [[ "$docker_enabled" == "true" ]]; then
            echo "[INFO] Disabling docker.service..."
            sudo systemctl disable docker
        fi

        # Also disable docker.socket (can auto-start docker.service on demand)
        if [[ "$socket_enabled" == "true" ]]; then
            echo "[INFO] Disabling docker.socket (prevents auto-start)..."
            sudo systemctl disable docker.socket
            sudo systemctl stop docker.socket 2>/dev/null || true
        fi
    fi

    echo "[OK] ContainAI Docker daemon configured at $containai_socket"
    echo "[OK] Data stored in $containai_data (separate from default Docker)"
    echo "[WARN] Log out and back in to use containai-docker group"
    echo "[INFO] To use ContainAI: cai --context containai-secure run"
    echo "[INFO] To restore default Docker: sudo systemctl stop containai-docker && sudo systemctl enable --now docker"
}

_cai_create_secure_context_linux() {
    local ctx_name="containai-secure"
    local socket="/var/run/containai-docker.sock"

    # Check if context already exists
    if docker context inspect "$ctx_name" >/dev/null 2>&1; then
        echo "[INFO] Context '$ctx_name' already exists, updating..."
        docker context rm "$ctx_name" >/dev/null 2>&1 || true
    fi

    # Wait for socket to be available
    local max_wait=30
    local waited=0
    while [[ ! -S "$socket" && $waited -lt $max_wait ]]; do
        sleep 1
        ((waited++))
    done

    if [[ ! -S "$socket" ]]; then
        echo "[ERROR] ContainAI Docker socket not available at $socket"
        return 1
    fi

    echo "[INFO] Creating Docker context '$ctx_name' pointing to ContainAI daemon..."
    docker context create "$ctx_name" \
        --docker "host=unix://${socket}" \
        --description "ContainAI secure context with Sysbox as default runtime" || {
        echo "[ERROR] Failed to create context"
        return 1
    }

    echo "[OK] Context '$ctx_name' created"
    echo "[INFO] Use with: cai --context $ctx_name run"
}

# WSL2-specific configuration (uses separate socket to avoid conflicts with Docker Desktop)
_cai_configure_sysbox_runtime_wsl2() {
    local containai_socket="/var/run/containai-docker.sock"
    local containai_data="/var/lib/docker-containai"
    local daemon_json="/etc/containai/daemon.json"

    echo "[INFO] Configuring dedicated Docker daemon for ContainAI in WSL2..."

    # Create containai-docker group for socket access
    if ! getent group containai-docker >/dev/null 2>&1; then
        sudo groupadd containai-docker
        echo "[INFO] Created group: containai-docker"
    fi

    # Add current user to group
    sudo usermod -aG containai-docker "$USER" || true
    echo "[INFO] Added $USER to containai-docker group"

    # Create directories
    sudo mkdir -p /etc/containai
    sudo mkdir -p "$containai_data"

    # Create daemon.json for ContainAI's dockerd (separate from Docker Desktop)
    # Uses separate data-root to avoid conflicts
    cat <<EOF | sudo tee "$daemon_json" > /dev/null
{
  "hosts": ["unix://${containai_socket}"],
  "data-root": "${containai_data}",
  "group": "containai-docker",
  "runtimes": {
    "sysbox-runc": {
      "path": "/usr/bin/sysbox-runc"
    }
  },
  "default-runtime": "sysbox-runc"
}
EOF

    # Create systemd service for ContainAI's dockerd
    # Note: No socket activation - dockerd manages the socket directly with --group
    # Conflicts with default docker.service to avoid confusion
    cat <<'EOF' | sudo tee /etc/systemd/system/containai-docker.service > /dev/null
[Unit]
Description=ContainAI Docker daemon with Sysbox (WSL2)
After=network.target sysbox.service
Requires=sysbox.service
# Conflicts with default docker to avoid data-root confusion
Conflicts=docker.service

[Service]
Type=notify
ExecStart=/usr/bin/dockerd --config-file=/etc/containai/daemon.json
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Check if default docker is running/enabled (for later disabling)
    # This docker.service was installed by get.docker.com - NOT Docker Desktop
    local docker_active=false docker_enabled=false socket_enabled=false
    systemctl is-active --quiet docker 2>/dev/null && docker_active=true
    systemctl is-enabled --quiet docker 2>/dev/null && docker_enabled=true
    systemctl is-enabled --quiet docker.socket 2>/dev/null && socket_enabled=true

    local needs_docker_disable=false
    if [[ "$docker_active" == "true" || "$docker_enabled" == "true" || "$socket_enabled" == "true" ]]; then
        needs_docker_disable=true
        echo ""
        echo "[WARN] Default Docker daemon/socket in WSL2 conflicts with ContainAI daemon"
        echo "[WARN] After success, this will stop/disable: docker.service docker.socket"
        echo "[INFO] Docker Desktop (outside WSL2) remains unaffected"
        echo "[INFO] To revert: sudo systemctl stop containai-docker && sudo systemctl enable --now docker"

        if [[ "${OPT_FORCE:-false}" != "true" ]]; then
            read -p "Proceed? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy] ]]; then
                echo "[INFO] Aborted. Use --force to skip confirmation."
                return 1
            fi
        fi
    fi

    # Start containai-docker FIRST (before disabling default docker)
    sudo systemctl daemon-reload
    sudo systemctl enable containai-docker.service
    echo "[INFO] Starting ContainAI Docker daemon in WSL2..."
    if ! sudo systemctl start containai-docker.service; then
        echo "[ERROR] Failed to start ContainAI Docker daemon" >&2
        echo "[ERROR] Default Docker daemon was NOT modified (rollback safe)" >&2
        echo "[INFO] Check logs: journalctl -u containai-docker.service" >&2
        # Disable containai-docker so it doesn't interfere on future boots
        sudo systemctl disable containai-docker.service 2>/dev/null || true
        return 1
    fi

    # Only disable default docker AFTER containai-docker succeeds
    if [[ "$needs_docker_disable" == "true" ]]; then
        # Stop and disable docker.service
        if [[ "$docker_active" == "true" ]]; then
            echo "[INFO] Stopping docker.service in WSL2..."
            sudo systemctl stop docker
        fi
        if [[ "$docker_enabled" == "true" ]]; then
            echo "[INFO] Disabling docker.service in WSL2..."
            sudo systemctl disable docker
        fi

        # Also disable docker.socket (can auto-start docker.service on demand)
        if [[ "$socket_enabled" == "true" ]]; then
            echo "[INFO] Disabling docker.socket in WSL2..."
            sudo systemctl disable docker.socket
            sudo systemctl stop docker.socket 2>/dev/null || true
        fi
    fi

    echo "[OK] ContainAI Docker daemon configured at $containai_socket"
    echo "[OK] Data stored in $containai_data (separate from Docker Desktop)"
    echo "[WARN] Log out and back in to use containai-docker group"
    echo "[INFO] Docker Desktop (outside WSL2) remains available on default context"
    echo "[INFO] Default docker.service in WSL2 has been stopped/disabled"
}

_cai_create_secure_context_wsl2() {
    local ctx_name="containai-secure"
    local socket="/var/run/containai-docker.sock"

    # Check if context already exists
    if docker context inspect "$ctx_name" >/dev/null 2>&1; then
        echo "[INFO] Context '$ctx_name' already exists, updating..."
        docker context rm "$ctx_name" >/dev/null 2>&1 || true
    fi

    # Wait for socket to be available
    local max_wait=30
    local waited=0
    while [[ ! -S "$socket" && $waited -lt $max_wait ]]; do
        sleep 1
        ((waited++))
    done

    if [[ ! -S "$socket" ]]; then
        echo "[ERROR] ContainAI Docker socket not available at $socket"
        return 1
    fi

    echo "[INFO] Creating Docker context '$ctx_name' pointing to ContainAI daemon..."
    docker context create "$ctx_name" \
        --docker "host=unix://${socket}" \
        --description "ContainAI secure context with Sysbox (WSL2)" || {
        echo "[ERROR] Failed to create context"
        return 1
    }

    echo "[OK] Context '$ctx_name' created"
    echo "[INFO] Use with: cai --context $ctx_name run"
    echo "[INFO] Note: Docker Desktop remains the default context"
}
```

## `cai sandbox reset` Command

Resets sandbox state by removing ContainAI-labeled containers and optionally volumes.

**Context check:** Management commands treat "context not honored" as fatal.

**Mode branching:** Uses `docker sandbox ls/rm` for Sandbox mode (Docker Desktop), but `docker ps/rm` for Sysbox mode (containers created via `docker run`).

```bash
_cai_sandbox_reset() {
    local ctx="${OPT_CONTEXT:-${DOCKER_CONTEXT:-default}}"
    local all="${OPT_ALL:-false}"
    local dry_run="${OPT_DRY_RUN:-false}"
    local workspace="${OPT_WORKSPACE:-$(pwd)}"
    local explicit_config="${OPT_CONFIG:-}"

    # Management commands: context mismatch is FATAL
    if [[ "$ctx" != "default" && "$ctx" != "containai-secure" ]]; then
        local ctx_check
        ctx_check=$(docker --context "$ctx" context show 2>/dev/null) || ctx_check=""
        if [[ "$ctx_check" != "$ctx" ]]; then
            echo "[ERROR] Context '$ctx' not honored - refusing to run destructive command" >&2
            echo "[ERROR] Use default context or verify context configuration" >&2
            return 1
        fi
    fi

    # Validate config early (same as cai run)
    if [[ -n "$explicit_config" ]]; then
        [[ -f "$explicit_config" ]] || {
            echo "[ERROR] Config not found: $explicit_config"
            return 1
        }
    elif [[ -n "${CONTAINAI_CONFIG:-}" ]]; then
        [[ -f "$CONTAINAI_CONFIG" ]] || {
            echo "[ERROR] CONTAINAI_CONFIG not found: $CONTAINAI_CONFIG"
            return 1
        }
        explicit_config="$CONTAINAI_CONFIG"
    fi

    # Branch by mode: Sysbox (containai-secure) vs Sandbox (Docker Desktop)
    local -a containers
    if [[ "$ctx" == "containai-secure" ]]; then
        # Sysbox mode: containers created via docker run, use docker ps/rm
        echo "[INFO] Sysbox mode: finding containers via docker ps"
        local ps_output ps_rc
        ps_output=$(docker --context "$ctx" ps -a --filter "label=containai.sandbox=containai" -q 2>&1)
        ps_rc=$?
        if [[ $ps_rc -ne 0 ]]; then
            echo "[ERROR] Failed to list containers: $ps_output" >&2
            return 1
        fi
        mapfile -t containers <<< "$ps_output"
        # Filter out empty entries
        containers=("${containers[@]//[[:space:]]/}")
        containers=(${containers[@]})

        if [[ ${#containers[@]} -eq 0 || -z "${containers[0]:-}" ]]; then
            echo "[INFO] No ContainAI containers found"
        else
            echo "[INFO] Found ${#containers[@]} ContainAI container(s)"

            if [[ "$dry_run" == "true" ]]; then
                echo "[DRY-RUN] Would remove containers: ${containers[*]}"
            else
                for cid in "${containers[@]}"; do
                    [[ -z "$cid" ]] && continue
                    echo "[INFO] Removing container: $cid"
                    docker --context "$ctx" rm -f "$cid" || {
                        echo "[WARN] Failed to remove container: $cid"
                    }
                done
            fi
        fi
    else
        # Sandbox mode: containers created via docker sandbox run, use docker sandbox ls/rm
        echo "[INFO] Sandbox mode: finding sandboxes via docker sandbox ls"

        # First check if sandbox command is available
        local sandbox_output sandbox_rc classification
        sandbox_output=$(docker --context "$ctx" sandbox ls --filter "label=containai.sandbox=containai" -q 2>&1)
        sandbox_rc=$?
        classification=$(_cai_classify_sandbox_error "$sandbox_output" "$sandbox_rc")

        case "$classification" in
            ok)
                # Success - proceed with output
                ;;
            empty)
                # "empty" means no sandboxes but with unusual rc
                # Clear output to prevent treating the message as container IDs
                echo "[INFO] $SANDBOX_MSG"
                sandbox_output=""
                ;;
            not_available|disabled)
                echo "[ERROR] $SANDBOX_MSG" >&2
                echo "[INFO] Cannot reset sandboxes - Docker Sandbox not available" >&2
                echo "[INFO] If containers were created manually, use: docker rm -f <container>" >&2
                return 1
                ;;
            *)
                echo "[ERROR] Failed to list sandboxes: $sandbox_output" >&2
                return 1
                ;;
        esac

        mapfile -t containers <<< "$sandbox_output"
        # Filter out empty entries
        containers=("${containers[@]//[[:space:]]/}")
        containers=(${containers[@]})

        if [[ ${#containers[@]} -eq 0 || -z "${containers[0]:-}" ]]; then
            echo "[INFO] No ContainAI sandboxes found"
        else
            echo "[INFO] Found ${#containers[@]} ContainAI sandbox(es)"

            if [[ "$dry_run" == "true" ]]; then
                echo "[DRY-RUN] Would remove sandboxes: ${containers[*]}"
            else
                for sid in "${containers[@]}"; do
                    [[ -z "$sid" ]] && continue
                    echo "[INFO] Removing sandbox: $sid"
                    docker --context "$ctx" sandbox rm -f "$sid" || {
                        echo "[WARN] Failed to remove sandbox: $sid"
                        # Fallback to docker rm if sandbox rm fails
                        docker --context "$ctx" rm -f "$sid" 2>/dev/null || true
                    }
                done
            fi
        fi
    fi

    # Volume reset requires --all flag
    if [[ "$all" == "true" ]]; then
        # Resolve volume using same precedence as cai run
        local data_volume
        data_volume=$(_cai_resolve_volume "$workspace" "$explicit_config" "${OPT_DATA_VOLUME:-}") || {
            echo "[ERROR] Failed to resolve data volume"
            return 1
        }

        echo "[WARN] This will DELETE all data in volume: $data_volume"
        echo "[WARN] This includes credentials, settings, and cached data"

        if [[ "$dry_run" == "true" ]]; then
            echo "[DRY-RUN] Would remove volume: $data_volume"
        else
            # Prompt for confirmation (unless --yes flag)
            if [[ "${OPT_YES:-false}" != "true" ]]; then
                read -p "Type 'yes' to confirm volume deletion: " confirm
                if [[ "$confirm" != "yes" ]]; then
                    echo "[INFO] Volume deletion cancelled"
                    return 0
                fi
            fi

            docker --context "$ctx" volume rm "$data_volume" || {
                echo "[ERROR] Failed to remove volume: $data_volume"
                return 1
            }
            echo "[OK] Volume $data_volume removed"
        fi
    fi

    echo "[OK] Sandbox reset complete"
}
```

## `cai sandbox clear-credentials` Command

Clears credentials from sandbox data volume.

**Context check:** Management commands treat "context not honored" as fatal.

**Credential paths:** Uses target-side paths from SYNC_MAP (see `agent-sandbox/sync-agent-plugins.sh`).

```bash
_cai_sandbox_clear_credentials() {
    local workspace="${OPT_WORKSPACE:-$(pwd)}"
    local explicit_config="${OPT_CONFIG:-}"
    local dry_run="${OPT_DRY_RUN:-false}"
    local ctx="${OPT_CONTEXT:-${DOCKER_CONTEXT:-default}}"

    # Management commands: context mismatch is FATAL
    if [[ "$ctx" != "default" ]]; then
        local ctx_check
        ctx_check=$(docker --context "$ctx" context show 2>/dev/null) || ctx_check=""
        if [[ "$ctx_check" != "$ctx" ]]; then
            echo "[ERROR] Context '$ctx' not honored - refusing to run destructive command" >&2
            echo "[ERROR] Use default context or verify context configuration" >&2
            return 1
        fi
    fi

    # Validate config early (same as cai run)
    if [[ -n "$explicit_config" ]]; then
        [[ -f "$explicit_config" ]] || {
            echo "[ERROR] Config not found: $explicit_config"
            return 1
        }
    elif [[ -n "${CONTAINAI_CONFIG:-}" ]]; then
        [[ -f "$CONTAINAI_CONFIG" ]] || {
            echo "[ERROR] CONTAINAI_CONFIG not found: $CONTAINAI_CONFIG"
            return 1
        }
        explicit_config="$CONTAINAI_CONFIG"
    fi

    # Resolve volume
    local data_volume
    data_volume=$(_cai_resolve_volume "$workspace" "$explicit_config" "${OPT_DATA_VOLUME:-}") || return 1

    # Verify volume exists (avoid silently creating empty volumes)
    if ! docker --context "$ctx" volume inspect "$data_volume" >/dev/null 2>&1; then
        echo "[ERROR] Data volume not found: $data_volume" >&2
        echo "[INFO] No credentials to clear (volume does not exist)" >&2
        return 1
    fi

    echo "[INFO] Clearing credentials from volume: $data_volume"

    # Credential paths - TARGET-SIDE paths from SYNC_MAP in agent-sandbox/sync-agent-plugins.sh
    # These match the volume layout, NOT host dotfiles
    # MUST cover all auth-bearing targets from SYNC_MAP
    local -a cred_paths=(
        # Claude Code (SYNC_MAP: /source/.claude.json:/target/claude/claude.json:fjs)
        "claude/claude.json"
        "claude/credentials.json"
        # Gemini (SYNC_MAP: /source/.gemini/oauth_creds.json:/target/gemini/oauth_creds.json:fs)
        "gemini/oauth_creds.json"
        "gemini/google_accounts.json"
        # GitHub CLI (SYNC_MAP: /source/.config/gh:/target/config/gh:ds)
        "config/gh"
        # Codex (SYNC_MAP: /source/.codex/auth.json:/target/codex/auth.json:fs)
        "codex/auth.json"
        # OpenCode (SYNC_MAP: /source/.local/share/opencode/auth.json:/target/local/share/opencode/auth.json:fs)
        "local/share/opencode/auth.json"
        # Copilot (SYNC_MAP: /source/.copilot/config.json:/target/copilot/config.json:f)
        # Copilot config may contain auth tokens
        "copilot/config.json"
        "copilot/mcp-config.json"
    )

    if [[ "$dry_run" == "true" ]]; then
        echo "[DRY-RUN] Would clear credential paths from $data_volume:"
        for path in "${cred_paths[@]}"; do
            echo "  - $path"
        done
        return 0
    fi

    # Use temporary container to clear credentials
    for path in "${cred_paths[@]}"; do
        echo "[INFO] Clearing: $path"
        docker --context "$ctx" run --rm -v "${data_volume}:/data" alpine \
            rm -rf "/data/${path}" 2>/dev/null || true
    done

    echo "[OK] Credentials cleared"
}
```

## Acceptance Criteria

### Config Discovery
1. [ ] Config discovery walks up to git root or / (per fn-4-vet)
2. [ ] `_cai_find_config` validates workspace before discovery
3. [ ] `_cai_find_config` returns exit 2 for missing explicit config
4. [ ] `_cai_resolve_volume` propagates error messages from find_config
5. [ ] `git rev-parse` guarded with `command -v git` check

### Sandbox Error Handling
6. [ ] `_cai_classify_sandbox_error` shared by both preflight and doctor
7. [ ] Sandbox classification allows "no sandboxes" output even with rc!=0 (with warning in msg)
8. [ ] Preflight warns for contexts other than "default" or "containai-secure"
9. [ ] Preflight verifies containai-secure socket exists when that context is used

### `cai doctor`
10. [ ] Shows distinct messages: "command not available" vs "feature disabled"
11. [ ] Checks BOTH modes (sandbox on default, sysbox on containai-secure)
12. [ ] Passes if EITHER mode is viable (per Requirements Hierarchy)
13. [ ] Uses shared `_cai_classify_sandbox_error` for sandbox mode
14. [ ] Reports status of both modes in output with actionable guidance

### `cai run`
15. [ ] Validates explicit `--config` AND `CONTAINAI_CONFIG` BEFORE preflight
16. [ ] Image tag respects: `--image-tag` > `CONTAINAI_AGENT_TAG` > agent default tag
17. [ ] Image built as `${repo}:${tag}` (no string surgery)
18. [ ] Validates workspace before config discovery
19. [ ] Uses array execution (no eval)
20. [ ] All acknowledgement flags required for risky options
21. [ ] `_cai_check_image` verifies image exists before run
22. [ ] Sandbox mode (`default` context): uses `docker sandbox run`
23. [ ] Sysbox mode (`containai-secure`): uses `docker run --runtime=sysbox-runc`
24. [ ] `--mount-docker-socket` mounts ContainAI socket (`/var/run/containai-docker.sock`) in Sysbox mode
25. [ ] Sysbox mode: rejects `--credentials` with non-`none` values (hard error)

### Preflight
26. [ ] Checks socket BEFORE docker info for containai-secure (actionable error)
27. [ ] Checks docker connectivity AFTER socket verification

### Volume Resolution
28. [ ] Checks for Python 3.11+ (tomllib) or tomli package before config parsing
29. [ ] Provides clear error message with installation instructions

### `cai setup`
30. [ ] Detects platform: Linux, WSL2, macOS
31. [ ] `_cai_detect_distro` identifies Ubuntu/Debian/Fedora/etc
32. [ ] Ubuntu/Debian: Installs Sysbox via deb package
33. [ ] Fedora/RHEL/Arch: Provides manual installation guidance with clear next steps
34. [ ] Detects existing sysbox-runc and skips installation (allows rerun after manual install)
35. [ ] WSL2: Checks systemd is RUNNING (`/run/systemd/system`)
36. [ ] WSL2: Tests seccomp with /proc/1/status, distinguishes filter mode (Seccomp: 2)
37. [ ] WSL2: Warns about seccomp filter mode potential conflicts, prompts for confirmation
38. [ ] WSL2: Warns about mirrored networking mode
39. [ ] WSL2: Requires `--force` to continue when seccomp unavailable
40. [ ] Linux/WSL2: Requires confirmation before stopping/disabling docker (or `--force`)
41. [ ] Linux/WSL2: Stops/disables docker.service AND docker.socket (avoid auto-start)
42. [ ] Linux/WSL2: Creates dedicated daemon with `default-runtime: sysbox-runc`
43. [ ] Linux/WSL2: Uses separate `data-root` (`/var/lib/docker-containai`)
44. [ ] Linux/WSL2: Creates containai-docker group, configures via `--group`
45. [ ] Linux/WSL2: No socket activation (dockerd manages socket directly)
46. [ ] Linux/WSL2: Creates `containai-secure` context with explicit endpoint
47. [ ] macOS: Checks ECI status, provides Lima VM guidance
48. [ ] `--dry-run` shows what would be installed

### `cai sandbox reset`
49. [ ] Context mismatch is FATAL for non-default/containai-secure contexts
50. [ ] Validates config early (same as `cai run`)
51. [ ] Sandbox mode: validates sandbox availability before listing (fails loudly on error)
52. [ ] Sandbox mode: uses `docker sandbox ls/rm` for Docker Desktop sandboxes
53. [ ] Sysbox mode: uses `docker ps/rm` for containers created via docker run
54. [ ] `--all` flag resolves and removes data volume
55. [ ] Volume deletion requires explicit confirmation or `--yes`
56. [ ] `--dry-run` shows what would be removed

### `cai sandbox clear-credentials`
57. [ ] Context mismatch is FATAL for non-default/containai-secure contexts
58. [ ] Validates config early (same as `cai run`)
59. [ ] Verifies data volume exists before clearing (avoids creating empty volumes)
60. [ ] Resolves data volume
61. [ ] Uses TARGET-SIDE paths from SYNC_MAP (not host dotfiles)
62. [ ] Includes copilot/config.json and copilot/mcp-config.json
63. [ ] `--dry-run` shows what would be cleared

### Sysbox/ECI Detection
64. [ ] `_cai_detect_isolation` returns: sysbox, eci, or none
65. [ ] Checks `docker info` for sysbox-runc
66. [ ] Checks `docker info` for ECI indicators

## References

- Config schema: fn-4-vet spec
- Docker Sandboxes: https://docs.docker.com/ai/sandboxes/
- Sysbox: https://github.com/nestybox/sysbox
