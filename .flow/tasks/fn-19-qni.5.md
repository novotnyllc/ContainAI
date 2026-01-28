# fn-19-qni.5 Write agent sandboxing comparison doc

## Description
Create comprehensive documentation comparing ContainAI to other AI coding agent sandboxing approaches. This helps users understand ContainAI's position in the ecosystem and make informed decisions.

**Size:** M
**Files:** `docs/agent-sandboxing-comparison.md` (new)

## Approach

### Solutions to compare

| Tool | Runtime | Key Features |
|------|---------|--------------|
| **ContainAI** | Docker/Sysbox | Full development environment, SSH access, multi-agent |
| **OpenAI Codex CLI** | Landlock (Linux), Seatbelt (macOS), Windows Sandbox | Native OS sandboxing, minimal overhead |
| **Google Gemini CLI** | Seatbelt profiles, Docker/Podman | Profile-based (permissive/restrictive), network control |
| **E2B** | Firecracker microVMs | Hardware-level isolation, cloud-hosted |
| **Claude Code sandbox** | Docker | Docker Desktop integration, experimental |
| **Daytona** | Orchestration layer | Infrastructure management for dev environments |
| **Third-party Claude containers** | Docker | Community solutions (textcortex, tintinweb) |

### Comparison dimensions

1. **Isolation level**: Container vs VM vs namespace vs process
2. **Security boundaries**: Filesystem, network, syscalls
3. **Resource limits**: CPU, memory, disk
4. **Development experience**: SSH, IDE integration, persistence
5. **Platform support**: Linux, macOS, Windows
6. **Ease of setup**: Dependencies, configuration
7. **Performance overhead**: Startup time, runtime overhead

### Key sources (from github-scout research)

- Codex: `github.com/openai/codex/tree/main/codex-rs/linux-sandbox`
- Gemini: `github.com/google-gemini/gemini-cli/tree/main/packages/cli/src/utils`
- E2B infra: `github.com/e2b-dev/infra`
- E2B SDK: `github.com/e2b-dev/E2B`

### Structure

Follow existing `docs/security-comparison.md` structure but focus on agent-specific use cases.
## Acceptance
- [ ] Covers 6+ sandboxing approaches (Codex, Gemini, E2B, Claude, Daytona, third-party)
- [ ] Comparison table with key dimensions (isolation, security, platform)
- [ ] Technical details accurate (verified against source code/docs)
- [ ] Explains ContainAI's unique value proposition
- [ ] Links to official repos/documentation for each tool
- [ ] Discusses trade-offs (security vs convenience, cloud vs local)
- [ ] Format consistent with existing docs in `docs/`
- [ ] Added to docs index/navigation if applicable
## Done summary
Superseded - merged into fn-34-fk5
## Evidence
- Commits:
- Tests:
- PRs:
