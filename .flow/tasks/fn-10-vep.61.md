# fn-10-vep.61 Rewrite main README.md with value prop and quick start

## Description
Rewrite main README.md with compelling value prop and quick start.

**Size:** M
**Files:** README.md

## Approach

1. Hero section:
   - One-line value prop: "Run AI coding agents in isolated containers - free"
   - Problem statement in 2-3 bullets
   - Visual: mermaid diagram or ASCII art showing architecture

2. Quick start (copy-paste ready):
   ```bash
   curl -fsSL https://containai.dev/install.sh | bash
   cai setup
   cai run .
   ```

3. Comparison table: ContainAI vs Docker Desktop sandbox vs devcontainers

4. Feature highlights with examples

5. Links to detailed docs

## Key context

- README is the primary landing page for GitHub visitors
- Must immediately communicate value and get users started
- Follow patterns from popular CLI tools (gh, rg, fd)
## Acceptance
- [ ] Hero section with clear value proposition
- [ ] Quick start in < 3 commands (copy-paste ready)
- [ ] Comparison table vs alternatives
- [ ] Feature highlights with examples
- [ ] Mermaid architecture diagram
- [ ] Links to detailed documentation
- [ ] Screenshot or gif showing typical workflow
- [ ] Badge row (license, version, CI status)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
