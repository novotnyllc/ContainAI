# fn-17-axl.12 Investigate Claude OAuth token expiration on import

## Description

**Priority: Low** - Investigate why Claude's OAuth token expires after import, even though the credentials file is imported correctly.

**Symptoms observed:**
- Claude credentials (`.credentials.json`) are imported to the container
- The token in the file has a valid `expiresAt` timestamp in the future
- Claude CLI still reports the token as expired or invalid
- May require re-authentication inside the container

**Possible causes to investigate:**
1. **Timestamp format mismatch**: Is `expiresAt` in milliseconds vs seconds?
2. **Clock skew**: Is the container's clock significantly different from host?
3. **File permissions**: Is `.credentials.json` readable by the agent user?
4. **Token scope mismatch**: Are the scopes in the imported token correct for Claude Code?
5. **Symlink issues**: If credentials are symlinked, is Claude following the symlink?
6. **Config path differences**: Is Claude looking for credentials in a different location?
7. **Session binding**: Is the token bound to a specific machine/session ID? There may be additional files in ~/.claude we need to import.

**Investigation steps:**
1. Compare `.credentials.json` on host vs container (byte-for-byte)
2. Check file permissions and ownership in container
3. Check container time vs host time (`date` command)
4. Run `claude --version` and check for config path output
5. Check Claude's debug logs for auth errors
6. Test with fresh authentication in container

**Note:** This is investigation only - may not result in a code fix if the issue is inherent to Claude's auth model.

## Acceptance
- [x] Root cause identified and documented
- [ ] If fixable: solution implemented and tested
- [x] If not fixable: documented as known limitation with workaround
- [x] Investigation findings added to docs/troubleshooting.md if relevant

## Investigation Findings

### Root Causes Identified

1. **Refresh Token Rotation**: Claude uses refresh token rotation (RFC 6819 security best practice). When a refresh token is used, it's invalidated and a new one is issued. If host and container both try to use the same refresh token, only one will succeed - the other gets an invalid token error.

2. **Short Token Lifetime**: Access tokens expire within 8-12 hours. The `expiresAt` field in `.credentials.json` is in milliseconds since epoch.

3. **Server-Side Issues**: Anthropic's OAuth infrastructure occasionally has issues (documented in GitHub Issues #18444, #18442, #19078) where valid tokens are rejected.

4. **Multiple Instance Conflicts**: Running Claude CLI on both host and container simultaneously causes token refresh races.

### Investigation of Original Hypotheses

| Hypothesis | Finding |
|------------|---------|
| Timestamp format mismatch | **NOT an issue** - `expiresAt` is correctly in milliseconds |
| Clock skew | **Possible but unlikely** - container uses host kernel time |
| File permissions | **NOT an issue** - import.sh sets 600 permissions correctly |
| Token scope mismatch | **NOT an issue** - scopes are preserved during import |
| Symlink issues | **NOT an issue** - credentials are copied, not symlinked |
| Config path differences | **NOT an issue** - Claude looks in ~/.claude/.credentials.json |
| Session binding | **PARTIAL** - Refresh token rotation effectively binds token to single instance |

### Why This Cannot Be Fully Fixed in ContainAI

OAuth tokens with refresh token rotation are **designed** for single-instance interactive use. The security model intentionally prevents token sharing:

1. Copying credentials creates a race condition on refresh
2. Both host and container cannot use OAuth simultaneously
3. This is an intentional security feature of OAuth 2.0, not a bug

### Workarounds Documented

1. **Re-authenticate inside container** (`claude /login`) - most reliable
2. **Import fresh credentials and use immediately** - works within token lifetime
3. **Use API key instead of OAuth** - recommended for automation/CI
4. **Don't run Claude on host while using container** - avoids refresh conflicts

### Files Added to Sync (Already Complete)

The sync manifest already includes all necessary files:
- `.claude/.credentials.json` (OAuth tokens)
- `.claude/settings.json` and `.claude/settings.local.json` (preferences)
- `.claude.json` (main config with session state)

Note: `statsig/` directory is NOT synced because it contains session-specific analytics that could cause conflicts.

## Done summary
Investigated Claude OAuth token expiration. Root cause: OAuth refresh token rotation prevents credential sharing between host and container (by design). Documented as known limitation with workarounds in docs/troubleshooting.md.

## Evidence
- Commits: (documentation only)
- Tests: N/A (investigation task)
- PRs:
