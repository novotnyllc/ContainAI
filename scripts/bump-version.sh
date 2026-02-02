#!/usr/bin/env bash
# Bump VERSION file using semver rules.
# Usage: scripts/bump-version.sh [major|minor|patch]
# Defaults to patch if no argument provided.
set -euo pipefail

BUMP_TYPE="${1:-patch}"

case "$BUMP_TYPE" in
    major|minor|patch) ;;
    *)
        printf 'Usage: %s [major|minor|patch]\n' "${0##*/}" >&2
        exit 1
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
    printf 'ERROR: VERSION file not found: %s\n' "$VERSION_FILE" >&2
    exit 1
fi

current=$(tr -d '[:space:]' <"$VERSION_FILE")

# POSIX-compatible version parsing (no bash-specific regex)
# Validate format: X.Y.Z where X, Y, Z are non-negative integers
major="${current%%.*}"
rest="${current#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"

# Validate each component is a non-negative integer (BRE-compatible pattern)
if ! printf '%s\n' "$major" | grep -q '^[0-9][0-9]*$'; then
    printf 'ERROR: invalid VERSION format: %s\n' "$current" >&2
    exit 1
fi
if ! printf '%s\n' "$minor" | grep -q '^[0-9][0-9]*$'; then
    printf 'ERROR: invalid VERSION format: %s\n' "$current" >&2
    exit 1
fi
if ! printf '%s\n' "$patch" | grep -q '^[0-9][0-9]*$'; then
    printf 'ERROR: invalid VERSION format: %s\n' "$current" >&2
    exit 1
fi

# Ensure format is exactly X.Y.Z (no extra dots)
if [[ "$current" != "${major}.${minor}.${patch}" ]]; then
    printf 'ERROR: invalid VERSION format: %s\n' "$current" >&2
    exit 1
fi

case "$BUMP_TYPE" in
    major)
        major=$((major + 1))
        minor=0
        patch=0
        ;;
    minor)
        minor=$((minor + 1))
        patch=0
        ;;
    patch)
        patch=$((patch + 1))
        ;;
esac

new_version="${major}.${minor}.${patch}"
printf '%s\n' "$new_version" > "$VERSION_FILE"
printf 'Bumped version: %s → %s\n' "$current" "$new_version"
