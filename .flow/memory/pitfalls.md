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
