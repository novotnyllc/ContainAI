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
Implemented _cai_build_template() function that builds user's Dockerfile using the same Docker context as container creation. Integrated template build into container creation flow: builds default template, uses resulting image (containai-template-{name}:local), and labels container with ai.containai.template={name}. Dry-run outputs TEMPLATE_BUILD_CMD with proper shell escaping and env var clearing prefix.
## Evidence
- Commits: 160eab0, ee7024b, 373b167
- Tests: SKIP_DOCKER_TESTS=1 ./tests/integration/test-templates.sh
- PRs:
