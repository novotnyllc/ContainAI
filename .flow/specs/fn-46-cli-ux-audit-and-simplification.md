# CLI UX Audit and Simplification Recommendations

## Overview

Conduct a UX researcher-style audit of ContainAI's CLI to identify inconsistencies, usability issues, and opportunities for simplification. This epic produces **analysis and recommendations**, not implementation code.

### Core Problem
The CLI has grown organically with varying flag patterns, help text depth, and error message quality. No systematic UX review has been performed to ensure the CLI is cohesive, intuitive, and follows modern CLI conventions.

### Goals
1. **Command inventory** - derive authoritative list programmatically from dispatch code
2. **Heuristic evaluation** against CLI UX best practices (clig.dev, GNU, POSIX)
3. **Consistency audit** of flag naming, help text, and error messages
4. **Simplification opportunities** - reduce cognitive load for users
5. **Prioritized recommendations** for future implementation

### Non-Goals
- **Not implementing fixes** - fn-36-rb7 and fn-42 handle implementation
- **Not changing the `-v`/`--verbose` decision** - this is documented and intentional
- **Not breaking backward compatibility** without explicit approval

## Design Decisions (Resolving Open Questions)

### Target Audience
**Primary**: AI developers unfamiliar with containers who need quick setup
**Secondary**: Docker experts who want control and predictability
**Implication**: Prioritize "happy path" simplicity over advanced options

### Breaking Change Appetite
**Policy**: Breaking changes require deprecation warnings for 1 minor version minimum.
**Implication**: Recommendations tagged "breaking" must include migration path.

### Prioritization Scheme
**Axis**: User impact first, then effort
**Scoring**: Impact (1-5) × Frequency (1-5) = Priority score
**Tie-breaker**: Lower effort wins

### Personas (for heuristic evaluation)

**Persona A: "Alex the AI Dev"**
- Wants to run Claude Code in a container for the first time
- Docker experience: novice (knows `docker run`, not much else)
- Goals: Get working in < 5 minutes, sync workspace, stop wasting time on setup
- Journeys: first-run, attach-shell, import-config

**Persona B: "Dana the DevOps Engineer"**
- Setting up ContainAI for a team or CI environment
- Docker experience: expert (manages registries, custom networks)
- Goals: Understand all options, configure precisely, automate updates
- Journeys: setup-customization, troubleshoot-doctor, update-cycle, uninstall-reinstall

### Core User Journeys (for evaluation context)
1. **First run**: `cai setup` → `cai run` → working shell
2. **Attach shell**: `cai shell` or `cai exec bash` to existing container
3. **Import secrets**: `cai import` to bring SSH keys/credentials safely
4. **Troubleshoot**: `cai doctor` → `cai doctor fix` to resolve issues
5. **Update cycle**: `cai update` → `cai refresh` → verify

## Command Inventory Derivation

**PROGRAMMATIC APPROACH** - robust extraction from `containai()` dispatch:

```bash
# Step 1: Extract ALL tokens from case arms (including --flags)
# Uses POSIX [[:space:]] for cross-platform compatibility (not \s)
awk '/^containai\(\)/,/^}/' src/containai.sh | \
  grep -E '^[[:space:]]+[a-z-]+.*\)' | \
  sed 's/).*//; s/[[:space:]]//g' | \
  tr '|' '\n' | \
  sort -u

# Step 2: Filter to command names (strip -- prefix, filter short flags)
# This produces: completion, config, docker, doctor, exec, export, gc,
#                help, import, links, refresh, run, setup, shell, ssh, status,
#                stop, sync, template, uninstall, update, validate, version, sandbox
# Note: acp is a pre-case if-route, not in case arms
awk '/^containai\(\)/,/^}/' src/containai.sh | \
  grep -E '^[[:space:]]+[a-z-]+.*\)' | \
  sed 's/).*//; s/[[:space:]]//g' | \
  tr '|' '\n' | \
  sed 's/^--//' | \
  grep -E '^[a-z]+$' | \
  sort -u

# Step 3: Identify pre-case if-routes (both with and without -- prefix)
awk '/^containai\(\)/,/^}/' src/containai.sh | \
  grep -E '== "[a-z-]+"' | \
  sed 's/.*== "\([a-z-]*\)".*/\1/' | \
  sort -u
```

**Flag-based case arms** (mapped to commands):
- `--refresh` → refresh command (case arm, not pre-case if)

**Pre-case if-routes** (before case statement):
- `acp` → acp command (pre-case if-route, matches `== "acp"`)
- `--acp` → acp proxy (pre-case if-route, matches `== "--acp"`)

**Deprecated subcommands** (include in audit, mark deprecated):
- `sandbox` → deprecated, shows warning

**Note on unknown commands**: Unknown tokens route to `run`, not an "unknown command" error. This is a UX finding to document.

## Scope

### In Scope
- Command inventory derivation from dispatch code (programmatic, handles multi-pattern arms and --flag routes)
- Audit all discovered commands against UX heuristics
- Document flag naming inconsistencies across `src/containai.sh` AND `src/lib/*.sh`
- Review error messages for actionability (including printf, _cai_error, dynamic)
- Assess help text completeness via structured checklist
- Identify command structure simplification opportunities
- Produce prioritized recommendations document in `.flow/specs/`

### Out of Scope
- Code changes (defer to fn-36-rb7, fn-42, or new epics)
- User-facing documentation updates (fn-45 handles docs)
- Shell completion improvements (fn-36-rb7 handles this)

**Clarification**: Output is an **internal planning document** in `.flow/specs/`, not user-facing docs.

## Quick commands

```bash
# Derive command inventory PROGRAMMATICALLY (POSIX-portable, uses [[:space:]] not \s)
awk '/^containai\(\)/,/^}/' src/containai.sh | grep -E '^[[:space:]]+[a-z-]+.*\)' | sed 's/).*//; s/[[:space:]]//g' | tr '|' '\n' | sed 's/^--//' | grep -E '^[a-z]+$' | sort -u

# Test help text for ALL discovered commands (derive from inventory)
source src/containai.sh
for cmd in $(awk '/^containai\(\)/,/^}/' src/containai.sh | grep -E '^[[:space:]]+[a-z-]+.*\)' | sed 's/).*//; s/[[:space:]]//g' | tr '|' '\n' | sed 's/^--//' | grep -E '^[a-z]+$' | sort -u); do
  echo "=== cai $cmd --help ==="
  cai $cmd --help 2>&1 | head -25
done

# Check flag consistency across ALL sources (use grep -E for portability)
grep -rn -E -- '--container|--name' src/containai.sh src/lib/*.sh | head -30

# Find all error patterns (comprehensive)
grep -rn -E '_cai_error|printf.*>&2|\[ERROR\]' src/*.sh src/lib/*.sh | wc -l
```

## Acceptance Criteria

- [ ] Command inventory derived programmatically (handles multi-pattern case arms AND --flag routes)
- [ ] Pre-case if-routes identified where applicable
- [ ] UX heuristic evaluation completed for all discovered commands with scoring rubrics
- [ ] Flag consistency matrix from `src/containai.sh` AND `src/lib/*.sh`
- [ ] Error message audit with actionability scores and dedupe strategy
- [ ] Help text completeness checklist (see deliverable spec below)
- [ ] Simplification opportunities identified and prioritized
- [ ] Recommendations document produced in `.flow/specs/cli-ux-recommendations.md`
- [ ] Each recommendation tagged: quick-win, medium-effort, breaking-change
- [ ] Each recommendation has "Owner epic" field: fn-36-rb7 / fn-42 / fn-45 / new

## Help Text Completeness Checklist (Deliverable)

For each command, check:
- [ ] Synopsis (usage line)
- [ ] Brief description (1-2 sentences)
- [ ] Options section with all flags
- [ ] Option grouping (global vs command-specific)
- [ ] At least 2 examples
- [ ] Exit codes documented (if non-trivial)
- [ ] Environment variables mentioned (if any)
- [ ] Stdout/stderr behavior noted (if relevant)
- [ ] Related commands cross-linked
- [ ] Deprecation notes (if applicable)

## Scoring Rubrics

### Heuristic Scores (1-5)

| Score | Discoverability | Learnability | Efficiency | Error Prevention |
|-------|-----------------|--------------|------------|------------------|
| 1 | Can't find from help | Help text confusing | Many steps for simple task | Easy to make mistakes |
| 2 | Buried in help | Help text incomplete | Unnecessary flags required | Some footguns |
| 3 | Findable with effort | Help text adequate | Reasonable workflow | Warns on common errors |
| 4 | Easily findable | Help text good | Streamlined workflow | Prevents common errors |
| 5 | Obvious/intuitive | Help text excellent | Minimal user effort | Fail-safe design |

### Error Message Scores (1-5)

| Score | Description | Example |
|-------|-------------|---------|
| 1 | Cryptic/unhelpful | "Error" |
| 2 | Explains problem, no solution | "Container not found" |
| 3 | Explains problem, vague solution | "Container not found. Check name." |
| 4 | Clear problem and solution | "Container 'foo' not found. Run 'cai run' to create it." |
| 5 | Clear problem, solution, and prevention | "Container 'foo' not found. Run 'cai run' to create, or 'cai status' to list existing." |

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
- Main CLI: `src/containai.sh`
- Library modules: `src/lib/*.sh` (setup, validate, update, container, etc.)
