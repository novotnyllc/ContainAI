# Conventions

Project patterns discovered during work. Not in CLAUDE.md but important.

<!-- Entries added manually via `flowctl memory add` -->

## 2026-01-16 manual [convention]
Use 'command -v' instead of 'which' for portability - which is not a shell builtin and may not exist

## 2026-01-16 manual [convention]
Use consistent ASCII markers [OK], [WARN], [ERROR] for status messages in shell scripts - avoid mixing with colon format (ERROR:)

## 2026-01-19 manual [convention]
Use printf '%s\n' instead of echo for shell logging - echo mis-handles messages starting with -n/-e

## 2026-01-20 manual [convention]
Tests should verify actual behavior (e.g., sentinel values) not just that operations succeed without error

## 2026-01-20 manual [convention]
In bash functions with strict/non-strict modes, apply consistent error handling: strict mode returns 1 with [ERROR], non-strict returns defaults with [WARN]
