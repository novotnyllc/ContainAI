# fn-7-j5o.1 Create root README.md

## Description
Create a root README.md as the project's entry point. This is the first thing users see when they land on the GitHub repo.

**Size:** S
**Files:** `README.md`

## Approach

- Follow pattern from GitHub CLI (`cli/cli`) and Docker Compose README structures
- Lead with clear value proposition: "Secure Docker sandboxes for AI agent execution"
- Include 3-step quickstart (source CLI → authenticate → run)
- Progressive disclosure: link to detailed docs, don't duplicate content
- Reference existing `agent-sandbox/README.md` for technical depth

## Key Context

- Current main docs are in `agent-sandbox/README.md` (1200+ lines)
- CLI is `cai` or `containai` (bash-based, requires sourcing)
- Multi-agent support: Claude, Gemini, Codex, Copilot, OpenCode
- Two isolation modes: Docker Desktop ECI or Sysbox
## Acceptance
- [ ] README.md exists at project root
- [ ] Opens with clear one-line value proposition
- [ ] Includes badge row (license, build status if CI exists)
- [ ] 3-step quickstart with copy-paste commands
- [ ] Table of Contents for navigation
- [ ] Links to docs/quickstart.md, SECURITY.md, CONTRIBUTING.md
- [ ] Links to agent-sandbox/README.md for detailed technical docs
- [ ] Renders correctly on GitHub
## Done summary
Created root README.md as project entry point with value proposition, 3-step quickstart (source CLI, authenticate, run), badge row, and navigation links. Added required stub files (LICENSE, SECURITY.md, CONTRIBUTING.md, docs/quickstart.md) to satisfy acceptance criteria for link targets.
## Evidence
- Commits: bfd3ac9, 10a2388, 69254f8, 286f6a9
- Tests:
- PRs:
