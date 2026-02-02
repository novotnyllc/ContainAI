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

- [ ] `_CAI_IMAGE_CHANNEL` global declared in config.sh
- [ ] `[image].channel` parsed in `_containai_parse_config` using existing JSON/Python pattern
- [ ] Channel stored in `_CAI_IMAGE_CHANNEL` global after config parsing
- [ ] Valid values: "stable", "nightly" (default: stable)
- [ ] `--channel <value>` CLI flag added to argument parsing
- [ ] CLI flag sets `_CAI_CHANNEL_OVERRIDE` variable
- [ ] `CONTAINAI_CHANNEL` environment variable supported
- [ ] Precedence: CLI > env > config > default
- [ ] Invalid channel value logs warning and falls back to stable
- [ ] `_cai_config_channel()` function returns resolved channel
- [ ] `_cai_base_image()` returns correct image for channel
- [ ] Default template uses `ARG BASE_IMAGE` pattern
- [ ] Template build passes `--build-arg BASE_IMAGE` from `_cai_base_image()`
- [ ] `cai template upgrade` command migrates hardcoded templates
- [ ] Template upgrade works on templates in `~/.config/containai/templates/<name>/`
- [ ] Template upgrade preserves user customizations
- [ ] `cai doctor` warns about hardcoded template base images
- [ ] Channel config affects: image pull prompt, freshness check, refresh command

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
