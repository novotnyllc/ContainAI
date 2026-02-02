# fn-46-cli-ux-audit-and-simplification.1 Heuristic evaluation of all CLI commands

## Description
Conduct a heuristic evaluation of all 24 CLI commands against established CLI UX best practices. Evaluate each command for discoverability, learnability, efficiency, and error prevention.

**Size:** M
**Files:** Analysis output only (no code changes)

## Approach

1. Define evaluation heuristics based on:
   - clig.dev guidelines (human-first, discoverability, composability)
   - GNU coding standards (--help, --version, flag conventions)
   - POSIX utility conventions (short flags, -- terminator)

2. For each command, evaluate:
   - **Discoverability**: Can users find this command when they need it?
   - **Learnability**: Is the command easy to understand from help text?
   - **Efficiency**: Does the command minimize user effort?
   - **Error prevention**: Does the command prevent common mistakes?
   - **Help quality**: Is --help comprehensive and well-structured?

3. Commands to evaluate (24 total):
   ```
   run, shell, exec, doctor, setup, validate, docker, sandbox (deprecated),
   import, export, sync, stop, status, gc, ssh, links, config, template,
   completion, version, update, refresh, uninstall, help
   ```

4. Output format: Table with command, heuristic scores (1-5), and notes

## Key context

Reference files:
- Main CLI: `src/containai.sh:6833-6942` (dispatch)
- Help functions: `src/containai.sh:193-947`
- Conventions: `.flow/memory/conventions.md` (verbosity pattern)

Known issues to look for:
- Inconsistent help text depth
- Missing examples in help
- Unclear command purposes
## Acceptance
- [ ] Evaluation heuristics defined and documented
- [ ] All 24 commands evaluated against heuristics
- [ ] Scores and notes captured in structured format
- [ ] Top 5 usability issues identified
- [ ] Quick wins (easy fixes) flagged
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
