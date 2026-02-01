# fn-33-lp4.2 Create template files in repo

## Description
Create `src/templates/default.Dockerfile` and `src/templates/example-ml.Dockerfile` with comprehensive comments. Use symlink pattern for systemd service enabling (NOT `systemctl enable` which fails in docker build).

## Acceptance
- [ ] `src/templates/default.Dockerfile` exists with ENTRYPOINT/CMD/USER warnings
- [ ] Default template uses `FROM ghcr.io/novotnyllc/containai:latest`
- [ ] Comments show symlink pattern: `ln -sf /etc/systemd/system/foo.service /etc/systemd/system/multi-user.target.wants/`
- [ ] `src/templates/example-ml.Dockerfile` exists with ML tools example
- [ ] Example uses symlink pattern (not `systemctl enable`)
- [ ] Example uses `printf` not `echo` (per project conventions)

## Done summary
# fn-33-lp4.2 Summary

Created template files in `src/templates/`:

1. **default.Dockerfile** - Comprehensive user template with:
   - `FROM ghcr.io/novotnyllc/containai:latest` as base image
   - ENTRYPOINT/CMD/USER warnings in header
   - Commented examples for system packages, Node/Python/Rust tools
   - Systemd service examples using symlink pattern (not `systemctl enable`)
   - Environment variable examples

2. **example-ml.Dockerfile** - ML development example with:
   - CUDA toolkit installation
   - Python ML packages (torch, numpy, pandas)
   - GPU check startup script using `printf` (not `echo`)
   - Systemd service using symlink pattern for enabling
## Evidence
- Commits:
- Tests:
- PRs:
