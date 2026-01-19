# Pitfalls

Lessons learned from NEEDS_WORK feedback. Things models tend to miss.

<!-- Entries added automatically by hooks or manually via `flowctl memory add` -->

## 2026-01-14 manual [pitfall]
ERE grep -E does not support \s for whitespace; use POSIX [[:space:]] instead

## 2026-01-16 manual [pitfall]
In sourced bash scripts, all loop variables (for/while) and read targets must be declared local to prevent shell pollution

## 2026-01-16 manual [pitfall]
BuildKit cache mounts for non-root USER must include uid/gid to avoid permission issues on parent directories

## 2026-01-16 manual [pitfall]
BuildKit cache mounts exclude content from final image layer - do not cache directories needed at runtime

## 2026-01-16 manual [pitfall]
Dynamic ARGs/LABELs (BUILD_DATE, VCS_REF) invalidate layer cache - place them at end of Dockerfile

## 2026-01-16 manual [pitfall]
Shell precedence: 'cmd1 && cmd2 || true' masks cmd1 failures; use 'cmd1 && (cmd2 || true)' to only mask cmd2

## 2026-01-18 manual [pitfall]
ln -sfn to directory paths needs rm -rf first if destination may exist as real directory (ln -sfn creates link INSIDE existing dir)

## 2026-01-19 manual [pitfall]
Git worktrees and submodules use .git file (not directory); use -e test instead of -d for git root detection

## 2026-01-19 manual [pitfall]
With set -e, capturing exit code via var=$(cmd); rc=$? is dead code - use if ! var=$(cmd); then for error handling

## 2026-01-19 manual [pitfall]
Tests checking env var/config precedence must clear external env vars (env -u) to be hermetic

## 2026-01-19 manual [pitfall]
grep -v with empty input fails under set -euo pipefail; use sed -e '/pattern/d' instead for filter pipelines

## 2026-01-19 manual [pitfall]
Functions returning non-zero for valid control flow (not just errors) need if/else guards for set -e: if func; then rc=0; else rc=$?; fi

## 2026-01-19 manual [pitfall]
Bash read command returns non-zero on EOF; guard with 'if ! read -r var; then' for set -e safety

## 2026-01-19 manual [pitfall]
base64 -w0 is not portable (BSD/macOS lacks -w flag); use 'base64 | tr -d \n' for cross-platform encoding

## 2026-01-19 manual [pitfall]
BASH_SOURCE check must come AFTER BASH_VERSION check - BASH_SOURCE is bash-only and fails in sh/dash

## 2026-01-19 manual [pitfall]
Use 'cd -- "$path"' not 'cd "$path"' - paths starting with - can be misinterpreted as cd options
