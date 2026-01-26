#!/usr/bin/env bash
# Validate that Dockerfile.agents symlinks match sync-manifest.toml
# Usage: validate-dockerfile-symlinks.sh <manifest_path> <dockerfile_path>
# Returns 0 if symlinks match, 1 if mismatches found
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_FILE="${1:-}"
DOCKERFILE="${2:-}"

if [[ -z "$MANIFEST_FILE" || ! -f "$MANIFEST_FILE" ]]; then
    printf 'ERROR: manifest file required as first argument\n' >&2
    exit 1
fi
if [[ -z "$DOCKERFILE" || ! -f "$DOCKERFILE" ]]; then
    printf 'ERROR: Dockerfile required as second argument\n' >&2
    exit 1
fi

PARSE_SCRIPT="${SCRIPT_DIR}/parse-manifest.sh"
if [[ ! -x "$PARSE_SCRIPT" ]]; then
    printf 'ERROR: parse-manifest.sh not found or not executable\n' >&2
    exit 1
fi

# Extract symlink targets from Dockerfile (ln -sfn commands)
# Format: target -> link
extract_dockerfile_symlinks() {
    grep -oE 'ln -sfn [^ ]+ [^ ]+' "$DOCKERFILE" | \
        sed 's/ln -sfn //' | \
        awk '{print $1 " -> " $2}' | \
        sort
}

# Extract expected symlinks from manifest
extract_manifest_symlinks() {
    while IFS='|' read -r source target container_link flags entry_type; do
        # Skip entries without container_link
        [[ -z "$container_link" ]] && continue
        # Skip dynamic pattern entries (G flag)
        [[ "$flags" == *G* ]] && continue

        volume_path="/mnt/agent-data/${target}"
        container_path="/home/agent/${container_link}"
        printf '%s -> %s\n' "$volume_path" "$container_path"
    done < <("$PARSE_SCRIPT" "$MANIFEST_FILE") | sort
}

# Compare
manifest_links=$(extract_manifest_symlinks)
dockerfile_links=$(extract_dockerfile_symlinks)

# Check if a manifest link is covered by a Dockerfile directory symlink
is_covered_by_dir_symlink() {
    local manifest_link="$1"
    local target_path link_path
    target_path="${manifest_link%% -> *}"
    link_path="${manifest_link##* -> }"

    # Check if any Dockerfile link is a parent directory of this link
    while IFS= read -r df_link; do
        local df_target df_link_path
        df_target="${df_link%% -> *}"
        df_link_path="${df_link##* -> }"

        # If Dockerfile links a parent dir, and manifest links a file under it, it's covered
        if [[ "$link_path" == "${df_link_path}/"* && "$target_path" == "${df_target}/"* ]]; then
            return 0
        fi
    done <<< "$dockerfile_links"
    return 1
}

# Find symlinks in manifest but not in Dockerfile
missing_in_dockerfile=()
while IFS= read -r link; do
    if ! grep -qF "$link" <<< "$dockerfile_links"; then
        # Check if covered by a directory symlink
        if ! is_covered_by_dir_symlink "$link"; then
            missing_in_dockerfile+=("$link")
        fi
    fi
done <<< "$manifest_links"

# Find symlinks in Dockerfile but not in manifest
extra_in_dockerfile=()
while IFS= read -r link; do
    if ! grep -qF "$link" <<< "$manifest_links"; then
        extra_in_dockerfile+=("$link")
    fi
done <<< "$dockerfile_links"

errors=0

if [[ ${#missing_in_dockerfile[@]} -gt 0 ]]; then
    printf '\n[WARN] Symlinks in manifest but not in Dockerfile:\n'
    for link in "${missing_in_dockerfile[@]}"; do
        printf '  %s\n' "$link"
    done
    errors=1
fi

if [[ ${#extra_in_dockerfile[@]} -gt 0 ]]; then
    printf '\n[INFO] Symlinks in Dockerfile but not in manifest (may include agent-specific setup):\n'
    for link in "${extra_in_dockerfile[@]}"; do
        printf '  %s\n' "$link"
    done
    # Extra symlinks in Dockerfile are OK (agent-specific setup)
fi

if [[ $errors -eq 0 ]]; then
    printf '[OK] All manifest symlinks are present in Dockerfile\n'
fi

exit $errors
