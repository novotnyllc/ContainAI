# CLI UX Audit and Simplification Recommendations

## Overview

Conduct a UX researcher-style audit of ContainAI's CLI to identify inconsistencies, usability issues, and opportunities for simplification. This epic produces **analysis and recommendations**, not implementation code.

### Core Problem
The CLI has grown organically to 24 commands with varying flag patterns, help text depth, and error message quality. No systematic UX review has been performed to ensure the CLI is cohesive, intuitive, and follows modern CLI conventions.

### Goals
1. **Heuristic evaluation** against CLI UX best practices (clig.dev, GNU, POSIX)
2. **Consistency audit** of flag naming, help text, and error messages
3. **Simplification opportunities** - reduce cognitive load for users
4. **Prioritized recommendations** for future implementation

### Non-Goals
- **Not implementing fixes** - fn-36-rb7 and fn-42 handle implementation
- **Not changing the `-v`/`--verbose` decision** - this is documented and intentional
- **Not breaking backward compatibility** without explicit approval

## Scope

### In Scope
- Audit all 24 CLI commands against UX heuristics
- Document flag naming inconsistencies
- Review error messages for actionability
- Assess help text completeness and consistency
- Identify command structure simplification opportunities
- Produce prioritized recommendations document

### Out of Scope
- Code changes (defer to fn-36-rb7, fn-42, or new epics)
- Documentation updates (fn-45 handles docs)
- Shell completion improvements (fn-36-rb7 handles this)

## Quick commands

```bash
# View all commands
source src/containai.sh && cai help

# Test help text for each command
for cmd in run shell exec doctor setup validate import export stop status gc ssh links config template completion version update; do
  echo "=== cai $cmd --help ==="
  cai $cmd --help 2>&1 | head -20
done

# Check flag consistency
grep -n '\-\-container\|--name' src/containai.sh | head -20
```

## Acceptance Criteria

- [ ] UX heuristic evaluation completed for all 24 commands
- [ ] Flag consistency matrix documenting all flags across commands
- [ ] Error message audit with actionability scores
- [ ] Help text completeness checklist
- [ ] Simplification opportunities identified and prioritized
- [ ] Recommendations document produced in `.flow/specs/` or `docs/`
- [ ] Each recommendation tagged: quick-win, medium-effort, breaking-change

## Dependencies

### Coordinates With
- **fn-36-rb7** (CLI UX Consistency): Implementation epic for CLI fixes
- **fn-42** (CLI UX Fixes): Short container names, hostname fixes
- **fn-45** (Documentation): CLI reference documentation

### Blocked By
- None (audit can proceed independently)

## References

- CLI guidelines: https://clig.dev/
- GNU coding standards: https://www.gnu.org/prep/standards/
- Project conventions: `.flow/memory/conventions.md` (verbosity pattern)
- Project pitfalls: `.flow/memory/pitfalls.md` (flag validation gotchas)
- Current CLI: `src/containai.sh` (6700+ lines, 24 commands)

## Open Questions

1. What is the target audience - Docker experts, AI developers unfamiliar with containers, or both?
2. Is there appetite for breaking changes if they significantly improve UX?
3. Should recommendations be prioritized by user impact or implementation effort?

## Known Issues to Audit

From research:
- `--name` in `cai links` vs `--container` elsewhere
- Positional workspace AND `--workspace` flag (two ways to do same thing)
- `--volume/-v` rejected with insufficient explanation
- JSON output (`--json`) not available on all commands
- Error messages vary in actionability
- Help text depth inconsistent across commands
