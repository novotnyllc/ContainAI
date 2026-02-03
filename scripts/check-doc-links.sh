#!/usr/bin/env bash
# check-doc-links.sh - Validate internal documentation links
#
# Validates all internal markdown links (relative paths and anchors) in the
# docs/ directory and root markdown files. Ensures broken links are caught
# before they reach production.
#
# Usage:
#   ./scripts/check-doc-links.sh [options]
#
# Options:
#   --verbose     Show all files being checked (including those without errors)
#   --help        Show this help message
#
# Example output:
#   Checking docs/quickstart.md...
#     [ERROR] docs/quickstart.md:42: SECURITY.md does not exist
#     [ERROR] docs/quickstart.md:56: #nonexistent-anchor - anchor not found in this file
#     [ERROR] docs/quickstart.md:78: docs/bar.md#section - anchor not found in target
#   ...
#   Summary: 3 broken links in 1 file
#
# Exit codes:
#   0 - All links valid
#   1 - Broken links found
#   2 - Script error (missing dependencies, etc.)
#
# Limitations:
#   - Only checks inline links [text](target), not reference-style [text][id]
#   - Links inside inline code `[text](link)` are still checked (use fenced blocks)
#   - Anchor slugging approximates GitHub's algorithm (ASCII headings work best)
#   - Absolute paths (/foo) are rejected; use relative paths only

set -euo pipefail

# Find repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Options
VERBOSE=false

# Counters
TOTAL_BROKEN=0
FILES_WITH_ERRORS=0

# Color codes (disabled if not a terminal - check both stdout and stderr)
if [[ -t 1 ]] || [[ -t 2 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

usage() {
    sed -n '2,/^$/{ s/^# //; s/^#//; p }' "$0"
    exit 0
}

# Check for required dependencies
check_dependencies() {
    if ! command -v perl >/dev/null 2>&1; then
        printf '%sError: perl is required but not found%s\n' "$RED" "$NC" >&2
        exit 2
    fi
    if ! command -v realpath >/dev/null 2>&1; then
        printf '%sError: realpath is required but not found%s\n' "$RED" "$NC" >&2
        exit 2
    fi
}

log_error() {
    local file="$1"
    local line_num="$2"
    local msg="$3"
    printf '%s  [ERROR]%s %s:%d: %s\n' "$RED" "$NC" "$file" "$line_num" "$msg" >&2
}

log_warning() {
    local file="$1"
    local line_num="$2"
    local msg="$3"
    printf '%s  [WARN]%s %s:%d: %s\n' "$YELLOW" "$NC" "$file" "$line_num" "$msg" >&2
}

log_info() {
    if [[ "$VERBOSE" == "true" ]]; then
        printf "%s\n" "$1"
    fi
}

# Convert heading text to GitHub-style anchor
# GitHub's algorithm:
# 1. Convert to lowercase
# 2. Remove anything that is not a letter, number, space, or hyphen
# 3. Replace spaces with hyphens
# Note: GitHub does NOT collapse multiple hyphens - "foo--bar" stays as "foo--bar"
heading_to_anchor() {
    local heading="$1"

    # Remove leading/trailing whitespace
    heading="${heading#"${heading%%[![:space:]]*}"}"
    heading="${heading%"${heading##*[![:space:]]}"}"

    # Convert to lowercase
    heading=$(printf '%s' "$heading" | tr '[:upper:]' '[:lower:]')

    # Remove characters that GitHub removes from anchors:
    # Keep: alphanumeric, spaces, hyphens, underscores
    # Note: We keep spaces here, then convert to hyphens
    heading=$(printf '%s' "$heading" | sed 's/[^a-z0-9 _-]//g')

    # Replace spaces with hyphens
    heading=$(printf '%s' "$heading" | tr ' ' '-')

    # Remove leading/trailing hyphens
    heading="${heading#-}"
    heading="${heading%-}"

    printf '%s' "$heading"
}

# Extract all heading anchors from a markdown file
# Handles duplicate headings by appending -1, -2, etc. (GitHub style)
# Skips headings inside fenced code blocks
extract_anchors() {
    local file="$1"
    declare -A anchor_counts
    local in_code_block=false
    local code_fence=""
    local code_fence_char=""
    local code_fence_len=0

    while IFS= read -r line; do
        # Check for fenced code block boundaries (``` or ~~~, length >= 3)
        # shellcheck disable=SC1009,SC1072,SC1073
        if [[ "$line" =~ ^[[:space:]]*([~]{3,}|\`{3,}) ]]; then
            local fence="${BASH_REMATCH[1]}"
            local fence_char="${fence:0:1}"
            local fence_len=${#fence}
            if [[ "$in_code_block" == "false" ]]; then
                in_code_block=true
                code_fence="$fence"
                code_fence_char="$fence_char"
                code_fence_len=$fence_len
            elif [[ "$fence_char" == "$code_fence_char" && "$fence_len" -ge "$code_fence_len" ]]; then
                in_code_block=false
                code_fence=""
                code_fence_char=""
                code_fence_len=0
            fi
            continue
        fi

        # Skip lines inside code blocks
        if [[ "$in_code_block" == "true" ]]; then
            continue
        fi

        # Match markdown headings (# ## ### etc.)
        if [[ "$line" =~ ^[[:space:]]*(#{1,6})[[:space:]]+(.+)$ ]]; then
            local heading_text="${BASH_REMATCH[2]}"
            local anchor
            anchor=$(heading_to_anchor "$heading_text")

            if [[ -n "$anchor" ]]; then
                # Track duplicates
                local count="${anchor_counts[$anchor]:-0}"
                if [[ "$count" -eq 0 ]]; then
                    printf '%s\n' "$anchor"
                    anchor_counts[$anchor]=1
                else
                    printf '%s\n' "${anchor}-${count}"
                    anchor_counts[$anchor]=$((count + 1))
                fi
            fi
        fi
    done < "$file"
}

# Check if an anchor exists in a file
anchor_exists() {
    local file="$1"
    local anchor="$2"

    local anchors
    anchors=$(extract_anchors "$file")

    # Check if anchor is in the list
    if printf '%s\n' "$anchors" | grep -qxF "$anchor"; then
        return 0
    fi

    return 1
}

# Check a single markdown file for broken links
# shellcheck disable=SC2094
check_file() {
    local file="$1"
    local file_dir
    file_dir=$(dirname "$file")
    local file_errors=0
    local line_num=0
    local in_code_block=false
    local code_fence=""
    local code_fence_char=""
    local code_fence_len=0
    local header_printed=false

    if [[ "$VERBOSE" == "true" ]]; then
        printf 'Checking %s...\n' "$file"
        header_printed=true
    fi

    while IFS= read -r line; do
        ((line_num++)) || true

        # Check for fenced code block boundaries (``` or ~~~, length >= 3)
        # Skip link checking inside code blocks
        # shellcheck disable=SC1009,SC1072,SC1073
        if [[ "$line" =~ ^[[:space:]]*([~]{3,}|\`{3,}) ]]; then
            local fence="${BASH_REMATCH[1]}"
            local fence_char="${fence:0:1}"
            local fence_len=${#fence}
            if [[ "$in_code_block" == "false" ]]; then
                in_code_block=true
                code_fence="$fence"
                code_fence_char="$fence_char"
                code_fence_len=$fence_len
            elif [[ "$fence_char" == "$code_fence_char" && "$fence_len" -ge "$code_fence_len" ]]; then
                in_code_block=false
                code_fence=""
                code_fence_char=""
                code_fence_len=0
            fi
            continue
        fi

        # Skip lines inside code blocks
        if [[ "$in_code_block" == "true" ]]; then
            continue
        fi

        # Extract markdown links: [text](target)
        # Strip inline images to avoid capturing nested image URLs
        # Use perl for better regex handling - outputs one link per line
        local links
        links=$(printf '%s' "$line" | perl -ne 's/!\[[^\]]*\]\([^)]*\)//g; while (/\[[^\]]*\]\(([^)]+)\)/g) { my $t=$1; $t =~ s/^[[:space:]]+|[[:space:]]+$//g; $t =~ s/[[:space:]]+"[^"]*"$//; $t =~ s/[[:space:]]+\x27[^\x27]*\x27$//; $t =~ s/[[:space:]]+$//; print "$t\n"; }')

        # Iterate links line-by-line to handle spaces correctly
        while IFS= read -r link; do
            [[ -z "$link" ]] && continue

            link="${link#<}"
            link="${link%>}"
            link="${link%%[[:space:]]*}"

            # Skip external URLs (http://, https://, mailto:, ftp://, data:)
            if [[ "$link" =~ ^(https?://|mailto:|ftp://|data:) ]]; then
                continue
            fi

            # Parse link into path and anchor
            local link_path=""
            local link_anchor=""

            if [[ "$link" =~ ^#(.+)$ ]]; then
                # Same-file anchor: #section
                link_anchor="${BASH_REMATCH[1]}"
            elif [[ "$link" =~ ^([^#]+)#(.+)$ ]]; then
                # Path with anchor: file.md#section
                link_path="${BASH_REMATCH[1]}"
                link_anchor="${BASH_REMATCH[2]}"
            else
                # Just a path: file.md or docs/file.md
                link_path="$link"
            fi

            # Resolve the target file path
            local target_file=""
            if [[ -n "$link_path" ]]; then
                # Absolute paths starting with / are invalid for internal docs
                # GitHub interprets /foo as site-root absolute, not repo-relative
                if [[ "$link_path" =~ ^/ ]]; then
                    if [[ "$header_printed" == "false" ]]; then
                        printf 'Checking %s...\n' "$file" >&2
                        header_printed=true
                    fi
                    log_error "$file" "$line_num" "$link_path - absolute paths not supported (use relative paths)"
                    ((file_errors++)) || true
                    continue
                fi

                # Relative path from current file's directory
                target_file="${file_dir}/${link_path}"

                # Normalize path (resolve .., remove .)
                # First get absolute canonical path
                target_file=$(realpath -m -- "$target_file" 2>/dev/null || printf '%s' "$target_file")

                # Security check: ensure resolved path stays within REPO_ROOT
                # Links escaping the repo are invalid (they won't work on GitHub)
                if [[ "$target_file" != "$REPO_ROOT"/* && "$target_file" != "$REPO_ROOT" ]]; then
                    if [[ "$header_printed" == "false" ]]; then
                        printf 'Checking %s...\n' "$file" >&2
                        header_printed=true
                    fi
                    log_error "$file" "$line_num" "$link_path resolves outside repository"
                    ((file_errors++)) || true
                    continue
                fi
            else
                # Same-file anchor
                target_file="$file"
            fi

            # Check if target file/directory exists
            if [[ -n "$link_path" ]]; then
                if [[ -f "$target_file" ]]; then
                    : # File exists, continue to anchor check
                elif [[ -d "$target_file" ]]; then
                    # Directory link - valid on GitHub (shows README.md)
                    # For anchor checking, use the directory's README.md if it exists
                    if [[ -f "${target_file}/README.md" ]]; then
                        target_file="${target_file}/README.md"
                    elif [[ -n "$link_anchor" ]]; then
                        # Directory with anchor but no README - treat as error
                        # Can't validate anchor, and this is likely a broken link
                        if [[ "$header_printed" == "false" ]]; then
                            printf 'Checking %s...\n' "$file" >&2
                            header_printed=true
                        fi
                        log_error "$file" "$line_num" "${link_path}#${link_anchor} - directory has no README.md to check anchor"
                        ((file_errors++)) || true
                        continue
                    fi
                    # Directory without anchor is valid
                else
                    if [[ "$header_printed" == "false" ]]; then
                        printf 'Checking %s...\n' "$file" >&2
                        header_printed=true
                    fi
                    log_error "$file" "$line_num" "$link_path does not exist"
                    ((file_errors++)) || true
                    continue
                fi
            fi

            # Check anchor if present
            if [[ -n "$link_anchor" ]]; then
                if [[ -f "$target_file" ]]; then
                    if ! anchor_exists "$target_file" "$link_anchor"; then
                        if [[ -z "$link_path" ]]; then
                            if [[ "$header_printed" == "false" ]]; then
                                printf 'Checking %s...\n' "$file" >&2
                                header_printed=true
                            fi
                            log_error "$file" "$line_num" "#$link_anchor - anchor not found in this file"
                        else
                            if [[ "$header_printed" == "false" ]]; then
                                printf 'Checking %s...\n' "$file" >&2
                                header_printed=true
                            fi
                            log_error "$file" "$line_num" "${link_path}#${link_anchor} - anchor not found in target"
                        fi
                        ((file_errors++)) || true
                    fi
                fi
            fi
        done <<< "$links"
    done < "$file"

    if [[ "$file_errors" -gt 0 ]]; then
        ((FILES_WITH_ERRORS++)) || true
        TOTAL_BROKEN=$((TOTAL_BROKEN + file_errors))
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            printf "Unknown option: %s\n" "$1" >&2
            exit 1
            ;;
    esac
done

# Check dependencies before proceeding
check_dependencies

# Find all markdown files to check
cd "$REPO_ROOT"

# Root markdown files
ROOT_MD_FILES=$(find . -maxdepth 1 -name "*.md" -type f | sort)

# docs/ markdown files (recursive)
DOCS_MD_FILES=""
if [[ -d docs ]]; then
    DOCS_MD_FILES=$(find docs -name "*.md" -type f | sort)
fi

# Combine and check
ALL_FILES="$ROOT_MD_FILES"
if [[ -n "$DOCS_MD_FILES" ]]; then
    ALL_FILES="$ALL_FILES
$DOCS_MD_FILES"
fi

# Check each file
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    check_file "$file"
done <<< "$ALL_FILES"

# Summary
if [[ "$TOTAL_BROKEN" -eq 0 ]]; then
    printf '%s%s%s\n' "$GREEN" "All documentation links are valid." "$NC"
    exit 0
else
    printf '\n%sSummary: %d broken link(s) in %d file(s)%s\n' "$RED" "$TOTAL_BROKEN" "$FILES_WITH_ERRORS" "$NC"
    exit 1
fi
