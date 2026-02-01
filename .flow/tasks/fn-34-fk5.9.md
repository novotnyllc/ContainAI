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
- [ ] Lists candidates with `--dry-run`
- [ ] Interactive confirmation by default
- [ ] `--force` skips confirmation
- [ ] `--age` filters by timestamp (default 30d)
- [ ] Includes both `exited` and `created` status containers
- [ ] Uses FinishedAt for stopped, Created for never-ran
- [ ] Cross-platform timestamp parsing via Python
- [ ] `--images` prunes only `containai:*` and `ghcr.io/containai/*` images
- [ ] Only removes images not in use by any container
- [ ] Respects all protection rules
