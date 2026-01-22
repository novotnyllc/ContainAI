# fn-10-vep.31 Convert ASCII box diagrams to mermaid

## Description
Convert ASCII art diagrams with nested boxes to mermaid format for better maintainability and contrast.

**Size:** S
**Files:**
- README.md (lines 48-66)
- docs/quickstart.md (lines 65-96, 147-162)

## Context

The codebase has 3 ASCII diagrams with nested box structures that should be converted to mermaid:

1. **README.md (48-66)** - Architecture diagram showing:
   - Host Machine → Docker Desktop/Sysbox → ContainAI Sandbox
   - Nested 3-level hierarchy

2. **docs/quickstart.md (65-96)** - Runtime decision tree showing:
   - cai doctor → ECI Path / Sysbox Path → Ready to run
   - Decision flow with fallback options

3. **docs/quickstart.md (147-162)** - "What Just Happened" architecture:
   - Same 3-level hierarchy as README

## Approach

1. Convert each ASCII diagram to mermaid flowchart syntax
2. Apply the dark theme styling from fn-10-vep.29:
   ```mermaid
   %%{init: {'theme': 'base', 'themeVariables': {
     'primaryColor': '#1a1a2e',
     'primaryTextColor': '#ffffff',
     'primaryBorderColor': '#16213e',
     'secondaryColor': '#0f3460',
     'tertiaryColor': '#1a1a2e',
     'lineColor': '#a0a0a0',
     'textColor': '#ffffff',
     'background': '#0d1117'
   }}}%%
   ```
3. Use subgraphs for nested hierarchies
4. Test rendering in GitHub light and dark modes

## Key context

- Task fn-10-vep.29 already established the mermaid theme pattern
- Keep ASCII trees for file structures (they're clearer as text)
- Focus on architecture/hierarchy diagrams where mermaid adds value
## Acceptance
- [ ] README.md architecture diagram converted to mermaid with subgraphs
- [ ] docs/quickstart.md decision tree converted to mermaid flowchart
- [ ] docs/quickstart.md "What Just Happened" diagram converted to mermaid
- [ ] All diagrams use dark theme from fn-10-vep.29
- [ ] Diagrams render correctly in GitHub light mode
- [ ] Diagrams render correctly in GitHub dark mode
- [ ] ASCII version removed (no duplicates)
## Done summary
Converted 3 ASCII box diagrams to mermaid flowcharts with dark theme styling: README.md architecture diagram, quickstart.md runtime decision tree, and quickstart.md "What Just Happened" architecture diagram.
## Evidence
- Commits: c0b0704, 3cf17d9, 21f46e0
- Tests: visual inspection of mermaid syntax
- PRs: