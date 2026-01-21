# fn-10-vep.25 Create install.sh distribution script

## Description
Create installer script for easy one-liner installation (curl | bash pattern).

**Size:** M
**Files:**
- `install.sh` (new, at repo root)

## Approach

1. Detect OS (macOS, Linux)
2. Check prerequisites (Docker, git)
3. Clone repo or download release
4. Set up shell integration (add to PATH)
5. Run initial setup if needed

## Key context

- Target: `curl -fsSL https://raw.githubusercontent.com/novotnyllc/ContainAI/main/install.sh | bash`
- Should work on macOS and Linux
- Handle both fresh install and update
## Acceptance
- [ ] install.sh created at repo root
- [ ] Works on macOS
- [ ] Works on Linux (Ubuntu, Debian, Fedora)
- [ ] Detects and reports missing prerequisites
- [ ] Adds cai to PATH
- [ ] Idempotent (safe to run multiple times)
- [ ] One-liner documented in README
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
