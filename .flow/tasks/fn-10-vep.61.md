# fn-10-vep.61 Rewrite main README.md with value prop and quick start

## Description
Rewrite main README.md with clear value proposition around **system containers** - VM-like containers that can run systemd, services, and Docker itself. No references to previous versions, migrations, or legacy features.

**Size:** M
**Files:** README.md

## Key Message: System Containers

The README should explain what makes ContainAI different:
- **System containers** - Not just app containers, but VM-like environments
- **systemd as PID 1** - Real init system, multiple services
- **Docker-in-Docker** - Agents can build/run containers without --privileged
- **Automatic isolation** - Sysbox handles user namespace mapping automatically
- **SSH access** - VS Code Remote-SSH, agent forwarding, port tunneling

## Approach

1. Hero section:
   - One-line value prop: "Secure system containers for AI coding agents"
   - What is a system container: VM-like behavior, systemd, services, DinD
   - Why this matters: isolation, DinD without --privileged, SSH access

2. Quick start (copy-paste ready):
   ```bash
   curl -fsSL https://containai.dev/install.sh | bash
   cai setup
   cai run .
   ```

3. Key capabilities:
   - System container with systemd
   - DinD without --privileged (sysbox handles it)
   - SSH access (VS Code Remote-SSH compatible)
   - Automatic user namespace isolation

4. Links to detailed docs

## Key context

- README is the primary landing page for GitHub visitors
- Must immediately communicate the "system container" value proposition
- Follow patterns from popular CLI tools (gh, rg, fd)
- Sysbox handles userns mapping automatically - no manual config needed
## Acceptance
- [ ] README.md rewritten with value proposition
- [ ] Quick start section with install and first run
- [ ] Features section with current capabilities
- [ ] Links to documentation
- [ ] NO legacy references or migration notes
- [ ] NO changelog or version history
- [ ] Reads as if this is the first and only version
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
