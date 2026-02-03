# Comprehensive Documentation Overhaul

## Overview

Restructure and enhance ContainAI documentation to serve three distinct personas (users, contributors, security auditors) with clear value proposition and differentiated positioning. Current documentation is technically thorough but scattered; this epic consolidates it into a persona-driven, Diataxis-aligned structure.

**Visual Documentation Standard**: All documentation must use Mermaid diagrams wherever flows, states, relationships, or decision trees would aid comprehension.

### Core Problem
Users don't quickly understand **why ContainAI vs alternatives** (Docker sandbox, SRT). The value prop—VM-like isolation with container convenience, preferences sync, "feels like home"—is buried across 13+ docs files.

### Goals
1. **Clear value proposition** in first 30 seconds of README
2. **Persona-based entry points** for quick orientation
3. **Unified CLI reference** (currently scattered)
4. **Document recent changes** (silent CLI, network security)
5. **Ephemeral vs long-lived patterns** explicitly documented
6. **Visual diagrams** wherever flows, states, or relationships exist

## Scope

### In Scope
- README overhaul with differentiated value prop
- Persona landing pages (user, contributor, security auditor)
- CLI reference documentation (all commands, flags, env vars)
- Usage patterns guide (ephemeral vs persistent)
- Config examples cookbook
- Update docs for fn-41 (silent CLI), fn-43 (network security)
- Sync architecture visualization
- **Add Mermaid diagrams to existing docs** (sync-architecture, setup-guide, configuration, adding-agents, acp, testing)
- **Retrofit existing diagrams** with `accTitle`/`accDescr` for accessibility compliance
- **Add link validation script** for CI/pre-commit checks

### Out of Scope
- **Documentation website** (no MkDocs, Docusaurus, GitHub Pages, or hosted docs site)
- Video content
- Internationalization
- fn-44 changes (defer until that epic completes)

**Note:** All documentation remains as markdown files in the repo (`docs/`, `README.md`). A hosted docs website is a separate future epic if ever needed.

## Mermaid Diagram Guidelines

- Use `flowchart LR/TB/TD` for architecture, data flows, decision trees
- Use `sequenceDiagram` for multi-component interactions over time
- Use `stateDiagram-v2` for state machines (container lifecycle)
- Keep diagrams under 30 nodes for readability
- Use subgraphs to group related elements
- **REQUIRED**: Include `accTitle` and `accDescr` in EVERY diagram for accessibility
- Test diagrams render correctly on GitHub before merging
- **No mandatory theme** - use whatever renders well on GitHub (dark/light compatible)

**Existing examples to follow:**
- `docs/architecture.md:49-83` (Flowchart with subgraphs)
- `docs/architecture.md:168-229` (Sequence diagram)
- `docs/lifecycle.md:9-30` (State diagram)

## Quick commands

```bash
# Verify docs build/lint
shellcheck -x src/*.sh  # Check code examples work

# Preview changes
cat README.md | head -50  # Check value prop section

# Validate internal links (use scripts/check-doc-links.sh after task creates it)
scripts/check-doc-links.sh

# Test Mermaid syntax (use Mermaid Live Editor)
# https://mermaid.live/
```

## Acceptance Criteria

- [ ] README first paragraph (after badges/title) answers "why ContainAI vs alternatives"
- [ ] Three persona landing pages exist with clear entry points
- [ ] CLI reference covers ALL `cai` subcommands including: run, shell, exec, doctor, setup, validate, docker, import, export, sync, stop, status, gc, ssh, links, config, completion, version, update, refresh, uninstall, help, acp, template, **sandbox (deprecated)**
- [ ] CLI reference documents subcommands: `doctor fix`, `ssh cleanup`, `config list/get/set/unset`, `links check/fix`, `gc`, `template upgrade`, `acp proxy`
- [ ] Usage patterns guide documents THREE modes: (1) disposable container with persistent volume, (2) fully ephemeral including volume deletion, (3) long-lived persistent environment
- [ ] Config examples directory with 5+ real-world configurations
- [ ] Silent CLI behavior (--verbose) documented in quickstart and CLI ref
- [ ] Network security (private IP blocking) documented in SECURITY.md
- [ ] SECURITY.md isolation claims corrected to match implementation (Sysbox + containai-docker, not ECI)
- [ ] Sync architecture has visual diagram (mermaid)
- [ ] All internal doc links validated via `scripts/check-doc-links.sh`
- [ ] No duplicate content across docs (single source of truth)
- [ ] **All NEW diagrams include `accTitle`/`accDescr` for accessibility**
- [ ] **All EXISTING diagrams retrofitted with `accTitle`/`accDescr`** (architecture.md, lifecycle.md, quickstart.md, security-comparison.md, security-scenarios.md)
- [ ] **Diagrams render correctly on GitHub**

## Dependencies

### Runs After
- **fn-46** (CLI UX Audit): CLI reference should incorporate audit findings
- **fn-47** (Extensibility): Documentation should cover new extensibility features (hooks, network policies)

**Execution order:** fn-46 → fn-47 → fn-45

### Informs
- Future docs website epic (if ever needed) will build on this structure

## References

- Diataxis framework: https://diataxis.fr/
- Best-README-Template: https://github.com/othneildrew/Best-README-Template
- Existing docs: `docs/`, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`
- Memory conventions: `.flow/memory/conventions.md` (doc accuracy requirements)
- Memory pitfalls: `.flow/memory/pitfalls.md` (doc drift warnings)
- Mermaid accessibility: https://mermaid.js.org/config/accessibility.html
- GitHub Mermaid support: https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams

## Open Questions

~~1. Should "Why ContainAI" be a new page or evolved from `security-comparison.md`?~~ **Resolved**: Keep security-comparison.md as technical comparison; README provides value prop.

~~2. Primary persona ordering for landing pages?~~ **Resolved**: User > Contributor > Security Auditor (by audience size).

~~3. Should CLI reference be auto-generated from --help or manually maintained?~~ **Resolved**: Manually maintained with a maintenance policy documented in the CLI reference file itself. Single-source-of-truth is `--help` output; docs provide extended examples/explanations.
