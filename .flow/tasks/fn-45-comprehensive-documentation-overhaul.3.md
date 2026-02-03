# fn-45-comprehensive-documentation-overhaul.3 Create persona-based landing pages

## Description
Create three persona-based landing pages that provide tailored entry points for different audiences. Each page curates existing docs with persona-specific context and recommended reading order.

**Size:** M
**Files:**
- `docs/for-users.md` (new)
- `docs/for-contributors.md` (new)
- `docs/for-security-auditors.md` (new)

## Approach

1. **For Users** (`docs/for-users.md`):
   - "You want to run AI agents safely"
   - Quick path: quickstart → usage patterns → configuration
   - Highlight: preferences sync, ephemeral/persistent modes
   - Link to troubleshooting
   - **Include**: Visual navigation map showing doc relationships

2. **For Contributors** (`docs/for-contributors.md`):
   - "You want to improve ContainAI"
   - Quick path: CONTRIBUTING.md → architecture (summary) → testing
   - Highlight: code structure, conventions, good first issues
   - Link to `.flow/memory/conventions.md` patterns
   - **Include**: Visual map of code/docs structure

3. **For Security Auditors** (`docs/for-security-auditors.md`):
   - "You want to evaluate ContainAI's security"
   - Quick path: SECURITY.md → threat model → security-scenarios
   - Highlight: isolation guarantees, non-goals, attack surface
   - Link to Sysbox documentation
   - **Include**: Security documentation hierarchy diagram

4. Follow patterns from:
   - Diataxis framework (orientation-first content)
   - GitBook personas guide
   - coder/coder docs structure (user-guides/, admin/)

5. **Each landing page should have a Mermaid flowchart** showing the recommended reading path and how docs relate to each other. Include `accTitle` and `accDescr` for accessibility.

## Key context

Current docs assume users will navigate themselves. Research shows personas need curated paths:
- Users care about "how fast can I be productive"
- Contributors care about "how do I not break things"
- Auditors care about "what are the assumptions and limits"

## Acceptance
- [ ] Three landing pages created with persona-specific intros
- [ ] Each page has recommended reading order (numbered list)
- [ ] Each page links to 5-8 relevant existing docs
- [ ] Each page has "Start here" section with 2-3 steps
- [ ] Cross-links between personas where relevant
- [ ] README updated to link to these pages
- [ ] No duplicate content - pages curate, not copy
- [ ] **Each page has a Mermaid navigation/reading path diagram** (include `accTitle`/`accDescr`)

## Done summary
Created three persona-based landing pages that provide tailored entry points for different audiences:

1. **docs/for-users.md** - "You want to run AI agents safely"
   - 3-step "Start Here" section for quick onboarding
   - Reading order: quickstart → configuration → lifecycle → CLI reference → troubleshooting
   - Highlights: preferences sync, ephemeral/persistent modes, multiple agents
   - Mermaid diagram with accTitle/accDescr for accessibility

2. **docs/for-contributors.md** - "You want to improve ContainAI"
   - 3-step "Start Here" for forking and environment setup
   - Reading order: CONTRIBUTING → architecture → testing → config → CLI → sync
   - Highlights: code structure, shell conventions, testing tiers, good first issues
   - Links to conventions.md and pitfalls.md

3. **docs/for-security-auditors.md** - "You want to evaluate ContainAI's security"
   - 3-step "Start Here" for threat model review
   - Reading order: SECURITY → scenarios → comparison → architecture → base image contract
   - Highlights: isolation model, non-goals, attack surface, key implementation files
   - Links to Sysbox docs and relevant CVEs

Updated README.md "Jump to:" links to point to new persona pages.
## Evidence
- Commits:
- Tests:
- PRs:
