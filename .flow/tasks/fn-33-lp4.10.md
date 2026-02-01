# fn-33-lp4.10 Update documentation

## Description
Document template system in quickstart and configuration docs. Include systemd symlink examples (not `systemctl enable`).

## Acceptance
- [ ] `docs/quickstart.md` has "Customizing Your Container" section
- [ ] `docs/configuration.md` documents `[template]` section
- [ ] Examples use symlink pattern for systemd services
- [ ] Warning about ENTRYPOINT/CMD/USER in docs
- [ ] `cai doctor fix template` documented in troubleshooting

## Done summary
Added comprehensive template system documentation to quickstart.md and configuration.md, including template directory structure, usage, startup script patterns with systemd symlink examples, and troubleshooting with `cai doctor fix template`.
## Evidence
- Commits: 15dc73dd95b4ed8f75a4cebc9dc02e5da2a6c8d6, 177ea8148502acaf4beeb56a7b4a0c71bbe68a25
- Tests: codex impl-review
- PRs:
