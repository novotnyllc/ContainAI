# fn-17-axl.7 Absolute-to-relative symlink conversion

## Description

When importing symlinks that point inside $HOME using absolute paths, convert them to relative symlinks in the destination. This makes them mountpoint-agnostic.

**Current behavior:** `import.sh` has `relink_internal_symlinks()` that remaps to `/mnt/agent-data/...` absolute paths, which only works if the volume is mounted at that exact path.

**New behavior:** Convert to relative paths that work regardless of mount location.

## Key Insight: Volume Structure ≠ $HOME Structure

The volume path does NOT mirror $HOME. For example:
- `~/.config/gh` → `/target/config/gh` (not `/target/.config/gh`)
- `~/.claude/settings.json` → `/target/claude/settings.json`

Therefore, symlink target resolution MUST go through the manifest to find the correct destination path.

## Conversion Algorithm

**Input:**
- `LINK_PATH`: Path of the symlink in destination (e.g., `/target/config/nvim`)
- `LINK_TARGET`: Original absolute target read via `readlink` (e.g., `/home/user/dotfiles/nvim`)
- `HOST_SOURCE_ROOT`: The host $HOME that was imported (e.g., `/home/user`)
- `MANIFEST`: The sync manifest mapping source paths to destination paths

**Step 1: Validate target is inside source root**
```bash
case "$LINK_TARGET" in
    "${HOST_SOURCE_ROOT}/"*) ;; # Target is inside $HOME, proceed
    *)
        # Target is outside $HOME - preserve as-is, warn
        echo "[WARN] Symlink target outside HOME, preserving: $LINK_PATH -> $LINK_TARGET"
        return 0
        ;;
esac
```

**Step 2: Look up target in manifest using LONGEST-PREFIX MATCH**

User-specified `additional_paths` can create overlapping entries (e.g., `~/.config` plus `~/.config/gh`). Use longest-prefix match like workspace config resolution.

```bash
# Strip HOST_SOURCE_ROOT prefix to get home-relative path (PRESERVE leading dot)
home_rel_target="${LINK_TARGET#"$HOST_SOURCE_ROOT/"}"
# home_rel_target = "dotfiles/nvim" or ".config/gh" (dot preserved!)

# Search manifest for entry with LONGEST matching prefix
# Manifest entry format: source=/source/.config/gh, target=/target/config/gh
dest_target=""
best_match_len=0

for entry in "${MANIFEST[@]}"; do
    src="${entry%%:*}"          # /source/.config/gh

    # IMPORTANT: Strip only "/source/" prefix, preserve the dot!
    src_rel="${src#/source/}"   # .config/gh (dot preserved!)

    # Check if symlink target starts with this source (or equals it)
    case "$home_rel_target" in
        "${src_rel}"|"${src_rel}/"*)
            # This entry matches - check if it's longer than previous best
            match_len=${#src_rel}
            if [ "$match_len" -gt "$best_match_len" ]; then
                best_match_len=$match_len

                dst="${entry#*:}"
                dst="${dst%%:*}"  # /target/config/gh

                # Compute remainder (if target is inside the entry)
                if [ "$home_rel_target" = "$src_rel" ]; then
                    dest_target="$dst"
                else
                    remainder="${home_rel_target#"$src_rel/"}"
                    dest_target="$dst/$remainder"
                fi
            fi
            ;;
    esac
done

if [ -z "$dest_target" ]; then
    # Target not in imported set - preserve original, warn
    echo "[WARN] Symlink target not in imported set, preserving: $LINK_PATH -> $LINK_TARGET"
    return 0
fi
```

**Step 3: Compute relative path from link to target**
```bash
# LINK_PATH = /target/config/nvim
# dest_target = /target/dotfiles/nvim

# Get directory containing the link
link_dir="${LINK_PATH%/*}"  # /target/config

# Count depth from /target/ to link directory
# Strip /target prefix
link_dir_rel="${link_dir#/target}"  # /config or empty for root

# Count slashes to get depth
if [ -z "$link_dir_rel" ] || [ "$link_dir_rel" = "/" ]; then
    # Root level (e.g., /target/.gitconfig) - depth is 0
    depth=0
else
    # Count path components (slashes + 1, but strip leading /)
    link_dir_rel="${link_dir_rel#/}"  # config
    depth=$(echo "$link_dir_rel" | tr -cd '/' | wc -c)
    depth=$((depth + 1))  # 1 for "config", 2 for "config/foo", etc.
fi

# Build relative prefix (../ repeated depth times)
rel_prefix=""
i=0
while [ $i -lt $depth ]; do
    rel_prefix="../$rel_prefix"
    i=$((i + 1))
done

# Strip /target/ from dest_target to get target-relative path
dest_target_rel="${dest_target#/target/}"

# Final relative target
if [ -z "$rel_prefix" ]; then
    final_target="$dest_target_rel"
else
    final_target="${rel_prefix}${dest_target_rel}"
fi
```

**Step 4: Update symlink**
```bash
ln -sfn "$final_target" "$LINK_PATH"
```

## Edge Cases

1. **Target outside $HOME**: Preserve original absolute symlink, log warning
2. **Target not in manifest/imported set**: Preserve original absolute symlink, log warning (consistent with epic)
3. **Broken symlinks in source**: Skip with warning (readlink returns non-zero)
4. **Symlink chains**: Resolve only one level (don't follow chains), convert that level
5. **Root-level links** (e.g., /target/.gitconfig): depth=0, no `../` prefix needed
6. **Link and target in same directory**: Works correctly (depth accounts for it)
7. **Dotted paths**: `/source/.config/gh` stripped to `.config/gh` (dot preserved)
8. **Overlapping entries**: Longest-prefix match ensures `~/.config/gh` matches `/target/config/gh` not `/target/config`

## Example Walkthrough

**Example 1: Overlapping entries (longest-prefix match)**
```
Manifest entries:
  /source/.config -> /target/config
  /source/.config/gh -> /target/config/gh

Symlink: -> /home/user/.config/gh/hosts.yml
home_rel_target: ".config/gh/hosts.yml"

Match 1: ".config" (len=7) -> /target/config/gh/hosts.yml
Match 2: ".config/gh" (len=10) -> /target/config/gh/hosts.yml (WINNER - longer)

Result: Uses /target/config/gh as base (correct!)
```

**Example 2: Root-level link**
```
Source: ~/.gitconfig -> /home/user/dotfiles/gitconfig
Manifest: /source/dotfiles -> /target/dotfiles
         /source/.gitconfig -> /target/gitconfig

Link: /target/gitconfig
home_rel_target: "dotfiles/gitconfig"
dest_target: /target/dotfiles/gitconfig
Depth: 0 (root level)
Result: dotfiles/gitconfig
```

## Acceptance

- [ ] Algorithm uses manifest lookup (not $HOME path mirroring)
- [ ] **Longest-prefix match used for overlapping entries**
- [ ] Dotted paths preserved correctly (`.config/gh` not `config/gh`)
- [ ] Absolute symlinks inside $HOME with manifest match converted to relative
- [ ] Relative symlinks preserved as-is
- [ ] Symlinks to outside $HOME preserved with warning (consistent with epic)
- [ ] Symlinks to paths not in manifest preserved with warning (consistent with epic)
- [ ] Broken symlinks skipped with warning
- [ ] Root-level links work correctly (depth=0, no ../ prefix)
- [ ] Nested links work correctly (proper ../ count)
- [ ] `cai import --dry-run` shows symlink conversions
- [ ] Converted symlinks work when volume mounted at any path
- [ ] Original source symlinks NOT modified
- [ ] Works with --from <directory> option
- [ ] Test: overlapping entries resolve to longest match

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
