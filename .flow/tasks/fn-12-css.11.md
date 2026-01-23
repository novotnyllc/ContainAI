# fn-12-css.11 Merge install-containai-docker.sh into cai setup

## Description

Consolidate the Docker/Sysbox installation logic from `scripts/install-containai-docker.sh` into `lib/setup.sh`. This provides a single entry point (`cai setup`) for all installation needs.

**Current state:**
- `cai setup` - Installs Sysbox, creates context (WSL2/macOS)
- `scripts/install-containai-docker.sh` - Installs separate docker-ce instance with Sysbox default runtime

**Target state:**
- `cai setup` handles everything
- `cai setup --docker` - Full Docker CE + Sysbox installation (formerly the script)
- `cai setup` (no flag) - Just Sysbox + context (current behavior)

**Functionality to merge:**

From `scripts/install-containai-docker.sh`:
1. `install_docker_ce()` - Install docker-ce via apt/yum/dnf
2. `disable_default_docker_service()` - Stop system Docker to avoid conflicts
3. `install_sysbox()` - Download and install Sysbox
4. `verify_sysbox_services()` - Ensure sysbox-mgr and sysbox-fs are running
5. `create_daemon_json()` - Configure separate daemon.json
6. `create_systemd_service()` - Create containai-docker.service
7. `create_directories()` - Create data/exec-root directories
8. `start_service()` - Enable and start service
9. `create_docker_context()` - Create docker-containai context
10. `verify_installation()` - Test with minimal container

**New lib/setup.sh structure:**
```bash
_cai_setup() {
    if [[ "$1" == "--docker" ]]; then
        _cai_setup_docker_full "$@"  # Full docker-ce + sysbox
    else
        _cai_setup_sysbox "$@"       # Just sysbox + context (existing)
    fi
}

_cai_setup_docker_full() {
    # Merged functionality from install-containai-docker.sh
    # Requires sudo
}
```

**Preserved options:**
- `--dry-run` - Show what would be done
- `--verbose` - Detailed progress

## Acceptance

- [ ] `cai setup --docker` installs docker-ce + Sysbox (formerly script functionality)
- [ ] `cai setup` (no flag) works as before (Sysbox + context)
- [ ] `--dry-run` works with new docker setup
- [ ] `--verbose` shows detailed progress
- [ ] All checks from original script are preserved
- [ ] Service creation and verification work correctly

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
