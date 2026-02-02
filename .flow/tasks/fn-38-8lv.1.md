# fn-38-8lv.1 Create adding-agents.md documentation

## Description

Create the main `docs/adding-agents.md` file based on the template in the epic spec. This is the comprehensive guide for contributors adding new AI agent support to ContainAI.

Key sections to include:
- Overview of the agent addition workflow (6 steps)
- Dockerfile.agents patterns (required vs optional agents, fail-fast vs soft-fail)
- sync-manifest.toml configuration (all fields and flags)
- _IMPORT_SYNC_MAP update workflow with consistency check
- Testing workflow referencing docs/testing.md tiers
- Concrete examples from existing agents (Claude, Codex as required; Gemini, Pi as optional)

## Acceptance

- [ ] `docs/adding-agents.md` file created
- [ ] All 6 steps documented (Research, Dockerfile, Manifest, Import map, Generators, Test)
- [ ] Complete flag reference table (f, d, j, s, o, m, x, R, g, G)
- [ ] Required vs optional agent distinction explained with `o` flag
- [ ] `container_symlinks` and `disabled` fields documented
- [ ] Testing commands explicitly show host vs container context
- [ ] Examples reference actual agents: Claude/Codex (required), Gemini/Pi/Copilot/Kimi (optional)
- [ ] References docs/testing.md for test tier details

## Done summary
Created comprehensive docs/adding-agents.md documentation covering all 6 steps for adding new AI agents to ContainAI: Research, Dockerfile, Manifest, Import map, Generators, and Test. Includes complete flag reference table (f, d, j, s, o, m, x, R, g, G, p), clarified always-sync vs optional-sync agent terminology, documented container_symlinks and disabled fields, and provided examples from Claude/Codex (always-sync) and Gemini/Pi/Copilot/Kimi (optional-sync).
## Evidence
- Commits: 2dd822c, 72459ac, c68f9e4
- Tests: shellcheck -x src/*.sh src/lib/*.sh, ./scripts/check-manifest-consistency.sh
- PRs:
