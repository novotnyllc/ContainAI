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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
