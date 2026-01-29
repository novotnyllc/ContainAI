# fn-35-e0x.3 Add Pi to Dockerfile.agents

## Description
Run the build script to regenerate all generated files and rebuild the Docker image.

**Size:** S
**Files:** Generated files (auto-created)

## Approach

```bash
./src/build.sh
```

This will:
1. Regenerate `src/container/generated/symlinks.sh`
2. Regenerate `src/container/generated/init-dirs.sh`
3. Regenerate `src/container/generated/link-spec.json`
4. Build the Docker image

## Key context

- build.sh auto-runs all generators at lines 392-407
- No need to run individual gen-* scripts
## Acceptance
- [ ] Generators run successfully
- [ ] symlinks.sh includes Pi and Kimi entries
- [ ] init-dirs.sh includes Pi and Kimi directories
- [ ] link-spec.json includes Pi and Kimi entries
- [ ] Docker image builds without errors
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
