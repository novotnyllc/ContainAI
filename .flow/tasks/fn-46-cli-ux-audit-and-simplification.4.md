# fn-46-cli-ux-audit-and-simplification.4 Produce prioritized recommendations document

## Description
Synthesize findings from tasks .1-.3 into a prioritized recommendations document that can guide future CLI improvements.

**Size:** M
**Files:** `docs/cli-ux-audit.md` (new) or `.flow/specs/cli-ux-recommendations.md`

## Approach

1. Synthesize findings:
   - Heuristic evaluation results (.1)
   - Flag consistency audit (.2)
   - Error message audit (.3)

2. Categorize recommendations:
   - **Quick wins**: Low effort, high impact, no breaking changes
   - **Medium effort**: Moderate complexity, clear benefit
   - **Breaking changes**: Require deprecation cycle, significant benefit

3. Prioritize by:
   - User impact (how many users affected, how often)
   - Implementation effort (estimated complexity)
   - Risk (breaking changes, backward compatibility)

4. Document format:
   ```markdown
   # CLI UX Audit Recommendations

   ## Executive Summary
   ## Quick Wins (implement now)
   ## Medium Effort (next release)
   ## Breaking Changes (requires RFC)
   ## Appendix: Full Audit Data
   ```

5. Cross-reference with existing epics:
   - What's already planned in fn-36-rb7?
   - What's already planned in fn-42?
   - What's new and needs a new epic?

## Key context

Output should inform:
- fn-36-rb7 remaining tasks (if any)
- fn-45 documentation (CLI reference)
- Future CLI improvement epics

Recommendation template:
```markdown
### REC-001: Standardize --name to --container

**Category:** Quick win
**Impact:** High (affects daily usage)
**Effort:** Low (search-replace + deprecation warning)
**Breaking:** Yes (soft - add deprecation warning)

**Current:** `cai links --name foo`
**Proposed:** `cai links --container foo` (with --name as deprecated alias)
**Rationale:** Consistency with all other commands
```
## Acceptance
- [ ] All findings from .1-.3 synthesized
- [ ] Recommendations categorized (quick-win, medium, breaking)
- [ ] Each recommendation has impact/effort/risk assessment
- [ ] Cross-referenced with fn-36-rb7 and fn-42 scope
- [ ] Document written and committed to repo
- [ ] Executive summary suitable for stakeholder review
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
