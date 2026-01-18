# fn-4-vet.11 Create lib/export.sh - cai export subcommand

## Description
Create `agent-sandbox/lib/export.sh` - the `cai export` subcommand.

## Implementation

### `_containai_export(volume, output_path, excludes_array, no_excludes)`

1. Validate volume exists
2. Determine output path (default: `./containai-export-$(date +%Y%m%d-%H%M%S).tgz`)
3. Build tar exclude flags from `excludes_array` (unless `no_excludes`)
4. Run tar via docker container mounting the volume
5. Output archive path

## Docker Approach

```bash
docker run --rm \
  -v "${volume}:/data:ro" \
  -v "$(dirname "$output_path"):/out" \
  alpine:latest \
  tar -czf "/out/$(basename "$output_path")" \
  ${exclude_flags[@]} \
  -C /data .
```

## Exclude Flags

```bash
# Convert excludes to tar --exclude patterns
for pattern in "${excludes[@]}"; do
    tar_opts+=(--exclude "$pattern")
done
```

## Key Points
- Volume mounted read-only for safety
- Output to current dir by default, or specified `-o` path
- Respects cumulative excludes from config
- `--no-excludes` includes everything
## Acceptance
- [ ] File exists at `agent-sandbox/lib/export.sh`
- [ ] `_containai_export` creates valid .tgz archive
- [ ] Exclude patterns applied to tar
- [ ] `-o/--output` specifies output path
- [ ] `--no-excludes` includes all files
- [ ] Volume mounted read-only
- [ ] Outputs archive path on success
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
