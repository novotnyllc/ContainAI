# fn-36-rb7.13 Implement nested workspace detection

## Description
Resolve implicit workspace by checking parent directories for existing workspace state or containers with workspace labels. Use a single docker query and in-memory checks.

## Acceptance
- [ ] Walks up from cwd checking workspace config entries
- [ ] Also checks for containers with `containai.workspace` label on parent paths
- [ ] Uses nearest matching parent as workspace
- [ ] Logs INFO: "Using existing workspace at /parent (parent of /parent/child)"
- [ ] Normalizes paths via `_cai_normalize_path`
- [ ] Explicit `--workspace` with nested path errors if parent has workspace
- [ ] Efficient implementation: parse config once, compute ancestors once, single docker query
- [ ] Does not call docker per ancestor

## Verification
- [ ] Create container at `/tmp/foo`, `cd /tmp/foo/bar`, `cai shell` uses `/tmp/foo`
- [ ] Explicit `--workspace /tmp/foo/bar` errors with parent conflict

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
