# fn-32-2mq.2 Implement version bump script

## Description

Create `scripts/bump-version.sh` to increment the VERSION file following semver rules. Script is called by release-cut workflow and can also be run locally for testing.

**Implementation:**
```bash
#!/usr/bin/env bash
set -euo pipefail

BUMP_TYPE="${1:-patch}"
VERSION_FILE="VERSION"

# Read current version
current=$(cat "$VERSION_FILE" | tr -d '[:space:]')

# Parse into components
IFS='.' read -r major minor patch <<< "$current"

# Increment based on bump type
case "$BUMP_TYPE" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  *) echo "Usage: $0 [major|minor|patch]" >&2; exit 1 ;;
esac

new_version="${major}.${minor}.${patch}"
echo "$new_version" > "$VERSION_FILE"
echo "Bumped version: $current → $new_version"
```

**Validation:**
- VERSION file must exist and contain valid semver (X.Y.Z)
- Rejects pre-release suffixes (e.g., 0.1.0-beta)
- Handles edge cases: 0.0.0 → 0.0.1, 0.9.9 → 0.9.10

## Acceptance

- [ ] Script exists at `scripts/bump-version.sh` and is executable
- [ ] Accepts single argument: major, minor, or patch (defaults to patch)
- [ ] Correctly increments major version (resets minor and patch to 0)
- [ ] Correctly increments minor version (resets patch to 0)
- [ ] Correctly increments patch version
- [ ] Writes new version to VERSION file (no trailing newline issues)
- [ ] Outputs "Bumped version: X.Y.Z → A.B.C" to stdout
- [ ] Exits 1 with usage message for invalid bump type
- [ ] Exits 1 if VERSION file doesn't exist
- [ ] Exits 1 if VERSION contains invalid format (not X.Y.Z)
- [ ] Uses POSIX-compatible parsing (no bash-specific regex)

## Done summary
Implemented `scripts/bump-version.sh` with full semver version bump capabilities:
- Accepts major/minor/patch argument (defaults to patch)
- Validates VERSION file exists and contains valid X.Y.Z format
- Rejects pre-release suffixes (e.g., 0.1.0-beta)
- Uses POSIX-compatible parsing (BRE grep patterns, no bash-specific regex)
- Outputs "Bumped version: X.Y.Z → A.B.C" format
- All edge cases handled: 0.0.0 → 0.0.1, 0.9.9 → 0.9.10
## Evidence
- Commits: ee93fe8
- Tests:
- PRs:
