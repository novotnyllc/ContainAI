# fn-7-j5o.7 Create architecture overview

## Description
Create an architecture overview document with Mermaid diagrams explaining system components, data flow, and security boundaries.

**Size:** M
**Files:** `docs/architecture.md`

## Approach

- Use Mermaid diagrams (renders natively on GitHub)
- Include: system context, component diagram, data flow, security boundaries
- Explain modular lib/*.sh structure
- Document volume lifecycle and data persistence
- Reference ADRs from `.flow/memory/decisions.md`

## Key Context

- Modular design: `containai.sh` sources `lib/*.sh` modules
- Two execution paths: ECI (Docker Desktop) or Sysbox
- Volumes: data volume (per-agent) + workspace mount (per-workspace)
- Security: user namespaces, seccomp, network isolation options
- Key files: `lib/core.sh`, `lib/platform.sh`, `lib/docker.sh`, `lib/eci.sh`, `lib/container.sh`, `lib/config.sh`
## Acceptance
- [ ] docs/architecture.md exists
- [ ] Includes system context Mermaid diagram
- [ ] Includes component/module diagram
- [ ] Explains data flow from CLI to container
- [ ] Documents security boundaries (host vs sandbox)
- [ ] Explains lib/*.sh modular structure
- [ ] Documents volume types and lifecycle
- [ ] References relevant ADRs for design decisions
- [ ] All diagrams render correctly on GitHub
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
