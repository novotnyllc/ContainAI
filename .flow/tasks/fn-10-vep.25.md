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
Created install.sh distribution script enabling one-liner installation via `curl | bash`. The script detects OS (macOS/Linux distros), checks prerequisites (Docker, git), clones the repo to ~/.local/share/containai, creates a wrapper script at ~/.local/bin/cai with the install directory baked in, and updates the user's shell rc file with the appropriate PATH entry. The installer runs on bash 3.2+ while the CLI requires bash 4.0+. README updated with installation one-liner.
## Evidence
- Commits: 18da2f072cd1bb7d0e20f2a87e6d6a42e94ae56c, d107d077bf2e0bdc73ce72ebae2cf6f74b2d1c5a, eec7b0257eb65506d02d7b690d6d5878f8a4c558
- Tests: bash -n install.sh, shellcheck install.sh
- PRs:
