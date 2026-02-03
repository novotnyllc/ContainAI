# fn-45-comprehensive-documentation-overhaul.7 Add Mermaid diagrams to existing documentation

## Description
Add Mermaid diagrams to existing documentation files that currently lack visual aids for complex flows, states, or relationships. **Also retrofit ALL existing diagrams with `accTitle`/`accDescr` for accessibility compliance.**

**Size:** L (upgraded from M due to retrofit scope)
**Files:**
- `docs/sync-architecture.md` (HIGH priority - add diagrams)
- `docs/setup-guide.md` (HIGH priority - add diagrams)
- `docs/configuration.md` (HIGH priority - add diagrams)
- `docs/adding-agents.md` (MEDIUM priority - add diagrams)
- `docs/acp.md` (MEDIUM priority - convert ASCII art)
- `docs/testing.md` (MEDIUM priority - add diagrams)
- **RETROFIT**: `docs/architecture.md` (existing diagrams need `accTitle`/`accDescr`)
- **RETROFIT**: `docs/lifecycle.md` (existing diagrams need `accTitle`/`accDescr`)
- **RETROFIT**: `docs/quickstart.md` (existing diagrams need `accTitle`/`accDescr`)
- **RETROFIT**: `docs/security-comparison.md` (existing diagrams need `accTitle`/`accDescr`)
- **RETROFIT**: `docs/security-scenarios.md` (existing diagrams need `accTitle`/`accDescr`)

## Approach

### PHASE 1: Retrofit Existing Diagrams (REQUIRED FIRST)

Before adding new diagrams, add `accTitle` and `accDescr` to ALL existing Mermaid diagrams in:

1. **docs/architecture.md** - Multiple diagrams to retrofit
2. **docs/lifecycle.md** - State diagram at lines 9-30
3. **docs/quickstart.md** - Any existing diagrams
4. **docs/security-comparison.md** - Existing comparison diagrams
5. **docs/security-scenarios.md** - Existing scenario diagrams

Example retrofit pattern:
```mermaid
%%{init: {...}}%%
accTitle: Brief title for screen readers
accDescr: Longer description explaining what the diagram shows
flowchart ...
```

### PHASE 2: Add New Diagrams to Files Lacking Them

#### HIGH PRIORITY Files

1. **sync-architecture.md** (currently 0 diagrams):
   - Add **data flow diagram** showing: Host configs → rsync → Volume → Container symlinks
   - Show the 3-component sync system: import.sh → Dockerfile.agents → containai-init.sh
   - Visualize sync map relationships (source → target → container_link)

2. **setup-guide.md** (currently 0 diagrams):
   - Add **installation decision tree** for platform selection (WSL2 vs Linux vs macOS/Lima)
   - Show component stack: What gets installed and in what order

3. **configuration.md** (currently 0 diagrams):
   - Add **precedence hierarchy flowchart**: CLI flags > env vars > workspace config > global config > defaults
   - Add **config discovery flowchart**: How config file is located (walk up tree, stop at git root)

#### MEDIUM PRIORITY Files

4. **adding-agents.md** (currently 0 diagrams):
   - Add **6-step workflow diagram** showing agent addition process
   - Visualize path mapping: source → target → container_link conventions

5. **acp.md** (currently has ASCII art at line 33):
   - **Convert ASCII diagram** to Mermaid sequence diagram
   - Current ASCII: `Editor → ACP stdio → Proxy → cai exec → Container → Agent`

6. **testing.md** (currently 0 diagrams):
   - Add **test tier diagram** showing Tier 1 (lint) → Tier 2 (integration) → Tier 3 (E2E)

## Key context

**Accessibility requirement**: ALL diagrams MUST include:
```
accTitle: <brief title>
accDescr: <description of what diagram shows>
```

**Test diagrams** at https://mermaid.live/ before committing to ensure GitHub renders correctly.

**Existing examples to follow** (but retrofit these with accTitle/accDescr too):
- `docs/architecture.md:49-83` (Flowchart with subgraphs)
- `docs/architecture.md:168-229` (Sequence diagram)
- `docs/lifecycle.md:9-30` (State diagram)

## Acceptance

### PHASE 1: Retrofit Existing (MUST complete)
- [ ] docs/architecture.md ALL diagrams have `accTitle`/`accDescr`
- [ ] docs/lifecycle.md state diagram has `accTitle`/`accDescr`
- [ ] docs/quickstart.md any diagrams have `accTitle`/`accDescr`
- [ ] **docs/security-comparison.md ALL diagrams have `accTitle`/`accDescr`**
- [ ] **docs/security-scenarios.md ALL diagrams have `accTitle`/`accDescr`**
- [ ] Verify retrofitted diagrams still render on GitHub

### PHASE 2 HIGH PRIORITY (MUST complete)
- [ ] sync-architecture.md has data flow diagram (with `accTitle`/`accDescr`)
- [ ] sync-architecture.md has 3-component sync system diagram
- [ ] setup-guide.md has platform decision tree
- [ ] setup-guide.md has component installation stack diagram
- [ ] configuration.md has precedence hierarchy flowchart
- [ ] configuration.md has config discovery flowchart

### PHASE 2 MEDIUM PRIORITY (SHOULD complete)
- [ ] adding-agents.md has 6-step workflow diagram
- [ ] acp.md ASCII art converted to Mermaid sequence diagram
- [ ] testing.md has test tier hierarchy diagram

### Quality Requirements
- [ ] ALL diagrams (new AND retrofitted) include `accTitle`/`accDescr`
- [ ] All diagrams render correctly on GitHub (test before merge)
- [ ] Diagrams are placed immediately after relevant section headings
- [ ] No diagram exceeds 30 nodes (split if larger)

## Done summary
Added accessibility attributes (accTitle/accDescr) to all existing Mermaid diagrams and added new diagrams to documentation files that lacked visual aids.

Phase 1 - Retrofitted existing diagrams with accessibility:
- docs/architecture.md: 11 diagrams
- docs/lifecycle.md: 1 diagram
- docs/quickstart.md: 2 diagrams
- docs/security-comparison.md: 8 diagrams
- docs/security-scenarios.md: 6 diagrams

Phase 2 - Added new diagrams:
- docs/sync-architecture.md: 2 diagrams (data flow, 3-component system)
- docs/setup-guide.md: 2 diagrams (platform selection, component stack)
- docs/configuration.md: 2 diagrams (precedence hierarchy, config discovery)
- docs/adding-agents.md: 1 diagram (6-step workflow)
- docs/acp.md: 1 sequence diagram (converted ASCII art)
- docs/testing.md: 1 diagram (test tier hierarchy)
## Evidence
- Commits:
- Tests:
- PRs:
