# fn-32-2mq.8 Add channel configuration

## Description

Add release channel configuration option with CLI flag override and integrate with template system for channel-aware base images.

**Config Option (using existing config system):**
```toml
# ~/.config/containai/config.toml (or workspace override)
[image]
channel = "stable"  # or "nightly"
```

**Channel Selection Precedence:**
1. CLI flag: `--channel nightly` (highest priority)
2. Environment: `CONTAINAI_CHANNEL=nightly`
3. Config file: `[image].channel`
4. Default: `stable`

**Integration with Existing Config:**

Update `src/lib/config.sh` to parse channel in `_containai_parse_config`. Follow the existing pattern used for other config values:

1. Add global variable declaration at top of file:
```bash
_CAI_IMAGE_CHANNEL=""
```

2. Add channel extraction in `_containai_parse_config` (after other config extraction):
```bash
# Extract image.channel from config JSON (same pattern as other config values)
local channel_val=""
channel_val=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
print(config.get('image', {}).get('channel', ''))
")
_CAI_IMAGE_CHANNEL="$channel_val"
```

3. Add helper function to resolve final channel with precedence:
```bash
_cai_config_channel() {
  # Check CLI flag first (set by main.sh arg parsing)
  if [[ -n "${_CAI_CHANNEL_OVERRIDE:-}" ]]; then
    echo "$_CAI_CHANNEL_OVERRIDE"
    return
  fi

  # Check environment
  if [[ -n "${CONTAINAI_CHANNEL:-}" ]]; then
    echo "$CONTAINAI_CHANNEL"
    return
  fi

  # Use parsed config global
  local channel="${_CAI_IMAGE_CHANNEL:-stable}"

  # Validate
  case "$channel" in
    stable|nightly) echo "$channel" ;;
    *)
      _cai_warn "Invalid channel '$channel', using stable"
      echo "stable"
      ;;
  esac
}
```

**Base Image Resolution:**
```bash
_cai_base_image() {
  local channel
  channel="$(_cai_config_channel)"
  case "$channel" in
    nightly) echo "ghcr.io/novotnyllc/containai:nightly" ;;
    *)       echo "ghcr.io/novotnyllc/containai:latest" ;;
  esac
}
```

**CLI Flag Parsing:**
Add `--channel <value>` to main argument parsing in `src/containai.sh`:
```bash
--channel)
  _CAI_CHANNEL_OVERRIDE="$2"
  shift 2
  ;;
```

**Template Integration:**
1. Update `src/templates/default.Dockerfile`:
```dockerfile
ARG BASE_IMAGE=ghcr.io/novotnyllc/containai:latest
FROM ${BASE_IMAGE}
```

2. Update `_cai_build_template` to pass channel-aware base:
```bash
docker build --build-arg BASE_IMAGE="$(_cai_base_image)" ...
```

**Template Upgrade Command:**
Add `cai template upgrade` to migrate existing templates:
1. Read current template Dockerfile from `~/.config/containai/templates/<name>/`
2. Check if FROM uses hardcoded image (no ARG)
3. Rewrite to use ARG pattern
4. Preserve any user customizations below FROM

**Doctor Check:**
Add to `cai doctor`:
```
[WARN] Template uses hardcoded base image.
       Run 'cai template upgrade' to enable channel selection.
```

## Acceptance

- [x] `_CAI_IMAGE_CHANNEL` global declared in config.sh
- [x] `[image].channel` parsed in `_containai_parse_config` using existing JSON/Python pattern
- [x] Channel stored in `_CAI_IMAGE_CHANNEL` global after config parsing
- [x] Valid values: "stable", "nightly" (default: stable)
- [x] `--channel <value>` CLI flag added to argument parsing
- [x] CLI flag sets `_CAI_CHANNEL_OVERRIDE` variable
- [x] `CONTAINAI_CHANNEL` environment variable supported
- [x] Precedence: CLI > env > config > default
- [x] Invalid channel value logs warning and falls back to stable
- [x] `_cai_config_channel()` function returns resolved channel
- [x] `_cai_base_image()` returns correct image for channel
- [x] Default template uses `ARG BASE_IMAGE` pattern
- [x] Template build passes `--build-arg BASE_IMAGE` from `_cai_base_image()`
- [x] `cai template upgrade` command migrates hardcoded templates
- [x] Template upgrade works on templates in `~/.config/containai/templates/<name>/`
- [x] Template upgrade preserves user customizations
- [x] `cai doctor` warns about hardcoded template base images
- [x] Channel config affects: image pull prompt, freshness check, refresh command

## Done summary
# fn-32-2mq.8 Add channel configuration - Done Summary

## Implementation Summary

Added release channel configuration (`stable`/`nightly`) with full precedence chain and template integration.

### Config Layer (config.sh)
- `_CAI_IMAGE_CHANNEL` global variable at line 76
- `[image].channel` parsing in `_containai_parse_config()` (lines 545-557)
- `_cai_config_channel()` helper function with precedence: CLI > env > config > default
- Validation with warning on invalid values, stable fallback

### CLI Layer (containai.sh)
- `--channel <value>` flag for run/shell/exec commands
- Sets `_CAI_CHANNEL_OVERRIDE` global for precedence override
- Shell completion for `--channel` (completes `stable` and `nightly`)
- Updated help messages for all relevant commands

### Template Layer (template.sh)
- default.Dockerfile uses `ARG BASE_IMAGE=ghcr.io/novotnyllc/containai:latest`
- `_cai_build_template()` passes `--build-arg BASE_IMAGE="$(_cai_base_image)"`
- `cai template upgrade` command with subcommand handler
- `_cai_template_needs_upgrade()` detects hardcoded FROM lines
- `_cai_template_upgrade_file()` rewrites individual templates

### Doctor Integration (doctor.sh)
- Channel support check in text output (`[OK] Uses ARG BASE_IMAGE` or `[WARN] Hardcoded base image`)
- `channel_support` field in JSON output
- Warns users to run `cai template upgrade` when templates use hardcoded base

### Registry/Update Integration
- `_cai_base_image()` in registry.sh calls `_cai_config_channel()` for precedence
- Freshness check in container.sh uses `_cai_base_image()`
- Refresh command in update.sh uses `_cai_base_image()`

## Verification
- All bash syntax checks pass
- shellcheck passes on modified files
- All acceptance criteria satisfied
## Implementation Summary

Added release channel configuration (`stable`/`nightly`) with full precedence chain and template integration:

### Config Layer (config.sh)
- Added `_CAI_IMAGE_CHANNEL` global variable declaration
- Added `[image].channel` parsing in `_containai_parse_config()` using Python/JSON pattern
- Added `_cai_config_channel()` helper function with precedence: CLI > env > config > default
- Channel validation with warning on invalid values and stable fallback

### CLI Layer (containai.sh)
- Added `--channel <value>` flag to run/shell/exec commands
- Sets `_CAI_CHANNEL_OVERRIDE` global for precedence override
- Updated help messages for all relevant commands
- Added shell completion for `--channel` (completes `stable` and `nightly`)

### Template Layer (template.sh)
- Updated default.Dockerfile to use `ARG BASE_IMAGE=ghcr.io/novotnyllc/containai:latest`
- Modified `_cai_build_template()` to pass `--build-arg BASE_IMAGE="$(_cai_base_image)"`
- Added `cai template upgrade` command with subcommand handler
- Added `_cai_template_needs_upgrade()` to detect hardcoded FROM lines
- Added `_cai_template_upgrade_file()` to rewrite individual templates
- Added `_cai_template_upgrade()` for batch/individual template upgrades

### Doctor Integration (doctor.sh)
- Added channel support check in text output (`[OK] Uses ARG BASE_IMAGE` or `[WARN] Hardcoded base image`)
- Added `channel_support` field to JSON output
- Warns users to run `cai template upgrade` when templates use hardcoded base

### Integration Points
- `_cai_ensure_base_image()` uses channel-aware `_cai_base_image()`
- Freshness check in container.sh uses `_cai_base_image()`
- Refresh command in update.sh uses `_cai_base_image()`

## Files Modified
- `src/lib/config.sh` - Global vars, parsing, `_cai_config_channel()` function
- `src/lib/template.sh` - Template upgrade functions, build-arg integration
- `src/lib/doctor.sh` - Channel support checks in text/JSON output
- `src/containai.sh` - CLI flag parsing, help, completions, template subcommand
- `src/templates/default.Dockerfile` - ARG BASE_IMAGE pattern

## Verification
- All bash syntax checks pass
- shellcheck passes on modified files

## Code Review Fixes (codex impl-review)
The following issues from code review have been addressed:

### Major Issues Fixed
1. **`_cai_config_channel()` dead code** - Fixed `_cai_base_image()` in registry.sh to call `_cai_config_channel()` for precedence and validation
2. **Invalid channel silently dropped** - Config parsing now stores raw value; validation with warnings happens in `_cai_config_channel()`
3. **`_CAI_CHANNEL_OVERRIDE` not reset** - Added reset at top of `containai()` function to prevent leaking between invocations
4. **Template upgrade detection too loose** - Fixed `_cai_template_needs_upgrade()` to return 1 (not needs upgrade) when FROM already uses `$BASE_IMAGE`
5. **Self-referential BASE_IMAGE edge case** - Fixed `_cai_template_upgrade_file()` to detect variable images and default to ContainAI latest

## Evidence
- Commits:
- Tests:
- PRs:
