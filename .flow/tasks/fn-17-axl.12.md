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
- [ ] Root cause identified and documented
- [ ] If fixable: solution implemented and tested
- [ ] If not fixable: documented as known limitation with workaround
- [ ] Investigation findings added to docs/troubleshooting.md if relevant

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
