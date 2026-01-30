# fn-36-rb7.9 Implement shell completion for cai docker

## Description
Add completion for `cai docker` that delegates to docker completion if available, setting `DOCKER_CONTEXT=containai-docker` and falling back gracefully.

## Acceptance
- [ ] `cai docker <TAB>` completes docker subcommands
- [ ] `cai docker ps <TAB>` works
- [ ] Sets `DOCKER_CONTEXT=containai-docker` before calling docker completion
- [ ] Graceful fallback if docker completion is unavailable
- [ ] Does not filter `--context` or `-u`

## Verification
- [ ] `cai docker <TAB>`
- [ ] `cai docker exec <TAB>` shows container names

## Done summary
# fn-36-rb7.9: Implement shell completion for cai docker

## Summary
Implemented shell completion for `cai docker` subcommand that delegates to docker's native Cobra-style completion with the `containai-docker` context set. Added both bash and zsh completion support with graceful fallback to basic docker subcommands if docker completion is unavailable.

## Changes
- Modified bash completion in `_cai_completion_bash()` to handle the `docker)` case:
  - Delegates to `docker __complete` with `DOCKER_CONTEXT=containai-docker`
  - Falls back to basic docker subcommands list if native completion unavailable
  - Does not filter `--context` or `-u` flags (per spec requirement)

- Added zsh completion case for `docker` in `_cai_completion_zsh()`:
  - Same delegation pattern using `docker __complete`
  - Provides rich fallback with descriptions for each docker subcommand
  - Uses zsh-specific array handling for completions

## Implementation Details
- Uses `DOCKER_CONTEXT` environment variable to set context (not `--context` flag) per docker's Cobra completion mechanism
- Extracts docker subcommand words from completion line to pass to `docker __complete`
- Filters out directive lines (`:N`) from docker's completion output
- Graceful fallback with comprehensive docker subcommand list

## Testing Notes
- Bash syntax validated with `bash -n`
- Shellcheck passes without errors
- Cannot fully test completion in headless environment (requires interactive shell)
## Evidence
- Commits:
- Tests: bash -n src/containai.sh, shellcheck -x src/containai.sh
- PRs:
