# fn-37-4xi.2 Verify layer validation docs match implementation

## Description
Review and verify that the new contract doc and existing docs accurately describe the current validation behavior. The implementation validates Dockerfile FROM lines (not runtime layer history). Ensure no misleading language about "layer history" validation.

**Note**: The validation code already exists in `src/lib/template.sh:523` (`_cai_validate_template_base`). This task is verification/alignment, not implementation.

## Acceptance
- [x] `docs/base-image-contract.md` Validation section accurately describes FROM-based validation
- [x] No mention of "docker image history" or "layer history" as validation method
- [x] Document explains ARG variable substitution in FROM lines
- [x] Document lists all three accepted patterns:
  - `ghcr.io/novotnyllc/containai*`
  - `containai:*`
  - `containai-template-*:local`
- [x] Document mentions unresolved-variable warning path
- [x] Verified `docs/configuration.md` doesn't contradict the contract doc

## Done summary
Verified that documentation accurately describes the template base image validation behavior:

1. **FROM-based validation**: `docs/base-image-contract.md` lines 99-110 correctly describe that validation parses the first `FROM` line from the Dockerfile source (not runtime layer history)

2. **No incorrect references**: Neither `docs/base-image-contract.md` nor `docs/configuration.md` mention "docker image history" or "layer history"

3. **ARG substitution documented**: Lines 101-102 explain the three supported variable formats (`$VAR`, `${VAR}`, `${VAR:-default}`)

4. **All three patterns listed**: Lines 103-106 list exactly the patterns from `_cai_validate_template_base()`:
   - `ghcr.io/novotnyllc/containai*`
   - `containai:*`
   - `containai-template-*:local`

5. **Unresolved variable warning**: Lines 107-108 mention the warning path for unresolved ARG variables

6. **Configuration consistency**: `docs/configuration.md` `[template]` section (lines 296-317) is consistent with the contract doc - both describe `suppress_base_warning` identically

No code changes required - this was a verification task and all documentation is already accurate.

## Evidence
- Commits: (none - verification task)
- Tests: (none - verification task)
- PRs:
