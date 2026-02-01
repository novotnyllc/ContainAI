# fn-34-fk5.9: Implement cai gc command

## Goal
Implement garbage collection command to prune stale ContainAI containers.

## Staleness Metric
- Stopped containers (`status=exited`): use `.State.FinishedAt`
- Never-ran containers (`status=created`): use `.Created` timestamp
- Calculate age from current time minus timestamp

## Protection Rules
1. Never prune running containers
2. Never prune containers with `containai.keep=true` label
3. Only prune containers with `containai.managed=true` label
4. Operates on current Docker context only

## Cross-Platform Timestamp Parsing
Use Python for portable RFC3339 parsing (both Linux and macOS):
```bash
_cai_parse_timestamp() {
    python3 -c "from datetime import datetime; import sys; ..." "$ts"
}
```

## Image Pruning (`--images`)
Prune unused images matching these exact prefixes:
- `containai:*` (local builds)
- `ghcr.io/containai/*` (official registry)

Only remove images NOT in use by any container (running or stopped).

Pattern match: `grep -E '^(containai:|ghcr\.io/containai/)'`

## Files
- `src/containai.sh`: Add `_containai_gc_cmd` and routing
- `src/lib/core.sh` or inline: Add `_cai_parse_timestamp` helper

## Acceptance
- [x] Lists candidates with `--dry-run`
- [x] Interactive confirmation by default
- [x] `--force` skips confirmation
- [x] `--age` filters by timestamp (default 30d)
- [x] Includes both `exited` and `created` status containers
- [x] Uses FinishedAt for stopped, Created for never-ran
- [x] Cross-platform timestamp parsing via Python
- [x] `--images` prunes only `containai:*` and `ghcr.io/containai/*` images
- [x] Only removes images not in use by any container
- [x] Respects all protection rules

## Done summary
# fn-34-fk5.9: Implement cai gc command

## Summary
Implemented garbage collection command for ContainAI with full functionality as specified.

## Changes

### src/lib/core.sh
- Added `_cai_parse_age_to_seconds()` helper for parsing age duration strings (e.g., "30d", "7d", "24h")
- Added `_cai_parse_timestamp_to_epoch()` helper for cross-platform RFC3339 timestamp parsing using Python

### src/containai.sh
- Added `_containai_gc_help()` help function with complete documentation
- Added `_containai_gc_cmd()` main command handler implementing:
  - Argument parsing: `--dry-run`, `--force`, `--age <duration>`, `--images`, `--verbose`, `--help`
  - Container pruning with protection rules:
    1. Only containers with `containai.managed=true` label
    2. Never running containers
    3. Never containers with `containai.keep=true` label
  - Staleness calculation using:
    - `.State.FinishedAt` for exited containers
    - `.Created` for never-ran (created) containers
  - Image pruning for `containai:*` and `ghcr.io/containai/*` prefixes
  - Interactive confirmation (unless `--force`)
  - SSH config cleanup after container removal
- Added routing in main `containai()` function for `gc` subcommand
- Updated main help to include `gc` command

## Acceptance Criteria Met
- [x] Lists candidates with `--dry-run`
- [x] Interactive confirmation by default
- [x] `--force` skips confirmation
- [x] `--age` filters by timestamp (default 30d)
- [x] Includes both `exited` and `created` status containers
- [x] Uses FinishedAt for stopped, Created for never-ran
- [x] Cross-platform timestamp parsing via Python
- [x] `--images` prunes only `containai:*` and `ghcr.io/containai/*` images
- [x] Only removes images not in use by any container
- [x] Respects all protection rules
## Evidence
- Commits:
- Tests:
- PRs:
