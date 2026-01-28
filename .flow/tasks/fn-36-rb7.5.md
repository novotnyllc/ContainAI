# fn-36-rb7.5 Implement human-readable container naming

## Description
Replace hash-based naming with `containai-{repo}-{branch}` format. Keep `_containai_container_name` as a pure function; collision handling remains in `_cai_resolve_container_name`.

## Acceptance
- [ ] Format: `containai-{repo}-{branch}`, max 63 chars
- [ ] Repo = directory name (last path component)
- [ ] Branch from `git rev-parse --abbrev-ref HEAD`
- [ ] Non-git: use `nogit`
- [ ] Detached HEAD: use 7-char short SHA
- [ ] Sanitization: lowercase, `/` → `-`, remove non-alphanum except `-`
- [ ] Truncate base name to 59 chars (reserve 4 for suffix)
- [ ] `_containai_container_name` has no docker calls or collision logic

## Verification
- [ ] Test naming in git repo, non-git dir, detached HEAD, and long names

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
