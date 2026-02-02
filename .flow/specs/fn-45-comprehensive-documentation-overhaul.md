# Comprehensive Documentation Overhaul

## Overview

Restructure and enhance ContainAI documentation to serve three distinct personas (users, contributors, security auditors) with clear value proposition and differentiated positioning. Current documentation is technically thorough but scattered; this epic consolidates it into a persona-driven, Diataxis-aligned structure.

### Core Problem
Users don't quickly understand **why ContainAI vs alternatives** (Docker sandbox, SRT). The value prop—VM-like isolation with container convenience, preferences sync, "feels like home"—is buried across 13+ docs files.

### Goals
1. **Clear value proposition** in first 30 seconds of README
2. **Persona-based entry points** for quick orientation
3. **Unified CLI reference** (currently scattered)
4. **Document recent changes** (silent CLI, network security)
5. **Ephemeral vs long-lived patterns** explicitly documented

## Scope

### In Scope
- README overhaul with differentiated value prop
- Persona landing pages (user, contributor, security auditor)
- CLI reference documentation (all commands, flags, env vars)
- Usage patterns guide (ephemeral vs persistent)
- Config examples cookbook
- Update docs for fn-41 (silent CLI), fn-43 (network security)
- Sync architecture visualization

### Out of Scope
- **Documentation website** (no MkDocs, Docusaurus, GitHub Pages, or hosted docs site)
- Video content
- Internationalization
- fn-44 changes (defer until that epic completes)

**Note:** All documentation remains as markdown files in the repo (`docs/`, `README.md`). A hosted docs website is a separate future epic if ever needed.

## Quick commands

```bash
# Verify docs build/lint
shellcheck -x src/*.sh  # Check code examples work
markdownlint docs/**/*.md  # If linter available

# Preview changes
cat README.md | head -50  # Check value prop section

# Validate internal links
grep -r '\[.*\](docs/' README.md docs/
```

## Acceptance Criteria

- [ ] README first 10 lines answer "why ContainAI vs alternatives"
- [ ] Three persona landing pages exist with clear entry points
- [ ] CLI reference covers all `cai` subcommands with flags and examples
- [ ] Usage patterns guide explains ephemeral vs persistent workflows
- [ ] Config examples directory with 5+ real-world configurations
- [ ] Silent CLI behavior (--verbose) documented in quickstart and CLI ref
- [ ] Network security (private IP blocking) documented in SECURITY.md
- [ ] Sync architecture has visual diagram (mermaid)
- [ ] All internal doc links validated (no broken links)
- [ ] No duplicate content across docs (single source of truth)

## Dependencies

### Blocked By
- **fn-46** (CLI UX Audit): CLI reference should incorporate audit findings

### Informs
- Future docs website epic (if ever needed) will build on this structure

## References

- Diataxis framework: https://diataxis.fr/
- Best-README-Template: https://github.com/othneildrew/Best-README-Template
- Existing docs: `docs/`, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`
- Memory conventions: `.flow/memory/conventions.md` (doc accuracy requirements)
- Memory pitfalls: `.flow/memory/pitfalls.md` (doc drift warnings)

## Open Questions

1. Should "Why ContainAI" be a new page or evolved from `security-comparison.md`?
2. Primary persona ordering for landing pages?
3. Should CLI reference be auto-generated from --help or manually maintained?
