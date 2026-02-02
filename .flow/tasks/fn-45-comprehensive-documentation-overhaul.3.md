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

2. **For Contributors** (`docs/for-contributors.md`):
   - "You want to improve ContainAI"
   - Quick path: CONTRIBUTING.md → architecture (summary) → testing
   - Highlight: code structure, conventions, good first issues
   - Link to `.flow/memory/conventions.md` patterns

3. **For Security Auditors** (`docs/for-security-auditors.md`):
   - "You want to evaluate ContainAI's security"
   - Quick path: SECURITY.md → threat model → security-scenarios
   - Highlight: isolation guarantees, non-goals, attack surface
   - Link to Sysbox documentation

4. Follow patterns from:
   - Diataxis framework (orientation-first content)
   - GitBook personas guide
   - coder/coder docs structure (user-guides/, admin/)

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
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
