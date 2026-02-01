# fn-33-lp4.4 Implement template build flow

## Description
Build user's Dockerfile before container creation using same Docker context as container run. Tag as `containai-template-{name}:local`. Store template name as container label `ai.containai.template`.

## Acceptance
- [ ] `_cai_build_template()` function builds template Dockerfile
- [ ] Build uses same Docker context (`$context_args`) as container creation
- [ ] Image tagged as `containai-template-{name}:local`
- [ ] Container labeled with `ai.containai.template={name}`
- [ ] Build errors are propagated with clear messages
- [ ] `--dry-run` outputs `TEMPLATE_BUILD_CMD=<command>` for machine parsing

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
