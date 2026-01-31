# fn-31-gib.12 Install cai in container image

## Description
Add cai CLI to Dockerfile.agents as real executable (not just sourced in .bashrc). Must work non-interactively.

## Acceptance
- [ ] `/usr/local/bin/cai` exists in built image as executable wrapper
- [ ] Wrapper sources library and passes args: `source /opt/containai/containai.sh; cai "$@"`
- [ ] Library files present in `/opt/containai/` (containai.sh, lib/*.sh)
- [ ] `docker exec <container> cai --help` works (non-interactive test)
- [ ] `cai` available in interactive shell via sourced .bashrc
- [ ] Dockerfile changes in `src/container/Dockerfile.agents`

## Done summary
Added cai CLI to container image by copying containai.sh and lib/ to /opt/containai/, creating an executable wrapper at /usr/local/bin/cai for non-interactive use, and sourcing containai.sh in .bashrc for interactive shells.
## Evidence
- Commits: 5978fff7dd7e8d2dc4d46e6540be040dab15cddd
- Tests: docker build --check -f src/container/Dockerfile.agents src/
- PRs:
