# Decisions

Architectural choices with rationale. Why we chose X over Y.

<!-- Entries added manually via `flowctl memory add` -->

## 2026-01-19 manual [decision]
FR-4 safe defaults: reject dangerous options entirely rather than gating behind acknowledgment flags

## 2026-01-23 manual [decision]
Dockerfile.test: install sysbox for binary only (no services) to satisfy both 'remove redundant installation' and 'inner Docker uses sysbox-runc' requirements
