# fn-29-fv0.4 Print container and volume names in run/shell output

## Description
Print container and volume names clearly in `cai run` and `cai shell` output.

**Size:** S
**Files:** `src/lib/container.sh`

## Problem

Users don't know what container/volume names to use with `cai doctor fix`. The names are generated but not clearly displayed.

## Approach

After container creation/connection, add clear output **to stderr** (not stdout - preserves `cai run <cmd>` pipelines):
```
[INFO] Container: containai-0898484b57d8
[INFO] Volume: cai-dat
```

**Output rules:**
- Always emit to stderr via `_cai_info` (which writes to stderr)
- Gate behind `--verbose` flag OR "not `--quiet`" so `cai run` remains script-friendly
- This ensures piped commands like `cai run cat /etc/os-release | grep VERSION` still work

Find the container lifecycle functions that print status and add name output:
- Look for `_cai_info` calls after container creation in `container.sh`
- The container name is in `$container_name` variable
- The volume name is in `$data_volume` variable

Place after existing "Creating new container..." or similar messages when verbose is requested.

**NOTE:** `cai workspace inspect` is OUT OF SCOPE for this task - it's scope creep and should be a separate epic if needed.
## Acceptance
- [ ] `cai run --verbose` prints container name to stderr before executing command
- [ ] `cai shell --verbose` prints container name to stderr before connecting
- [ ] `cai shell --verbose --data-volume <name>` prints both container and volume names to stderr
- [ ] Output goes to stderr (not stdout) to preserve pipeline compatibility
- [ ] Output is gated behind `--verbose` (or not `--quiet`) for script-friendliness
- [ ] Output format is consistent and easily parseable
## Done summary
Added --verbose flag to cai run and cai shell that prints container and volume names to stderr before executing commands. Output is properly gated behind --verbose and not --quiet flags for script-friendliness.
## Evidence
- Commits: beabed1, f506bab, 72c8b69, 5f5280b, d3410fa, 2782d35
- Tests: shellcheck -x src/containai.sh src/lib/container.sh
- PRs:
