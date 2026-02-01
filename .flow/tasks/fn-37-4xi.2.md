# fn-37-4xi.2 Verify layer validation docs match implementation

## Description
Review and verify that the new contract doc and existing docs accurately describe the current validation behavior. The implementation validates Dockerfile FROM lines (not runtime layer history). Ensure no misleading language about "layer history" validation.

**Note**: The validation code already exists in `src/lib/template.sh:523` (`_cai_validate_template_base`). This task is verification/alignment, not implementation.

## Acceptance
- [ ] `docs/base-image-contract.md` Validation section accurately describes FROM-based validation
- [ ] No mention of "docker image history" or "layer history" as validation method
- [ ] Document explains ARG variable substitution in FROM lines
- [ ] Document lists all three accepted patterns:
  - `ghcr.io/novotnyllc/containai*`
  - `containai:*`
  - `containai-template-*:local`
- [ ] Document mentions unresolved-variable warning path
- [ ] Verified `docs/configuration.md` doesn't contradict the contract doc

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
