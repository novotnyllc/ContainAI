# fn-10-vep.29 Fix mermaid chart contrast in all docs

## Description
Fix mermaid chart contrast issues in all documentation to meet WCAG AA standards.

**Size:** S
**Files:**
- All .md files with mermaid diagrams

## Approach

1. Find all mermaid diagrams in docs
2. Add explicit style declarations with good contrast
3. Use dark backgrounds with white text
4. Test rendering in GitHub and VS Code

## Style template

```mermaid
graph LR
    A[Step 1] --> B[Step 2]
    style A fill:#1a1a2e,stroke:#16213e,color:#fff
    style B fill:#0f3460,stroke:#16213e,color:#fff
```
## Acceptance
- [ ] All mermaid diagrams have explicit styles
- [ ] Contrast meets WCAG AA (4.5:1 ratio)
- [ ] Diagrams readable in GitHub dark mode
- [ ] Diagrams readable in GitHub light mode
- [ ] No default gray-on-gray text
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
