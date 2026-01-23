# fn-10-vep.69 Create comprehensive setup documentation (docs/setup-guide.md)

## Description
Create detailed setup documentation covering the complex multi-component installation. The setup involves host-level systemd services, Docker contexts, SSH key management, and Sysbox configuration across WSL2, native Linux, and macOS (via Lima).

**Size:** M
**Files:** docs/setup-guide.md

## What This Enables

Users can understand:
- What components are installed and where
- Platform-specific setup differences
- What `cai setup` does under the hood
- How to verify the installation worked
- How to troubleshoot setup failures

## Approach

1. **Overview section**:
   - What gets installed (diagram/list)
   - Platform differences at a glance (table)
   - Prerequisites checklist

2. **Platform-specific sections**:
   - **WSL2**: systemd requirement, seccomp considerations, dedicated socket
   - **Native Linux**: Ubuntu/Debian auto-install, manual install for others
   - **macOS**: Lima VM setup, Homebrew dependency

3. **Component breakdown**:
   - **Host Docker configuration**:
     - Drop-in at `/etc/systemd/system/docker.service.d/` (WSL2)
     - Daemon.json with sysbox-runc runtime
     - Dedicated socket `/var/run/containai-docker.sock` (WSL2) vs default socket (Linux)
   - **Docker context**: `containai-secure` pointing to appropriate socket
   - **Sysbox installation**: sysbox-runc, sysbox-mgr, sysbox-fs services
   - **SSH infrastructure**:
     - Key at `~/.config/containai/id_containai`
     - Config dir at `~/.ssh/containai.d/`
     - Include directive in `~/.ssh/config`
   - **User config**: `~/.config/containai/config.toml`

4. **Verification section**:
   - How to run `cai doctor`
   - Expected output interpretation
   - Manual verification commands

5. **Troubleshooting section**:
   - Link to docs/troubleshooting.md
   - Quick fixes for common setup failures

## Key context

- Setup differs significantly between WSL2 and native Linux
- WSL2 uses dedicated socket to avoid Docker Desktop conflicts
- Native Linux uses the default Docker socket
- macOS requires Lima VM - completely different approach
- Reference existing code in `src/lib/setup.sh` for accuracy
- Pattern: Follow Sysbox official docs for service descriptions

## Acceptance
- [ ] docs/setup-guide.md created
- [ ] Covers all three platforms (WSL2, Linux, macOS)
- [ ] Diagram or table showing what gets installed
- [ ] Component locations documented with actual paths
- [ ] Prerequisites section with version requirements
- [ ] Verification section with `cai doctor` explanation
- [ ] Links to troubleshooting docs
- [ ] Copy-paste commands where helpful

## Done summary
Created comprehensive setup documentation (docs/setup-guide.md) covering WSL2, native Linux, and macOS platforms with prerequisites, component locations, verification steps, and troubleshooting guidance.
## Evidence
- Commits: 038dd613c716efc897183fe8c03b02277a9229f6
- Tests: Verified documentation against acceptance criteria, Manual review of all platform sections
- PRs:
