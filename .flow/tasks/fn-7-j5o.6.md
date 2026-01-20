# fn-7-j5o.6 Create CONTRIBUTING.md

## Description
Create CONTRIBUTING.md to enable community contributions with clear development setup, coding conventions, and PR process.

**Size:** S
**Files:** `CONTRIBUTING.md`

## Approach

- Include development environment setup (bash requirement, Docker)
- Reference coding conventions from `.flow/memory/conventions.md`
- Document testing process (test-*.sh scripts)
- Explain PR review process
- Link to architecture docs for understanding codebase

## Key Context

- Tests in `agent-sandbox/test-*.sh` with `[PASS]/[FAIL]/[WARN]` markers
- Coding conventions: `command -v` not `which`, `printf` not `echo`, ASCII markers
- Shell scripts must be bash (not zsh compatible)
- All loop variables must be declared local in sourced scripts
## Acceptance
- [ ] CONTRIBUTING.md exists at project root
- [ ] Documents development environment setup
- [ ] Documents coding conventions (shell scripting rules)
- [ ] Documents testing process with test-*.sh scripts
- [ ] Explains PR process and review expectations
- [ ] Links to architecture overview for codebase understanding
- [ ] Includes "good first issue" guidance for newcomers
- [ ] References .flow/memory/conventions.md for detailed rules
## Done summary
Created comprehensive CONTRIBUTING.md with development setup, shell scripting conventions, testing process, PR workflow, and good first issue guidance.
## Evidence
- Commits: dc2e2e3, 5e05bc8
- Tests: Manual verification of markdown rendering
- PRs: