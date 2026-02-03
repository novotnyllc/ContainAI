# fn-46-cli-ux-audit-and-simplification.4 Produce prioritized recommendations document

## Description
Synthesize findings from tasks .1-.3 into a prioritized recommendations document that can guide future CLI improvements. Output is an **internal planning document** in `.flow/specs/`, not user-facing documentation.

**Size:** M
**Files:** `.flow/specs/cli-ux-recommendations.md` (new)

## Approach

### Step 1: Synthesize Findings
- Heuristic evaluation results (.1) - scores and help checklist gaps
- Flag consistency audit (.2) - matrix and inconsistencies
- Error message audit (.3) - templates and scores

### Step 2: Categorize Recommendations

| Category | Description | Approval |
|----------|-------------|----------|
| **Quick wins** | Low effort, high impact, no breaking changes | Implement now |
| **Medium effort** | Moderate complexity, clear benefit | Plan for next release |
| **Breaking changes** | Require deprecation cycle | Requires RFC/approval |

### Step 3: Prioritize by Impact × Frequency

**Scoring formula:** Impact (1-5) × Frequency (1-5) = Priority score

| Impact | Description |
|--------|-------------|
| 1 | Affects edge case only |
| 2 | Affects power users occasionally |
| 3 | Affects regular workflow sometimes |
| 4 | Affects common workflow often |
| 5 | Affects every user every time |

**Tie-breaker:** Lower effort wins

### Step 4: Cross-Reference with Existing Epics

**REQUIRED field per recommendation:**

```markdown
**Owner epic:** fn-36-rb7 / fn-42 / fn-45 / NEW
**Status:** already planned / partially planned / new
```

Mapping:
- **fn-36-rb7** (CLI UX Consistency): Flag normalization, help text, completion
- **fn-42** (CLI UX Fixes): Short container names, hostname fixes
- **fn-45** (Documentation): CLI reference documentation (user-facing docs)
- **NEW**: Needs new epic filed

### Step 5: Document Format

```markdown
# CLI UX Audit Recommendations

## Executive Summary
- Total recommendations: N
- Quick wins: N (implement now)
- Medium effort: N (next release)
- Breaking changes: N (requires RFC)
- Top 3 priorities: [list]

## Quick Wins (implement now)
### REC-001: [Title]
**Category:** Quick win
**Priority:** [Impact × Frequency = score]
**Effort:** Low
**Breaking:** No
**Owner epic:** fn-36-rb7 | Status: already planned

**Current:** [Current behavior]
**Proposed:** [Proposed change]
**Rationale:** [Why this improves UX]

## Medium Effort (next release)
### REC-00N: [Title]
...

## Breaking Changes (requires RFC)
### REC-00N: [Title]
...
**Migration path:** [How users transition]

## Appendix A: Full Audit Data
- Heuristic scores table
- Flag consistency matrix
- Error message templates with scores

## Appendix B: Epic Cross-Reference
| Recommendation | Owner Epic | Status |
|----------------|------------|--------|
| REC-001 | fn-36-rb7 | planned |
| REC-002 | NEW | - |
...
```

## Key context

Output informs:
- fn-36-rb7 remaining tasks (if any)
- fn-42 scope validation
- fn-45 documentation (CLI reference)
- Future CLI improvement epics

**Output location:** `.flow/specs/cli-ux-recommendations.md` (internal planning doc)
**NOT:** `docs/` (user-facing docs are fn-45's scope)

## Acceptance
- [ ] All findings from .1-.3 synthesized
- [ ] Recommendations categorized (quick-win, medium, breaking)
- [ ] Each recommendation has Impact × Frequency priority score
- [ ] Each recommendation has **Owner epic** field
- [ ] Each recommendation has **Status** field (already planned / new)
- [ ] Cross-reference appendix links to fn-36-rb7, fn-42, fn-45
- [ ] Document written to `.flow/specs/cli-ux-recommendations.md`
- [ ] Executive summary suitable for stakeholder review

## Done summary
# fn-46.4 Completion Summary

Synthesized findings from tasks .1-.3 into prioritized recommendations document.

## Key Deliverables

- Created `.flow/specs/cli-ux-recommendations.md` with 25 prioritized recommendations
- Categorized: 10 quick wins, 10 medium effort, 5 breaking changes
- Top 3 priorities identified: template discoverability, error actionability, flag consistency
- Cross-referenced all recommendations with owner epics (fn-36-rb7, fn-42, fn-45, NEW)
- Included full audit data appendices (heuristic scores, flag matrix, error templates)

## Document Structure

1. Executive Summary with metrics
2. Quick Wins (10 recommendations, implement now)
3. Medium Effort (10 recommendations, next release)
4. Breaking Changes (5 recommendations, requires RFC)
5. Appendix A: Full Audit Data
6. Appendix B: Epic Cross-Reference

## Source Documents Synthesized

1. fn-46.1: `.flow/specs/cli-ux-heuristic-evaluation.md`
2. fn-46.2: `.flow/specs/flag-naming-consistency-audit.md`
3. fn-46.3: `docs/reports/fn-46.3-error-message-audit.md`
## Evidence
- Commits:
- Tests: N/A (analysis document, no code changes)
- PRs:
