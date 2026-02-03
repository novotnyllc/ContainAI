# fn-49-devcontainer-integration.2 Create ContainAI devcontainer feature

## Description

Create the ContainAI devcontainer feature that provides sysbox verification, symlink creation (with credential opt-in), SSH service, and DinD support.

### Feature Structure

```
src/devcontainer/feature/
├── devcontainer-feature.json
├── install.sh
├── verify-sysbox.sh
├── init.sh
├── start.sh
└── link-spec.json        # Copied from container/generated/
```

### Platform Support
**V1: Debian/Ubuntu only**. Clear error message on other distros (Alpine, Fedora, etc.).

### devcontainer-feature.json Options

- `dataVolume`: Name of cai data volume (default: `sandbox-agent-data`)
- `enableCredentials`: Sync credential files - GH tokens, Claude API keys (default: `false` - SECURITY)
- `enableSsh`: Run sshd for non-VS Code access (default: true)
- `installDocker`: Install Docker for DinD (default: true)
- `remoteUser`: User for symlinks (default: auto-detect vscode/node/root)

### Security: Credential Opt-In

**Credentials are NOT synced by default.** Files containing tokens/API keys are skipped unless `enableCredentials: true`:
- `~/.config/gh/hosts.yml` (GitHub token)
- `~/.claude/credentials.json` (Claude API key)
- `~/.codex/config.toml` (may contain keys)
- `~/.gemini/settings.json` (may contain keys)

This prevents untrusted code in the workspace from accessing credentials.

### Scripts

1. **install.sh** (build-time)
   - Check for apt-get (Debian/Ubuntu only)
   - Install jq for JSON parsing
   - Store config to `/usr/local/share/containai/config`
   - Create verify-sysbox.sh, init.sh, start.sh
   - Install openssh-server if enableSsh
   - Install Docker if installDocker (add user to docker group)
   - Copy link-spec.json to `/usr/local/lib/containai/`

2. **verify-sysbox.sh**
   - **MANDATORY**: Sysboxfs mount check (sysbox-unique, unforgeable)
   - UID map check (0 not mapped to 0)
   - Nested userns test (unshare --user)
   - CAP_SYS_ADMIN capability probe
   - Require sysboxfs + 2 other checks to pass

3. **init.sh** (postCreateCommand)
   - Run sysbox verification
   - Read symlinks from `/usr/local/lib/containai/link-spec.json` (no hardcoded lists)
   - **Rewrite paths**: link-spec.json uses `/home/agent` paths; rewrite to detected user home (`/home/vscode`, `/home/node`, etc.)
   - **Handle remove_first**: Implement `remove_first` semantics - `rm -rf` for directories before creating symlink
   - Skip credential files unless `enableCredentials=true`
   - Create symlinks using jq to parse link-spec.json

4. **start.sh** (postStartCommand)
   - Re-verify sysbox
   - Start sshd if enabled (with idempotency check)
   - Start dockerd for DinD (with retry/idempotency)

### Symlinks from link-spec.json

Uses the canonical `link-spec.json` generated from `sync-manifest.toml`. No duplicate symlink lists in this feature.

The init.sh script reads link-spec.json and creates symlinks, skipping credential files when `enableCredentials=false`.

## Acceptance

- [ ] Feature installs on Debian/Ubuntu base images
- [ ] Clear error on non-Debian distros (Alpine, Fedora, etc.)
- [ ] Sysbox verification requires sysboxfs mount (mandatory)
- [ ] Verification passes in sysbox, fails in regular docker
- [ ] Credentials NOT synced by default
- [ ] Credentials synced when `enableCredentials: true`
- [ ] Symlinks read from link-spec.json (no duplicate lists)
- [ ] **Link paths rewritten** from `/home/agent` to detected user home
- [ ] **remove_first handled** for directories (rm -rf before ln -sfn)
- [ ] SSH port read from `CONTAINAI_SSH_PORT` env var
- [ ] SSH starts with idempotency (doesn't fail if already running)
- [ ] Dockerd starts with retry and idempotency
- [ ] Hard-fail with clear error message when not in sysbox

## Done summary
Blocked:
Auto-blocked after 5 attempts.
Run: 20260203T013526Z-containai-containai-main-claire@novotny.org-23727-267d
Task: fn-49-devcontainer-integration.2

Last output:
{"type":"system","subtype":"init","cwd":"/home/agent/workspace","session_id":"b372108d-4ffc-4498-a575-bafef4a0b6cc","tools":["Task","TaskOutput","Bash","Glob","Grep","ExitPlanMode","Read","Edit","Write","NotebookEdit","WebFetch","TodoWrite","WebSearch","TaskStop","AskUserQuestion","Skill","EnterPlanMode","ToolSearch","mcp__fetch__fetch","mcp__sequential-thinking__sequentialthinking","mcp__context7__resolve-library-id","mcp__context7__query-docs"],"mcp_servers":[{"name":"fetch","status":"connected"},{"name":"sequential-thinking","status":"connected"},{"name":"context7","status":"connected"}],"model":"claude-opus-4-5-20251101","permissionMode":"bypassPermissions","slash_commands":["keybindings-help","flow-next:flow-next:ralph-init","flow-next:flow-next:uninstall","flow-next:flow-next:sync","flow-next:flow-next:prime","flow-next:flow-next:work","flow-next:flow-next:setup","flow-next:flow-next:epic-review","flow-next:flow-next:impl-review","flow-next:flow-next:plan","flow-next:flow-next:interview","flow-next:flow-next:plan-review","agent-orchestration:improve-agent","agent-orchestration:multi-agent-optimize","python-development:python-scaffold","javascript-typescript:typescript-scaffold","backend-development:feature-development","full-stack-orchestration:full-stack-feature","code-documentation:code-explain","code-documentation:doc-generate","debugging-toolkit:smart-debug","documentation-generation:doc-generate","c4-architecture:c4-architecture","code-refactoring:tech-debt","code-refactoring:refactor-clean","code-refactoring:context-restore","dependency-management:deps-audit","error-debugging:error-analysis","error-debugging:error-trace","error-debugging:multi-agent-review","llm-application-dev:langchain-agent","llm-application-dev:ai-assistant","llm-application-dev:prompt-optimize","context-management:context-save","context-management:context-restore","observability-monitoring:monitor-setup","observability-monitoring:slo-implement","distributed-debugging:debug-trace","deployment-validation:config-validate","cicd-automation:workflow-automate","frontend-mobile-security:xss-scan","codebase-cleanup:tech-debt","codebase-cleanup:refactor-clean","codebase-cleanup:deps-audit","systems-programming:rust-project","flow-next:flow-next-plan-review","flow-next:flow-next","flow-next:browser","flow-next:flow-next-impl-review","flow-next:flow-next-plan","flow-next:flow-next-sync","flow-next:flow-next-epic-review","flow-next:flow-next-rp-explorer","flow-next:flow-next-setup","flow-next:flow-next-interview","flow-next:flow-next-prime","flow-next:flow-next-work","flow-next:flow-next-worktree-kit","flow-next:flow-next-export-context","flow-next:flow-next-deps","flow-next:flow-next-ralph-init","python-development:async-python-patterns","python-development:python-performance-optimization","python-development:python-testing-patterns","python-development:uv-package-manager","python-development:python-packaging","javascript-typescript:modern-javascript-patterns","javascript-typescript:nodejs-backend-patterns","javascript-typescript:typescript-advanced-types","javascript-typescript:javascript-testing-patterns","backend-development:api-design-principles","backend-development:saga-orchestration","backend-development:workflow-orchestration-patterns","backend-development:event-store-design","backend-development:projection-patterns","backend-development:microservices-patterns","backend-development:architecture-patterns","backend-development:temporal-python-testing","backend-development:cqrs-implementation","documentation-generation:openapi-spec-generation","documentation-generation:architecture-decision-records","documentation-generation:changelog-automation","llm-application-dev:prompt-engineering-patterns","llm-application-dev:llm-evaluation","llm-application-dev:embedding-strategies","llm-application-dev:hybrid-search-implementation","llm-application-dev:langchain-architecture","llm-application-dev:rag-implementation","llm-application-dev:vector-index-tuning","llm-application-dev:similarity-search-patterns","observability-monitoring:distributed-tracing","observability-monitoring:grafana-dashboards","observability-monitoring:prometheus-configuration","observability-monitoring:slo-implementation","cicd-automation:gitlab-ci-patterns","cicd-automation:secrets-management","cicd-automation:deployment-pipeline-design","cicd-automation:github-actions-templates","business-analytics:kpi-dashboard-design","business-analytics:data-storytelling","systems-programming:rust-async-patterns","systems-programming:memory-safety-patterns","systems-programming:go-concurrency-patterns","quantitative-trading:risk-metrics-calculation","quantitative-trading:backtesting-frameworks","payment-processing:pci-compliance","payment-processing:stripe-integration","payment-processing:billing-automation","payment-processing:paypal-integration","playground:playground","compact","context","cost","init","pr-comments","release-notes","review","security-review","mcp__fetch__fetch"],"apiKeySource":"none","claude_code_version":"2.1.29","output_style":"default","agents":["Bash","general-purpose","statusline-setup","Explore","Plan","flow-next:repo-scout","flow-next:env-scout","flow-next:memory-scout","flow-next:security-scout","flow-next:build-scout","flow-next:observability-scout","flow-next:workflow-scout","flow-next:testing-scout","flow-next:epic-scout","flow-next:quality-auditor","flow-next:claude-md-scout","flow-next:docs-scout","flow-next:plan-sync","flow-next:github-scout","flow-next:flow-gap-analyst","flow-next:docs-gap-scout","flow-next:context-scout","flow-next:practice-scout","flow-next:tooling-scout","flow-next:worker","agent-orchestration:context-manager","python-development:fastapi-pro","python-development:python-pro","python-development:django-pro","javascript-typescript:typescript-pro","javascript-typescript:javascript-pro","backend-development:temporal-python-pro","backend-development:graphql-architect","backend-development:tdd-orchestrator","backend-development:event-sourcing-architect","backend-development:backend-architect","full-stack-orchestration:deployment-engineer","full-stack-orchestration:test-automator","full-stack-orchestration:performance-engineer","full-stack-orchestration:security-auditor","code-documentation:tutorial-engineer","code-documentation:docs-architect","code-documentation:code-reviewer","debugging-toolkit:debugger","debugging-toolkit:dx-optimizer","documentation-generation:mermaid-expert","documentation-generation:reference-builder","documentation-generation:tutorial-engineer","documentation-generation:docs-architect","documentation-generation:api-documenter","c4-architecture:c4-component","c4-architecture:c4-container","c4-architecture:c4-code","c4-architecture:c4-context","code-refactoring:legacy-modernizer","code-refactoring:code-reviewer","dependency-management:legacy-modernizer","error-debugging:debugger","error-debugging:error-detective","llm-application-dev:vector-database-engineer","llm-application-dev:ai-engineer","llm-application-dev:prompt-engineer","context-management:context-manager","observability-monitoring:network-engineer","observability-monitoring:performance-engineer","observability-monitoring:database-optimizer","observability-monitoring:observability-engineer","distributed-debugging:error-detective","distributed-debugging:devops-troubleshooter","deployment-strategies:deployment-engineer","deployment-strategies:terraform-specialist","deployment-validation:cloud-architect","cicd-automation:deployment-engineer","cicd-automation:terraform-specialist","cicd-automation:cloud-architect","cicd-automation:kubernetes-architect","cicd-automation:devops-troubleshooter","backend-api-security:backend-architect","backend-api-security:backend-security-coder","frontend-mobile-security:frontend-developer","frontend-mobile-security:frontend-security-coder","frontend-mobile-security:mobile-security-coder","codebase-cleanup:test-automator","codebase-cleanup:code-reviewer","business-analytics:business-analyst","jvm-languages:java-pro","jvm-languages:scala-pro","jvm-languages:csharp-pro","systems-programming:cpp-pro","systems-programming:golang-pro","systems-programming:rust-pro","systems-programming:c-pro","quantitative-trading:quant-analyst","quantitative-trading:risk-manager","payment-processing:payment-integration"],"skills":["keybindings-help","flow-next:flow-next-plan-review","flow-next:flow-next","flow-next:browser","flow-next:flow-next-impl-review","flow-next:flow-next-plan","flow-next:flow-next-sync","flow-next:flow-next-epic-review","flow-next:flow-next-rp-explorer","flow-next:flow-next-setup","flow-next:flow-next-interview","flow-next:flow-next-prime","flow-next:flow-next-work","flow-next:flow-next-worktree-kit","flow-next:flow-next-export-context","flow-next:flow-next-deps","flow-next:flow-next-ralph-init","python-development:async-python-patterns","python-development:python-performance-optimization","python-development:python-testing-patterns","python-development:uv-package-manager","python-development:python-packaging","javascript-typescript:modern-javascript-patterns","javascript-typescript:nodejs-backend-patterns","javascript-typescript:typescript-advanced-types","javascript-typescript:javascript-testing-patterns","backend-development:api-design-principles","backend-development:saga-orchestration","backend-development:workflow-orchestration-patterns","backend-development:event-store-design","backend-development:projection-patterns","backend-development:microservices-patterns","backend-development:architecture-patterns","backend-development:temporal-python-testing","backend-development:cqrs-implementation","documentation-generation:openapi-spec-generation","documentation-generation:architecture-decision-records","documentation-generation:changelog-automation","llm-application-dev:prompt-engineering-patterns","llm-application-dev:llm-evaluation","llm-application-dev:embedding-strategies","llm-application-dev:hybrid-search-implementation","llm-application-dev:langchain-architecture","llm-application-dev:rag-implementation","llm-application-dev:vector-index-tuning","llm-application-dev:similarity-search-patterns","observability-monitoring:distributed-tracing","observability-monitoring:grafana-dashboards","observability-monitoring:prometheus-configuration","observability-monitoring:slo-implementation","cicd-automation:gitlab-ci-patterns","cicd-automation:secrets-management","cicd-automation:deployment-pipeline-design","cicd-automation:github-actions-templates","business-analytics:kpi-dashboard-design","business-analytics:data-storytelling","systems-programming:rust-async-patterns","systems-programming:memory-safety-patterns","systems-programming:go-concurrency-patterns","quantitative-trading:risk-metrics-calculation","quantitative-trading:backtesting-frameworks","payment-processing:pci-compliance","payment-processing:stripe-integration","payment-processing:billing-automation","payment-processing:paypal-integration","playground:playground"],"plugins":[{"name":"flow-next","path":"/home/agent/.claude/plugins/cache/gmickel-claude-marketplace/flow-next/0.20.8"},{"name":"gopls-lsp","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/gopls-lsp/1.0.0"},{"name":"csharp-lsp","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/csharp-lsp/1.0.0"},{"name":"rust-analyzer-lsp","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/rust-analyzer-lsp/1.0.0"},{"name":"clangd-lsp","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/clangd-lsp/1.0.0"},{"name":"pyright-lsp","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/pyright-lsp/1.0.0"},{"name":"agent-orchestration","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/agent-orchestration/1.2.0"},{"name":"python-development","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/python-development/1.2.1"},{"name":"javascript-typescript","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/javascript-typescript/1.2.1"},{"name":"backend-development","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/backend-development/1.2.4"},{"name":"full-stack-orchestration","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/full-stack-orchestration/1.2.1"},{"name":"code-documentation","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/code-documentation/1.2.0"},{"name":"debugging-toolkit","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/debugging-toolkit/1.2.0"},{"name":"documentation-generation","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/documentation-generation/1.2.1"},{"name":"c4-architecture","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/c4-architecture/1.0.0"},{"name":"code-refactoring","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/code-refactoring/1.2.0"},{"name":"dependency-management","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/dependency-management/1.2.0"},{"name":"error-debugging","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/error-debugging/1.2.0"},{"name":"llm-application-dev","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/llm-application-dev/2.0.2"},{"name":"context-management","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/context-management/1.2.0"},{"name":"observability-monitoring","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/observability-monitoring/1.2.1"},{"name":"distributed-debugging","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/distributed-debugging/1.2.0"},{"name":"deployment-strategies","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/deployment-strategies/1.2.0"},{"name":"deployment-validation","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/deployment-validation/1.2.0"},{"name":"cicd-automation","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/cicd-automation/1.2.1"},{"name":"backend-api-security","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/backend-api-security/1.2.0"},{"name":"frontend-mobile-security","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/frontend-mobile-security/1.2.0"},{"name":"codebase-cleanup","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/codebase-cleanup/1.2.0"},{"name":"business-analytics","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/business-analytics/1.2.1"},{"name":"jvm-languages","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/jvm-languages/1.2.0"},{"name":"systems-programming","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/systems-programming/1.2.1"},{"name":"quantitative-trading","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/quantitative-trading/1.2.1"},{"name":"payment-processing","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/payment-processing/1.2.1"},{"name":"playground","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/playground/27d2b86d72da"}],"uuid":"7ffae30f-cd0b-4042-b811-9ad72a054fa7"}
{"type":"assistant","message":{"id":"bc03dc77-96d7-4c98-a6ac-658df3f33394","container":null,"model":"<synthetic>","role":"assistant","stop_reason":"stop_sequence","stop_sequence":"","type":"message","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":null,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}},"content":[{"type":"text","text":"API Error: 500 {\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"Internal server error\"},\"request_id\":\"req_011CXmP4N8R9NhWvvUpnaacp\"}"}],"context_management":null},"parent_tool_use_id":null,"session_id":"b372108d-4ffc-4498-a575-bafef4a0b6cc","uuid":"59f9541b-6503-4d95-85fb-66acfeb2b4c1","error":"unknown"}
{"type":"result","subtype":"success","is_error":true,"duration_ms":379,"duration_api_ms":0,"num_turns":1,"result":"API Error: 500 {\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"Internal server error\"},\"request_id\":\"req_011CXmP4N8R9NhWvvUpnaacp\"}","session_id":"b372108d-4ffc-4498-a575-bafef4a0b6cc","total_cost_usd":0,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}},"modelUsage":{},"permission_denials":[],"uuid":"b33770a9-b432-4694-b5d6-c418e735b34e"}
ralph: task not done; forcing retry
## Evidence
- Commits:
- Tests:
- PRs:
