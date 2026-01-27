# fn-28-5do.1 Remove upstream sysbox fallback - fail if ContainAI unavailable

## Description

Remove the upstream nestybox fallback from `_cai_resolve_sysbox_download_url()` in `src/lib/setup.sh`. The current code has a "Priority 4" fallback to upstream releases if ContainAI fetch fails - this caused the user's system to downgrade from ContainAI sysbox to upstream.

**Size:** S
**Files:** `src/lib/setup.sh`

## Approach

1. Locate the fallback section at `src/lib/setup.sh:755-818` (Priority 4: Fall back to upstream)
2. Remove the entire upstream fallback code block
3. When ContainAI fetch fails, return error with actionable message:
   - Mention CAI_SYSBOX_URL override for direct URL
   - Mention CAI_SYSBOX_VERSION for pinned version
   - Suggest checking GitHub releases page
4. Keep Priority 1 (CAI_SYSBOX_URL override) and Priority 2 (CAI_SYSBOX_VERSION pinned) as escape hatches

## Key context

- `_cai_resolve_sysbox_download_url()` at line 642-820
- Priority 1: `CAI_SYSBOX_URL` explicit override (keep)
- Priority 2: `CAI_SYSBOX_VERSION` pinned version (keep)
- Priority 3: ContainAI GitHub release (primary source)
- Priority 4: Upstream nestybox (REMOVE THIS)

## Acceptance

- [ ] `_cai_resolve_sysbox_download_url` returns error when ContainAI release unavailable
- [ ] Error message provides actionable workarounds (CAI_SYSBOX_URL, CAI_SYSBOX_VERSION)
- [ ] CAI_SYSBOX_URL and CAI_SYSBOX_VERSION overrides still work
- [ ] shellcheck passes on modified file
