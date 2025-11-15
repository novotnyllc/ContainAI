# Finding: Verify script treats optional GitHub CLI as hard requirement
- Category: Correctness vs Intended Behavior / Parity
- Files: scripts/verify-prerequisites.sh (GitHub CLI check block), scripts/verify-prerequisites.ps1 (GitHub CLI section)
- Problem: README explicitly states the verification script should only *warn* if GitHub CLI is missing, but both scripts call print_error/Write-ErrorMsg, increment failed counters, and exit with status 1 when gh is absent or unauthenticated. Users who do not rely on gh cannot complete verification successfully, contradicting documented behavior.
- Impact: Prevents successful prerequisite checks on systems that intentionally omit gh, creating false negatives and blocking onboarding.
- Expected: Treat GitHub CLI install/auth as optional (warning/info) unless host actually depends on it; successful run should still exit 0 when gh is missing but other mandatory prerequisites are satisfied.
- Notes: Applies equally to shell and PowerShell versions; adjust parity when fixing.