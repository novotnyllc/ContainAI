# Fix sysbox version detection, Docker context, and SSH key injection

Three independent bugs causing `cai update` and `cai doctor fix` to malfunction:

1. **Version comparison false positive** → triggers unnecessary update, stops containers
2. **Docker context validation ignores WSL2** → "repairs" working SSH context to broken unix socket
3. **SSH key injection has no verification** → reports `[FIXED]` but SSH still fails with "Permission denied"

## Bug Details

### Bug 1: Version detection returns empty string
- `_cai_sysbox_installed_version()` uses `sysbox-runc --version | head -1`
- New sysbox outputs multiline format, `head -1` returns "sysbox-runc" not version
- Function returns exit 0 with empty stdout
- Empty string compared to "0.6.7" triggers false "upgrade available"

### Bug 2: Context validation hard-codes unix:// for non-macOS
- `_cai_update_docker_context()` in `update.sh`: `expected_host="unix://$_CAI_CONTAINAI_DOCKER_SOCKET"`
- Never checks `_cai_is_wsl2()` - always expects unix socket
- On WSL2, correct endpoint is `ssh://containai-docker-daemon/var/run/containai-docker.sock`
- "Repair" corrupts working SSH context

### Bug 3: Key injection reports success without verification
- `cai doctor fix container --all` runs key injection via `docker exec`
- Reports `[FIXED]` if `docker exec` returns 0
- **Does NOT verify** the key is actually in authorized_keys
- SSH fails with "Permission denied (publickey)" immediately after
- Script errors through SSH-based docker context may not propagate

## Quick commands

```bash
# Test version detection
source src/containai.sh
_cai_sysbox_installed_version && echo "OK: $(_cai_sysbox_installed_version)" || echo "FAIL"

# Test context detection
_cai_is_wsl2 && echo "WSL2" || echo "Not WSL2"
docker context inspect containai-docker --format '{{.Endpoints.docker.Host}}'

# Verify key injection (manual debug)
docker exec containai-xxx cat /home/agent/.ssh/authorized_keys
cat ~/.config/containai/id_containai.pub
```

## Scope

- `src/lib/setup.sh`: Fix version parsing functions
- `src/lib/update.sh`: Fix `_cai_update_docker_context()` for WSL2
- `src/lib/docker.sh`: Fix `_cai_expected_docker_host()` for WSL2
- `src/lib/ssh.sh`: Add key injection verification
- `src/lib/doctor.sh`: Add connectivity test after "fix"

## Acceptance

- [ ] `cai update` with identical versions shows "Sysbox is current"
- [ ] `cai update` on WSL2 does NOT change SSH context to unix
- [ ] `cai doctor fix container --all` only reports `[FIXED]` if SSH works
- [ ] `cai shell` works after doctor fix (end-to-end)
- [ ] Version display shows actual version, not "sysbox-runc"
