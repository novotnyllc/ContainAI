# fn-10-vep.20 Reorganize repo structure to match CLI tool conventions

## Description
Reorganize the repository structure to match CLI tool conventions (docker-compose, dagger, mise patterns).

**Size:** M
**Files:** Multiple (rename/move operations)

## Target Structure

```
ContainAI/
├── src/
│   ├── docker/
│   │   ├── Dockerfile
│   │   ├── Dockerfile.test
│   │   └── configs/
│   ├── lib/
│   ├── containai.sh
│   ├── entrypoint.sh
│   └── build.sh
├── tests/
│   ├── test-sync-integration.sh
│   └── test-secure-engine.sh
├── docs/
├── .github/
│   └── workflows/
│       └── docker.yml
├── VERSION
├── README.md
└── SECURITY.md
```

## Approach

1. Create VERSION file with current version (0.1.0 or similar)
2. Rename `agent-sandbox/` to `src/`
3. Move Dockerfiles to `src/docker/`
4. Move test scripts to `tests/`
5. Update all path references in scripts and docs
6. **DO NOT touch `.flow/` or `scripts/` directories**

## Key files to reference

- Current structure: `agent-sandbox/` directory
- Build script: `agent-sandbox/build.sh` (needs path updates)
- containai.sh: References to Dockerfile paths
## Acceptance
- [ ] VERSION file created at repo root
- [ ] `agent-sandbox/` renamed to `src/`
- [ ] Dockerfiles moved to `src/docker/`
- [ ] Test scripts moved to `tests/`
- [ ] All path references updated
- [ ] `.flow/` and `scripts/` directories untouched
- [ ] Build still works after restructure
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
