# fn-12-css.11 Merge install-containai-docker.sh into cai setup

**STATUS: SKIPPED** - Superseded by fn-14-nm0 (tasks .2 and .3)

## Description

~~Consolidate the Docker/Sysbox installation logic from `scripts/install-containai-docker.sh` into `lib/setup.sh`. This provides a single entry point (`cai setup`) for all installation needs.~~

This task has been superseded by epic **fn-14-nm0** (Fix cai setup Docker isolation), which includes merging `install-containai-docker.sh` as part of tasks:
- fn-14-nm0.2: Refactor WSL2 setup for isolated Docker
- fn-14-nm0.3: Refactor Native Linux setup for isolated Docker (deletes script)

## Done summary

Superseded by fn-14-nm0 - the script merge is now part of the Docker isolation fix epic.

## Evidence

- Superseded by: fn-14-nm0
