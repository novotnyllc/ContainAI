# fn-46-cli-ux-audit-and-simplification.1 Heuristic evaluation of all CLI commands

## Description
Conduct a heuristic evaluation of all CLI commands against established CLI UX best practices. Derive command inventory programmatically from dispatch code (handling multi-pattern case arms, --flag case arms, and pre-case if-routes), then evaluate each for discoverability, learnability, efficiency, and error prevention using defined scoring rubrics and personas.

**Size:** M
**Files:** Analysis output only (no code changes)

## Approach

### Step 1: Derive Command Inventory Programmatically

**Extract case arms (handles multi-pattern arms AND --flag routes like `--refresh)`):**
```bash
# Parse the main dispatch case statement, split on |, strip -- prefix, filter to command names
# Uses POSIX [[:space:]] instead of \s for cross-platform compatibility
awk '/^containai\(\)/,/^}/' src/containai.sh | \
  grep -E '^[[:space:]]+[a-z-]+.*\)' | \
  sed 's/).*//; s/[[:space:]]//g' | \
  tr '|' '\n' | \
  sed 's/^--//' | \
  grep -E '^[a-z]+$' | \
  sort -u
```

**Extract pre-case if-routes (e.g., `acp` and `--acp` handled before case):**
```bash
# Find if statements that check subcommand before the main case
# Matches both "acp" and "--acp" patterns
awk '/^containai\(\)/,/^}/' src/containai.sh | \
  grep -E '== "[a-z-]+"' | \
  sed 's/.*== "\([a-z-]*\)".*/\1/' | \
  sort -u
```

**Route types:**
- **Case-arm flag routes**: `--refresh` (handled in case statement, maps to `refresh`)
- **Pre-case if-routes**: `acp`, `--acp` (handled before case statement)

**Combine and validate:**
- Merge case arms (including flag routes) + pre-case if-routes
- Compare against `cai help` output
- Document discrepancies (commands in dispatch but not in help, or vice versa)

### Step 2: Define Evaluation Framework
Apply heuristics from:
- clig.dev guidelines (human-first, discoverability, composability)
- GNU coding standards (--help, --version, flag conventions)
- POSIX utility conventions (short flags, -- terminator)

### Step 3: Evaluate Against Personas

**Persona A: "Alex the AI Dev"** (novice Docker user)
- Test journeys: first-run, attach-shell, import-config
- Focus: Is the happy path obvious?

**Persona B: "Dana the DevOps Engineer"** (expert Docker user)
- Test journeys: setup-customization, troubleshoot-doctor, update-cycle
- Focus: Are advanced options discoverable without clutter?

### Step 4: Score Each Command (using rubrics)

| Score | Discoverability | Learnability | Efficiency | Error Prevention |
|-------|-----------------|--------------|------------|------------------|
| 1 | Can't find from help | Help text confusing | Many steps for simple task | Easy to make mistakes |
| 2 | Buried in help | Help text incomplete | Unnecessary flags required | Some footguns |
| 3 | Findable with effort | Help text adequate | Reasonable workflow | Warns on common errors |
| 4 | Easily findable | Help text good | Streamlined workflow | Prevents common errors |
| 5 | Obvious/intuitive | Help text excellent | Minimal user effort | Fail-safe design |

### Step 5: Produce Help Text Completeness Checklist

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

## Key context

Reference files:
- Main CLI dispatch: `src/containai.sh` (search for `containai()` function)
- Help functions: `src/containai.sh` (search for `_cai_*_help` functions)
- Library commands: `src/lib/*.sh` (setup, validate, update, container, etc.)
- Conventions: `.flow/memory/conventions.md` (verbosity pattern)

Known issues to look for:
- Inconsistent help text depth
- Missing examples in help
- Unclear command purposes
- Commands not listed in `cai help` but available (e.g., `template`)

## Acceptance
- [x] Command inventory derived programmatically (handles multi-pattern case arms AND --flag case arms)
- [x] Case-arm flag routes identified (e.g., `--refresh` maps to `refresh`)
- [x] Pre-case if-routes identified (e.g., `--acp`)
- [x] Discrepancies between dispatch and `cai help` documented
- [x] Evaluation heuristics defined with scoring anchors
- [x] All discovered commands evaluated against heuristics with both personas
- [x] Scores and notes captured in structured format (table)
- [x] Help text completeness checklist for each command (deliverable)
- [x] Top 5 usability issues identified per persona
- [x] Quick wins (easy fixes) flagged

## Done summary
Completed comprehensive heuristic evaluation of all 24 CLI commands. Key findings:
- Derived 24 commands from dispatch code (including deprecated `sandbox`)
- Identified 2 pre-case if-routes (`acp`, `--acp` legacy)
- Found critical discoverability issue: `template` command not in main help
- `acp` subcommand buried after "Run Options" section, not with other subcommands
- `docker` command lacks dedicated help function
- Exit codes documented for only 4/24 commands (shell, exec, links, doctor)
- Average scores: shell/version highest (5.0), acp/template lowest (3.0-3.25)
- Produced help text completeness checklist showing gaps in env vars, exit codes, related commands
- Identified 5 quick wins: add template to help, move acp, add docker help, document exit codes, note --acp deprecation
## Evidence
- Commits:
- Tests:
- PRs:
