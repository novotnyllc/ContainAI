# fn-42-cli-ux-fixes-hostname-reset-wait-help.1 Add container hostname flag to docker run

## Description
Add RFC 1123 compliant hostname to containers, automatically sanitizing container names to be valid hostnames.

**Size:** M
**Files:** `src/lib/container.sh`

## Approach

The hostname implementation uses `_cai_sanitize_hostname()` to convert container names to valid RFC 1123 hostnames:

1. **Sanitization rules** (implemented in `_cai_sanitize_hostname()` at line 313):
   - Convert to lowercase
   - Replace underscores with hyphens (common in container names but invalid in hostnames)
   - Remove any non-alphanumeric and non-hyphen characters
   - Collapse multiple consecutive hyphens
   - Strip leading/trailing hyphens
   - Truncate to max 63 characters (RFC 1123 limit)
   - Fallback to "container" if sanitization results in empty string

2. **Application** in docker run (at line 2483):
   ```bash
   local container_hostname
   container_hostname=$(_cai_sanitize_hostname "$container_name")
   args+=(--hostname "$container_hostname")
   ```

## Key context

- Hostname sanitization function at `src/lib/container.sh:313-336`
- Applied during container creation at line 2483
- RFC 1123: alphanumeric + hyphens, max 63 chars, no leading/trailing hyphens
- Pattern: `args+=(--hostname "$container_hostname")`
<!-- Updated by plan-sync: fn-42-cli-ux-fixes-hostname-reset-wait-help.10 implemented RFC 1123 sanitization, not the named schemes mentioned in earlier approaches -->
## Acceptance
- [x] `_cai_sanitize_hostname()` function implemented (line 313-336)
- [x] Hostnames are RFC 1123 compliant (lowercase, alphanumeric + hyphens, max 63 chars)
- [x] Underscores converted to hyphens
- [x] Leading/trailing hyphens stripped
- [x] Multiple hyphens collapsed
- [x] Hostname flag added to docker run (line 2483)
- [x] Fallback to "container" if sanitization results in empty string
## Done summary
RFC 1123 hostname sanitization implemented: `_cai_sanitize_hostname()` function converts container names to valid hostnames using lowercase, hyphen conversion, character filtering, and truncation. Applied to docker run with --hostname flag.

## Evidence
- Commits: ebe7b53, 9642ade (from fn-42-cli-ux-fixes-hostname-reset-wait-help.10)
- Tests: shellcheck -x src/lib/container.sh
- PRs:
