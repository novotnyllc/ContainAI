# fn-29-fv0.4 Print container and volume names in run/shell output

## Description
Print container and volume names clearly in `cai run` and `cai shell` output.

**Size:** S
**Files:** `src/lib/container.sh`

## Problem

Users don't know what container/volume names to use with `cai doctor fix`. The names are generated but not clearly displayed.

## Approach

After container creation/connection, add clear output:
```
Container: containai-0898484b57d8
Volume: cai-dat
```

Add `cai workspace inspect` command that lists all containers and volumes associated with the workspace (available from config.toml).


Find the container lifecycle functions that print status and add name output:
- Look for `_cai_info` calls after container creation in `container.sh`
- The container name is in `$container_name` variable
- The volume name is in `$data_volume` variable

Use consistent format:
- `[INFO] Container: <name>`
- `[INFO] Volume: <volume>`

Place after existing "Creating new container..." or similar messages when verbose is requested.
## Acceptance
- [ ] `cai run` prints container name before executing command
- [ ] `cai shell` prints container name before connecting
- [ ] `cai shell --data-volume <name>` prints both container and volume names
- [ ] Output format is consistent and easily parseable
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
