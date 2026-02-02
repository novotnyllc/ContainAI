# fn-45-comprehensive-documentation-overhaul.1 README value proposition overhaul

## Description
Rewrite README.md to clearly communicate ContainAI's differentiated value proposition in the first 10 lines. Users should immediately understand why ContainAI vs Docker sandbox, SRT, or plain containers.

**Size:** M
**Files:** `README.md`

## Approach

1. Study existing value props in:
   - `README.md:8-22` (current capabilities table)
   - `docs/security-comparison.md` (competitor analysis)
   - `docs/architecture.md:41-98` (Sysbox benefits)

2. Craft messaging around three differentiators:
   - **VM-like isolation** without `--privileged` (Sysbox)
   - **Preferences sync** - feels like your local machine
   - **Ephemeral OR persistent** - your choice

3. Follow patterns from:
   - Best-README-Template: https://github.com/othneildrew/Best-README-Template
   - SWE-agent README structure (18k stars, similar tool)

4. Structure:
   - Hero line: Problem statement + solution
   - 30-second code demo
   - Three key differentiators with icons/emojis (only if existing style uses them)
   - Links to persona entry points

## Key context

Current README starts with "ContainAI provides secure system containers for AI coding agents" - this describes WHAT not WHY.

Competitors:
- Docker sandbox (Docker Desktop built-in) - less isolation, no sync
- SRT (Software Running Tool) - similar but different architecture
- Plain containers - no systemd, no DinD, no sync
## Acceptance
- [ ] First 10 lines answer "why ContainAI vs alternatives"
- [ ] 30-second code demo appears above the fold
- [ ] Three differentiators clearly stated
- [ ] Links to persona landing pages (placeholder links OK until .3 completes)
- [ ] No duplicate content with docs/ files
- [ ] Existing section structure preserved where still valid
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
