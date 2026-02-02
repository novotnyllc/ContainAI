# fn-45-comprehensive-documentation-overhaul.7 Add Mermaid diagrams to existing documentation

## Description
Add Mermaid diagrams to existing documentation files that currently lack visual aids for complex flows, states, or relationships. These files have dense text/tables that would benefit significantly from visual diagrams.

**Size:** M
**Files:**
- `docs/sync-architecture.md` (HIGH priority)
- `docs/setup-guide.md` (HIGH priority)
- `docs/configuration.md` (HIGH priority)
- `docs/adding-agents.md` (MEDIUM priority)
- `docs/acp.md` (MEDIUM priority - convert ASCII art)
- `docs/testing.md` (MEDIUM priority)

## Approach

### HIGH PRIORITY Files

1. **sync-architecture.md** (currently 0 diagrams):
   - Add **data flow diagram** showing: Host configs → rsync → Volume → Container symlinks
   - Show the 3-component sync system: import.sh → Dockerfile.agents → containai-init.sh
   - Visualize sync map relationships (source → target → container_link)
   - Follow pattern at `docs/architecture.md:561-600` (data flow diagram)

2. **setup-guide.md** (currently 0 diagrams):
   - Add **installation decision tree** for platform selection (WSL2 vs Linux vs macOS/Lima)
   - Show component stack: What gets installed and in what order
   - Follow pattern at `docs/quickstart.md:64-100` (doctor check flowchart)

3. **configuration.md** (currently 0 diagrams):
   - Add **precedence hierarchy flowchart**: CLI flags > env vars > workspace config > global config > defaults
   - Add **config discovery flowchart**: How config file is located (walk up tree, stop at git root)
   - Follow pattern at `docs/architecture.md:103-130` (architecture layers)

### MEDIUM PRIORITY Files

4. **adding-agents.md** (currently 0 diagrams):
   - Add **6-step workflow diagram** showing agent addition process
   - Visualize path mapping: source → target → container_link conventions

5. **acp.md** (currently has ASCII art at line 33):
   - **Convert ASCII diagram** to Mermaid sequence diagram
   - Current ASCII: `Editor → ACP stdio → Proxy → cai exec → Container → Agent`
   - Follow pattern at `docs/architecture.md:281-340` (SSH connection sequence)

6. **testing.md** (currently 0 diagrams):
   - Add **test tier diagram** showing Tier 1 (lint) → Tier 2 (integration) → Tier 3 (E2E)
   - Add **CI workflow diagram** showing job dependencies

## Key context

**Theme requirement**: All diagrams MUST use the standard dark theme from the epic spec:
```
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

**Accessibility**: Include `accTitle` and `accDescr` in each diagram for screen readers.

**Existing examples to follow**:
- `docs/architecture.md:49-83` (Flowchart with subgraphs)
- `docs/architecture.md:168-229` (Sequence diagram)
- `docs/lifecycle.md:9-30` (State diagram)

**Test diagrams** at https://mermaid.live/ before committing to ensure GitHub renders correctly.
## Acceptance
### HIGH PRIORITY (must complete)
- [ ] sync-architecture.md has data flow diagram showing host → rsync → volume → symlink
- [ ] sync-architecture.md has 3-component sync system diagram
- [ ] setup-guide.md has platform decision tree (WSL2 vs Linux vs macOS)
- [ ] setup-guide.md has component installation stack diagram
- [ ] configuration.md has precedence hierarchy flowchart
- [ ] configuration.md has config discovery flowchart

### MEDIUM PRIORITY (should complete)
- [ ] adding-agents.md has 6-step workflow diagram
- [ ] acp.md ASCII art converted to Mermaid sequence diagram
- [ ] testing.md has test tier hierarchy diagram

### Quality Requirements
- [ ] All diagrams use standard dark theme from epic spec
- [ ] All diagrams include `accTitle` and `accDescr` for accessibility
- [ ] All diagrams render correctly on GitHub (test before merge)
- [ ] Diagrams are placed immediately after relevant section headings
- [ ] No diagram exceeds 30 nodes (split if larger)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
