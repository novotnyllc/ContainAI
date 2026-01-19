# fn-5-urz.9 Unsafe opt-ins with acknowledgements

## Description
## Overview

Implement explicit unsafe opt-in flags with acknowledgement requirements per FR-5.

## Flags

### --allow-host-credentials
- Enables `docker sandbox run --credentials=host`
- Requires additional `--i-understand-this-exposes-host-credentials` flag
- Warns about exposure of `~/.ssh`, `~/.gitconfig`, etc.

### --allow-host-docker-socket
- Enables `docker sandbox run --mount-docker-socket`
- Requires `--i-understand-this-grants-root-access` flag
- Warns about root-level daemon access and sandbox escape risk

## Implementation

```bash
containai_run() {
    local allow_host_creds=false
    local allow_host_socket=false
    local ack_creds=false
    local ack_socket=false
    
    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --allow-host-credentials) allow_host_creds=true ;;
            --i-understand-this-exposes-host-credentials) ack_creds=true ;;
            --allow-host-docker-socket) allow_host_socket=true ;;
            --i-understand-this-grants-root-access) ack_socket=true ;;
            # ... other flags
        esac
        shift
    done
    
    # Validate acknowledgements
    if $allow_host_creds && ! $ack_creds; then
        _cai_error "--allow-host-credentials requires --i-understand-this-exposes-host-credentials"
        _cai_error "This will share ~/.ssh, ~/.gitconfig with the sandbox"
        return 1
    fi
    
    # Build command with unsafe options
    if $allow_host_creds; then
        cmd+=(--credentials=host)
        _cai_warn "Running with host credentials - ~/.ssh and ~/.gitconfig accessible"
    fi
}
```

## Config Support

```toml
[danger]
allow_host_credentials = false  # CLI override still requires ack flag
allow_host_docker_socket = false
```

Config can pre-allow but CLI still requires acknowledgement flag for audit trail.
## Acceptance
- [ ] `--allow-host-credentials` without ack flag fails with clear message
- [ ] `--allow-host-docker-socket` without ack flag fails with clear message
- [ ] Warning printed when unsafe option used (even with ack)
- [ ] Both flags together work correctly
- [ ] Config [danger] section doesn't bypass ack requirement
- [ ] Help text documents the risks of each flag
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
