# fn-37-4xi.1 Create base-image-contract.md

## Description
Create `docs/base-image-contract.md` documenting what ContainAI expects from base images. This is the primary documentation deliverable covering filesystem layout, user requirements, services, entrypoint behavior, and validation.

## Acceptance
- [ ] File `docs/base-image-contract.md` exists
- [ ] Document has these sections:
  - Contract Target (which images this applies to)
  - Required > Filesystem Layout (lists /home/agent, /mnt/agent-data, /opt/containai, /usr/local/lib/containai/init.sh)
  - Required > User (agent UID 1000, passwordless sudo, bash shell)
  - Required > Services (containai-init.service, OpenSSH, Docker daemon)
  - Required > Entrypoint/CMD Requirements (explains no command passed, systemd as PID 1, failure modes)
  - Required > Environment (container=docker, STOPSIGNAL, PATH)
  - Recommended > AI Agents
  - Recommended > SDKs
  - Validation Behavior (FROM-based validation, not layer history)
  - Warning Suppression (links to configuration.md)
- [ ] Validation section lists all three accepted patterns:
  - `ghcr.io/novotnyllc/containai*`
  - `containai:*`
  - `containai-template-*:local`
- [ ] Quick commands use correct CLI syntax:
  - `cai exec -- <cmd>` (from workspace dir)
  - `cai exec --container <name> -- <cmd>` (specific container)
  - NOT `docker run` with commands (fails due to systemd ENTRYPOINT)
- [ ] Document builds/renders without errors

## Done summary
Created `docs/base-image-contract.md` documenting what ContainAI expects from base images.

## Sections included:
- **Contract Target**: Images used in template Dockerfiles and `--image-tag`
- **Required > Filesystem Layout**: `/home/agent`, `/mnt/agent-data`, `/opt/containai`, `/usr/local/lib/containai/init.sh`
- **Required > User**: agent UID 1000, passwordless sudo, bash shell
- **Required > Services**: containai-init.service, ssh.service (OpenSSH), docker.service, containerd.service
- **Required > Entrypoint/CMD Requirements**: No command passed, systemd as PID 1, failure modes documented
- **Required > Environment**: container=docker, STOPSIGNAL, PATH with /home/agent/.local/bin
- **Recommended > AI Agents**: Claude Code CLI location
- **Recommended > SDKs**: Node.js via nvm, Python via uv/pipx
- **Validation Behavior**: FROM-based validation, not layer history
- **Warning Suppression**: Links to configuration.md#template-section

## Acceptance criteria verified:
- All three accepted patterns documented: `ghcr.io/novotnyllc/containai*`, `containai:*`, `containai-template-*:local`
- Quick commands use correct CLI syntax: `cai exec -- <cmd>` and `cai exec --container <name> -- <cmd>`
- Does NOT use `docker run` with commands (documents why this fails due to systemd ENTRYPOINT)
## Evidence
- Commits:
- Tests:
- PRs:
