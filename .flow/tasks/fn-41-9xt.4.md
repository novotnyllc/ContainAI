# fn-41-9xt.4 Update documentation and help text

## Description
Update documentation to reflect the new silent-by-default behavior and `--verbose` flag.

**Size:** S
**Files:** `README.md`, `AGENTS.md`, `docs/setup-guide.md`, `.flow/memory/conventions.md`

## Approach

1. Update README.md common commands section to mention `--verbose`
2. Update AGENTS.md Code Conventions to document verbose pattern
3. Update docs/setup-guide.md to explain `--verbose` behavior
4. Add convention to .flow/memory/conventions.md
5. Prepare CHANGELOG.md entry (under Unreleased)

## Key context

The setup-guide.md already has examples with `--verbose` (lines 222, 323, 380). These should have explanation text added.

Document these key points:
- Silent by default (Unix Rule of Silence)
- Use `--verbose` to see status messages (long form only, no `-v`)
- Use `CONTAINAI_VERBOSE=1` environment variable for persistent verbosity
- Warnings and errors always emit to stderr
- Precedence: `--quiet` > `--verbose` > `CONTAINAI_VERBOSE`

## Acceptance
- [ ] README.md mentions `--verbose` flag
- [ ] AGENTS.md Code Conventions documents verbose pattern
- [ ] docs/setup-guide.md explains `--verbose` behavior
- [ ] .flow/memory/conventions.md has verbose pattern entry
- [ ] CHANGELOG.md has entry under Unreleased documenting the breaking change
- [ ] Note that `-v` is NOT a verbose shorthand (due to version/volume conflicts)
## Done summary
# fn-41-9xt.4 Summary: Update documentation and help text

## Changes Made

### README.md
- Added note below Common Commands section explaining silent-by-default behavior
- Documented `--verbose` flag and `CONTAINAI_VERBOSE=1` environment variable

### AGENTS.md
- Added verbose pattern to Code Conventions section
- Documented `_cai_info()` usage, `--verbose` flag (no `-v`), and precedence rules

### docs/setup-guide.md
- Added "CLI Output Behavior" section to Table of Contents and document
- Updated setup command examples with explanatory comments about silent default
- Documented verbose output enablement, precedence rules, and `-v` flag note

### .flow/memory/conventions.md
- Added new convention entry dated 2026-01-30 documenting the verbose pattern

### CHANGELOG.md
- Added **BREAKING** change entry under Unreleased section
- Documented: silent default, `--verbose`/`CONTAINAI_VERBOSE`, precedence, `-v` note, exempt commands

## Acceptance Criteria Status
- [x] README.md mentions `--verbose` flag
- [x] AGENTS.md Code Conventions documents verbose pattern
- [x] docs/setup-guide.md explains `--verbose` behavior
- [x] .flow/memory/conventions.md has verbose pattern entry
- [x] CHANGELOG.md has entry under Unreleased documenting the breaking change
- [x] Note that `-v` is NOT a verbose shorthand (documented in all relevant places)
## Changes Made

### README.md
- Added note below Common Commands section explaining silent-by-default behavior
- Documented `--verbose` flag and `CONTAINAI_VERBOSE=1` environment variable

### AGENTS.md
- Added verbose pattern to Code Conventions section
- Documented `_cai_info()` usage, `--verbose` flag (no `-v`), and precedence rules

### docs/setup-guide.md
- Added "CLI Output Behavior" section to Table of Contents and document
- Updated setup command examples with explanatory comments about silent default
- Documented verbose output enablement, precedence rules, and `-v` flag note

### .flow/memory/conventions.md
- Added new convention entry dated 2026-01-30 documenting the verbose pattern

### CHANGELOG.md
- Added **BREAKING** change entry under Unreleased section
- Documented: silent default, `--verbose`/`CONTAINAI_VERBOSE`, precedence, `-v` note, exempt commands

## Acceptance Criteria Status
- [x] README.md mentions `--verbose` flag
- [x] AGENTS.md Code Conventions documents verbose pattern
- [x] docs/setup-guide.md explains `--verbose` behavior
- [x] .flow/memory/conventions.md has verbose pattern entry
- [x] CHANGELOG.md has entry under Unreleased documenting the breaking change
- [x] Note that `-v` is NOT a verbose shorthand (documented in all relevant places)
## Changes Made

### README.md
- Added note below Common Commands section explaining silent-by-default behavior
- Documented `--verbose` flag and `CONTAINAI_VERBOSE=1` environment variable

### AGENTS.md
- Added verbose pattern to Code Conventions section
- Documented `_cai_info()` usage, `--verbose` flag (no `-v`), and precedence rules

### docs/setup-guide.md
- Added "CLI Output Behavior" section to Table of Contents and document
- Updated setup command examples with explanatory comments about silent default
- Documented verbose output enablement, precedence rules, and `-v` flag note

### .flow/memory/conventions.md
- Added new convention entry dated 2026-01-30 documenting the verbose pattern

### CHANGELOG.md
- Added **BREAKING** change entry under Unreleased section
- Documented: silent default, `--verbose`/`CONTAINAI_VERBOSE`, precedence, `-v` note, exempt commands

## Acceptance Criteria Status
- [x] README.md mentions `--verbose` flag
- [x] AGENTS.md Code Conventions documents verbose pattern
- [x] docs/setup-guide.md explains `--verbose` behavior
- [x] .flow/memory/conventions.md has verbose pattern entry
- [x] CHANGELOG.md has entry under Unreleased documenting the breaking change
- [x] Note that `-v` is NOT a verbose shorthand (documented in all relevant places)
## Evidence
- Commits:
- Tests:
- PRs:
