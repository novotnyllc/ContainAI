# fn-10-vep.60 Dynamic resource detection (50% host memory/CPU)

## Description
Dynamic resource detection - default to 50% of host memory/CPU.

**Size:** S
**Files:** lib/container.sh

## Approach

1. Create `_cai_detect_resources()`:
   - Linux: Read `/proc/meminfo` and `nproc`
   - macOS: Use `sysctl hw.memsize` and `hw.ncpu`
2. Default: 50% of detected resources
3. Minimums: 2GB memory, 1 CPU
4. Configurable via `[container].memory` and `[container].cpus`
5. CLI flags `--memory` and `--cpus` override all

## Key context

- Previous hardcoded 4GB/2CPU was too small for larger machines
- 50% leaves room for host apps while giving good container resources
- Minimums prevent unusable containers on small machines
## Acceptance
- [ ] Auto-detects host memory (Linux and macOS)
- [ ] Auto-detects host CPU count (Linux and macOS)
- [ ] Default: 50% of host resources
- [ ] Minimum: 2GB memory, 1 CPU
- [ ] Configurable via `[container].memory` and `[container].cpus`
- [ ] `--memory` and `--cpus` CLI flags override config
- [ ] `cai doctor` shows detected vs configured resources
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
