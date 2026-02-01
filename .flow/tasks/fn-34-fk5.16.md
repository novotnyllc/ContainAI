# fn-34-fk5.16: Add --reset flag to cai run (from fn-19-qni)

**STATUS: ALREADY IMPLEMENTED**

The `--reset` flag is already implemented in `src/containai.sh`.
It generates a new unique volume name (safer than deleting volumes).
See lines 2806, 2949-2964, 3173-3200, 3295-3392.

## Done summary
# Task fn-34-fk5.16: Add --reset flag to cai run

## Summary

This task is a duplicate - the `--reset` flag was already fully implemented.

## Evidence
- Commits:
- Tests:
- PRs:
## Verification

`grep --reset src/containai.sh` returns 24 matches confirming full implementation.
