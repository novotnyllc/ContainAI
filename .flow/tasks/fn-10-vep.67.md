# fn-10-vep.67 Create security comparison docs: sysbox vs Docker sandbox vs alternatives

## Description
Create comprehensive documentation comparing ContainAI's sysbox-based system containers with other AI agent sandboxing solutions. This helps developers understand why system containers provide stronger isolation and when to use them.

**Size:** L
**Files:** docs/security-comparison.md

## Why This Matters

Developers choosing sandboxing solutions need to understand:
1. What each solution actually protects against
2. Trade-offs between isolation strength and capabilities
3. Why system containers are needed for certain use cases (DinD, systemd)

## Solutions to Compare

### 1. Docker Desktop "docker sandbox" (experimental)
- **What it is**: AI agent workspace mirroring (Docker Desktop 4.50+, Dec 2025)
- **Isolation**: Standard runc container, no user namespaces by default
- **DinD**: Yes (Docker CLI in template)
- **Limitations**: Experimental, no syscall filtering, agent has sudo
- **Key point**: NOT the same as ECI/sysbox - uses standard runc

### 2. Docker Desktop ECI (Enhanced Container Isolation)
- **What it is**: Sysbox integrated into Docker Desktop (Business tier only)
- **Isolation**: User namespaces always, syscall vetting, /proc virtualization
- **DinD**: Yes, securely
- **Limitations**: Docker Business only, Linux containers only
- **Key point**: Same technology as sysbox, but requires subscription

### 3. Anthropic SRT (Sandbox Runtime)
- **What it is**: Lightweight process sandboxing (macOS: sandbox-exec, Linux: bubblewrap)
- **Isolation**: Filesystem allowlists, network proxy filtering
- **DinD**: No
- **systemd**: No
- **Limitations**: Process-level only, no Windows, not a container
- **Key point**: Good for lightweight isolation, not for system containers

### 4. Bubblewrap (bwrap)
- **What it is**: Low-level namespace sandboxing (used by Flatpak, SRT)
- **Isolation**: Namespaces, but user must configure everything
- **DinD**: No
- **Key point**: Building block, not a complete solution

### 5. gVisor
- **What it is**: User-space kernel that intercepts all syscalls
- **Isolation**: Strongest syscall isolation
- **DinD**: Partial (requires special flags)
- **systemd**: Limited compatibility
- **Key point**: 2-5x slower I/O, ~70% syscall coverage

### 6. Firecracker/Kata (microVMs)
- **What it is**: True VM isolation with ~125ms startup
- **Isolation**: Hardware-level (KVM)
- **DinD**: Yes
- **systemd**: Yes
- **Limitations**: Requires KVM, higher memory overhead
- **Key point**: Strongest isolation, but more resources

### 7. nsjail / Firejail
- **What it is**: Process sandboxing with seccomp
- **DinD**: No
- **systemd**: No
- **Key point**: Good for single-process isolation

## Comparison Table Format

Use a feature comparison table with these categories:

| Feature | Docker Sandbox | ECI/Sysbox | ContainAI | SRT | gVisor | microVM |
|---------|---------------|------------|-----------|-----|--------|---------|
| User namespaces | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ |
| Syscall filtering | ❌ | ✅ | ✅ | ❌ | ✅✅ | ✅ |
| DinD | ✅ | ✅ | ✅ | ❌ | ⚠️ | ✅ |
| systemd | ❌ | ✅ | ✅ | ❌ | ⚠️ | ✅ |
| Cost | Free | Business | Free | Free | Free | Varies |
| Startup | Fast | Fast | Fast | Instant | ~100ms | ~125ms |

Legend: ✅ = Full support, ⚠️ = Partial/Limited, ❌ = No support

## Key Messaging

### Why Docker Sandbox Isn't Enough
- Uses standard runc (no user namespace isolation by default)
- Agent runs with sudo access
- Experimental - commands may change
- "If the container escapes, you have host root"

### Why ECI Requires Business Tier
- Same sysbox technology we use
- Docker monetizes it for enterprise
- ContainAI gives you the same isolation for free

### Why SRT/Bubblewrap Isn't Enough for Our Use Case
- No DinD capability
- No systemd support
- Process-level only
- Good for simple agents, not system containers

### Why System Containers Matter
- AI agents that build/run containers need DinD
- Agents that run background services need systemd
- Full development environment needs multiple services
- ContainAI provides all of this with strong isolation

## Approach

1. Create docs/security-comparison.md with:
   - Overview of the sandboxing landscape
   - Detailed comparison table (see format above)
   - "What protects you from what" explanations
   - When to use each solution

2. Include visual aids:
   - Mermaid diagram of isolation layers
   - Color-coded security feature table

3. Keep it developer-friendly:
   - No jargon without explanation
   - Real-world implications for each feature
   - "What this means for you" sections

## Key context

Research completed shows:
- Docker sandbox (experimental) uses runc, NOT sysbox
- ECI IS sysbox (Docker acquired Nestybox in 2022)
- SRT uses bubblewrap on Linux, sandbox-exec on macOS
- gVisor has ~70-80% syscall coverage, 2-5x I/O overhead
- Firecracker powers AWS Lambda, ~125ms startup

## Acceptance
- [ ] docs/security-comparison.md created
- [ ] Comparison table with all major solutions
- [ ] Clear explanation of why Docker sandbox != ECI
- [ ] Clear explanation of why system containers matter
- [ ] Developer-friendly language (no unexplained jargon)
- [ ] Mermaid diagrams for isolation layers
- [ ] Links to source documentation for each solution
## Done summary
Created comprehensive security comparison documentation (docs/security-comparison.md) comparing ContainAI's Sysbox-based isolation with Docker Desktop sandbox, ECI, Anthropic SRT, gVisor, Firecracker/Kata microVMs, and other sandboxing solutions. Includes feature comparison tables with emoji legend, mermaid diagrams for isolation layers and decision flowchart, and clear explanations of why system containers matter for AI agents.
## Evidence
- Commits: 48c17a39b4c6a46a08bb62b4e3e6d28a3c14c8b7, 2f0dd28f7c893d7f2458c8e3b42a8f5f3e8c5b3a, 7882a956edfaf0afb8903f0768c22f04f14d7b3c
- Tests:
- PRs:
