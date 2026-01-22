# fn-10-vep.37 Fix Lima VM docker group membership and socket permissions

## Description
Fix the Lima VM "socket exists but docker info failed" issue. Handle both new VMs and existing VMs that need repair.

**Size:** M  
**Files:** `src/lib/setup.sh`, `src/lib/doctor.sh`

## Approach

1. **Fix for new VMs** in Lima provision script:
   ```bash
   usermod -aG docker ${LIMA_CIDATA_USER}
   ```

2. **Fix for existing VMs** in `cai setup`:
   - Detect existing containai-secure VM: `limactl list | grep containai-secure`
   - Test docker access: `limactl shell containai-secure docker info`
   - If permission denied: 
     ```bash
     limactl shell containai-secure sudo usermod -aG docker $USER
     limactl stop containai-secure
     limactl start containai-secure
     ```

3. **Enhanced diagnostics in `cai doctor`**:
   - Check socket exists: `test -S ~/.lima/containai-secure/sock/docker.sock`
   - Test docker info via socket
   - Distinguish failure modes:
     - Socket missing → "Lima VM not running or not provisioned"
     - Permission denied → "User not in docker group, restart VM"
     - Connection refused → "Docker daemon not running inside VM"

4. **Specific remediation messages** for each failure mode

## Key context

- Adding user to docker group requires new login session
- SSH master socket persists old group membership
- Must restart Lima VM (stop + start) for group change to take effect
- provision scripts only run on VM creation, not on existing VMs
## Approach

1. Update Lima provision script:
   ```bash
   usermod -aG docker ${LIMA_CIDATA_USER}
   ```

2. After docker group change, Lima VM must be restarted:
   - SSH master socket persists old group membership
   - `cai setup` should restart VM after initial provision
   - Or: provision script triggers reboot

3. Add probe to verify docker access:
   ```yaml
   probes:
     - script: |
         if ! docker info >/dev/null 2>&1; then exit 1; fi
       hint: Waiting for Docker access (may need VM restart)
   ```

4. Update `cai doctor` to detect this issue:
   - Check if socket exists
   - Check if docker info succeeds
   - If socket exists but info fails, suggest: "Try restarting Lima VM"

## Key context

- Lima socket path: `~/.lima/<vm>/sock/docker.sock`
- Docker group change requires new login session
- `limactl stop && limactl start` restarts VM
- User's original error: "socket exists but docker info failed"
## Acceptance
- [ ] Lima provision script adds user to docker group
- [ ] `cai setup` detects existing containai-secure VM
- [ ] `cai setup` tests docker access in existing VM
- [ ] `cai setup` repairs existing VM (usermod + restart) if needed
- [ ] `cai doctor` distinguishes: socket missing vs permission denied vs daemon down
- [ ] Specific remediation message for each failure mode
- [ ] After setup, `docker info` works via Lima socket
- [ ] No manual intervention required for new or existing VMs
## Done summary
Implemented Lima VM docker group repair and enhanced failure diagnostics. Added _cai_lima_repair_docker_access() to automatically fix permission denied errors by adding user to docker group and restarting VM. Enhanced cai doctor with socket existence check and platform-specific remediation messages for macOS/Lima failures.
## Evidence
- Commits: 79440fd, 50740923b36697a8944ac10e0aca86805ac59cec
- Tests: bash -n src/lib/setup.sh, bash -n src/lib/doctor.sh, source all libs
- PRs: