# fn-33-lp4.5 Implement layer stack validation

## Description
Parse Dockerfile FROM line to check if base matches ContainAI patterns. Warn if not (unless suppressed). Include entrypoint warning in message. Handle ARG variable substitution.

## Acceptance
- [ ] `_cai_validate_template_base()` function parses Dockerfile
- [ ] Handles `ARG VAR=value` + `FROM $VAR` substitution
- [ ] Accepts patterns: `containai:*`, `ghcr.io/novotnyllc/containai*`, `containai-template-*:local`
- [ ] Warning emitted to stderr if no match
- [ ] Different warning if FROM uses unresolved variable
- [ ] Warning includes: "ENTRYPOINT must not be overridden or systemd won't start"
- [ ] Warning includes config suppression hint

## Done summary
## Implementation Summary

Added `_cai_validate_template_base()` function to `src/lib/template.sh` that validates whether a user's template Dockerfile is based on ContainAI images.

### Features
- Parses Dockerfile for ARG and FROM lines
- Handles ARG variable substitution:
  - `$VAR` syntax
  - `${VAR}` syntax
  - `${VAR:-default}` syntax with default fallback
- Validates against accepted patterns:
  - `containai:*`
  - `ghcr.io/novotnyllc/containai*`
  - `containai-template-*:local` (chained templates)
- Emits appropriate warnings to stderr:
  - For non-ContainAI base images
  - For unresolved variables
- Warnings include:
  - Note about ENTRYPOINT and systemd
  - Config suppression hint (`[template].suppress_base_warning = true`)
- Warning suppression via second argument

### Return Codes
- 0: Valid ContainAI base
- 1: Invalid/unresolved base
- 2: Parse error (missing file, no FROM)

### Files Modified
- `src/lib/template.sh`: Added function and updated header docs
- `tests/unit/test-template-paths.sh`: Added 15 unit tests
## Evidence
- Commits:
- Tests:
- PRs:
