# fn-31-gib.11 Prevent home directory pollution

## Description
Implement `o` (optional) flag across all code paths to prevent creating empty directories for agents user doesn't have.

**Root causes to address:**
1. `Dockerfile.agents` pre-creates optional agent dirs (`RUN mkdir -p`)
2. `gen-init-dirs.sh` creates all entries
3. `gen-dockerfile-symlinks.sh` symlinks all entries
4. `gen-container-link-spec.sh` repairs all entries

**Flag behavior matrix:**
| Code path | WITHOUT `o` | WITH `o` |
|-----------|-------------|----------|
| Dockerfile mkdir | Create dir | Skip mkdir |
| Import | Always sync | Only if host source exists |
| gen-init-dirs | Always init | Skip init |
| gen-dockerfile-symlinks | Always symlink | Skip symlink |
| gen-container-link-spec | Always repair | Skip repair |
| cai sync | Process if has container_link | Process if has container_link |

## Acceptance
- [ ] `src/scripts/parse-manifest.sh` parses and exposes `o` flag in output
- [ ] `src/scripts/gen-init-dirs.sh` skips entries with `o` flag
- [ ] `src/scripts/gen-dockerfile-symlinks.sh` skips entries with `o` flag
- [ ] `src/scripts/gen-container-link-spec.sh` skips entries with `o` flag (link repair)
- [ ] `src/container/Dockerfile.agents` no longer pre-creates optional agent dirs
- [ ] `src/lib/import.sh` checks source existence before syncing `o` entries
- [ ] Existing optional agents in `sync-manifest.toml` get `o` flag: Cursor, Aider, Continue, Copilot, Gemini
- [ ] Required dirs do NOT have `o` flag: `.claude`, `.codex` (primary agents that should always be available)
- [ ] Regenerated files reflect changes: `generated/init-dirs.sh`, `generated/symlinks.sh`, `generated/link-spec.json`

## Done summary
Implemented 'o' (optional) flag across all code paths to prevent creating empty directories for agents user doesn't have. Optional agents (Cursor, Aider, Continue, Copilot, Gemini) are skipped in Dockerfile mkdir, init-dirs, symlinks, and link-spec generation. Import now skips optional entries when source doesn't exist. Required agents (Claude, Codex) remain always available.
## Evidence
- Commits: f2c0c45, bf7d3ba
- Tests: ./scripts/check-manifest-consistency.sh, shellcheck
- PRs:
