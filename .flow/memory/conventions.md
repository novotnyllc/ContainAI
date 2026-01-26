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

## 2026-01-23 manual [convention]
Hot-reload env vars into containers via bashrc.d hook script that sources .env, not one-shot SSH export which doesn't persist

## 2026-01-23 manual [convention]
Reuse existing SSH infrastructure (_cai_ssh_run) for retry logic and host-key recovery instead of reimplementing SSH options

## 2026-01-23 manual [convention]
Documentation must reference actual implementation behavior - run grep/read on source files to verify claims about commands, outputs, and paths

## 2026-01-25 manual [convention]
Write config/version files atomically: write to .tmp then mv -f to prevent truncated files on interruption

## 2026-01-26 manual [convention]
CLI argument validation should be order-independent; use pre-scan pass to determine mode before validating args
