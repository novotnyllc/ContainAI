# fn-49-devcontainer-integration.3 Build VS Code extension (vscode-containai)

## Description

Create VS Code extension that detects ContainAI features in devcontainer.json and sets `dockerPath` to the cai-docker wrapper.

### Extension Structure

```
vscode-containai/
├── package.json
├── src/
│   ├── extension.ts
│   └── jsonc-parser.ts    # Proper JSONC parsing
├── tsconfig.json
└── README.md
```

### JSONC Parsing Requirement

**Must use proper JSONC parser** (not regex stripping). Use one of:
- `jsonc-parser` npm package (Microsoft's official JSONC parser)
- VS Code's built-in JSONC support

Regex-based comment stripping fails on:
- Comment-like sequences in strings: `"url": "https://example.com"`
- Multiline block comments
- Escaped quotes in strings

### Extension Logic

1. **Activation**: On workspace containing devcontainer.json
2. **Detection**: Parse devcontainer.json using proper JSONC parser for `containai` marker
3. **Configuration**: Set `dev.containers.dockerPath` to cai-docker path
4. **Notification**: Show info message that container will use sysbox
5. **Warning**: If cai-docker not found, show installation instructions

### Key Functions

- `findDevcontainerJson()` - locate devcontainer.json in workspace (handle multi-root, nested folders)
- `parseDevcontainerJson()` - parse JSONC using proper parser
- `hasContainAIFeature()` - check for containai in parsed features object
- `findCaiDocker()` - find cai-docker wrapper path
- `configureDockerPath()` - set dev.containers.dockerPath

### Implementation

```typescript
import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import { parse as parseJSONC } from 'jsonc-parser';  // Proper JSONC parser

export function activate(context: vscode.ExtensionContext) {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) return;

    const devcontainerPath = findDevcontainerJson(workspaceFolder.uri.fsPath);
    if (!devcontainerPath) return;

    if (hasContainAIFeature(devcontainerPath)) {
        const caiDockerPath = findCaiDocker();
        if (caiDockerPath) {
            vscode.workspace.getConfiguration('dev.containers').update(
                'dockerPath',
                caiDockerPath,
                vscode.ConfigurationTarget.Workspace
            );
            vscode.window.showInformationMessage(
                'ContainAI: Devcontainer will run in sysbox sandbox.'
            );
        } else {
            vscode.window.showWarningMessage(
                'ContainAI feature detected but cai not installed. ' +
                'Run: curl -fsSL https://containai.dev/install | sh'
            );
        }
    }
}

function hasContainAIFeature(devcontainerPath: string): boolean {
    const content = fs.readFileSync(devcontainerPath, 'utf8');
    // Use proper JSONC parser - handles comments correctly
    const parsed = parseJSONC(content);
    const features = parsed?.features || {};
    return Object.keys(features).some(key => key.includes('containai'));
}

function findCaiDocker(): string | null {
    const candidates = [
        path.join(process.env.HOME || '', '.local/bin/cai-docker'),
        '/usr/local/bin/cai-docker'
    ];
    return candidates.find(p => fs.existsSync(p)) || null;
}
```

### Distribution

- VS Code Marketplace (marketplace.visualstudio.com)
- Open VSX (open-vsx.org)
- Bundled with cai setup

## Acceptance

- [ ] Activates when devcontainer.json present
- [ ] **Uses proper JSONC parser** (jsonc-parser package, not regex)
- [ ] Detects ContainAI feature in parsed devcontainer.json
- [ ] Sets dockerPath to cai-docker when detected
- [ ] Shows info message about sysbox sandboxing
- [ ] Shows warning when cai not installed
- [ ] Handles multi-root workspaces
- [ ] Works on Windows (WSL), Mac, Linux

## Done summary
Blocked:
Auto-blocked after 5 attempts.
Run: 20260203T013526Z-containai-containai-main-claire@novotny.org-23727-267d
Task: fn-49-devcontainer-integration.3

Last output:
{"type":"system","subtype":"init","cwd":"/home/agent/workspace","session_id":"bacf2df7-93a7-4ac4-b2ec-868b2caebcbb","tools":["Task","TaskOutput","Bash","Glob","Grep","ExitPlanMode","Read","Edit","Write","NotebookEdit","WebFetch","TodoWrite","WebSearch","TaskStop","AskUserQuestion","Skill","EnterPlanMode","ToolSearch","mcp__fetch__fetch","mcp__sequential-thinking__sequentialthinking","mcp__context7__resolve-library-id","mcp__context7__query-docs"],"mcp_servers":[{"name":"fetch","status":"connected"},{"name":"sequential-thinking","status":"connected"},{"name":"context7","status":"connected"}],"model":"claude-opus-4-5-20251101","permissionMode":"bypassPermissions","slash_commands":["keybindings-help","flow-next:flow-next:ralph-init","flow-next:flow-next:uninstall","flow-next:flow-next:sync","flow-next:flow-next:prime","flow-next:flow-next:work","flow-next:flow-next:setup","flow-next:flow-next:epic-review","flow-next:flow-next:impl-review","flow-next:flow-next:plan","flow-next:flow-next:interview","flow-next:flow-next:plan-review","agent-orchestration:improve-agent","agent-orchestration:multi-agent-optimize","python-development:python-scaffold","javascript-typescript:typescript-scaffold","backend-development:feature-development","full-stack-orchestration:full-stack-feature","code-documentation:code-explain","code-documentation:doc-generate","debugging-toolkit:smart-debug","documentation-generation:doc-generate","c4-architecture:c4-architecture","code-refactoring:tech-debt","code-refactoring:refactor-clean","code-refactoring:context-restore","dependency-management:deps-audit","error-debugging:error-analysis","error-debugging:error-trace","error-debugging:multi-agent-review","llm-application-dev:langchain-agent","llm-application-dev:ai-assistant","llm-application-dev:prompt-optimize","context-management:context-save","context-management:context-restore","observability-monitoring:monitor-setup","observability-monitoring:slo-implement","distributed-debugging:debug-trace","deployment-validation:config-validate","cicd-automation:workflow-automate","frontend-mobile-security:xss-scan","codebase-cleanup:tech-debt","codebase-cleanup:refactor-clean","codebase-cleanup:deps-audit","systems-programming:rust-project","flow-next:flow-next-plan-review","flow-next:flow-next","flow-next:browser","flow-next:flow-next-impl-review","flow-next:flow-next-plan","flow-next:flow-next-sync","flow-next:flow-next-epic-review","flow-next:flow-next-rp-explorer","flow-next:flow-next-setup","flow-next:flow-next-interview","flow-next:flow-next-prime","flow-next:flow-next-work","flow-next:flow-next-worktree-kit","flow-next:flow-next-export-context","flow-next:flow-next-deps","flow-next:flow-next-ralph-init","python-development:async-python-patterns","python-development:python-performance-optimization","python-development:python-testing-patterns","python-development:uv-package-manager","python-development:python-packaging","javascript-typescript:modern-javascript-patterns","javascript-typescript:nodejs-backend-patterns","javascript-typescript:typescript-advanced-types","javascript-typescript:javascript-testing-patterns","backend-development:api-design-principles","backend-development:saga-orchestration","backend-development:workflow-orchestration-patterns","backend-development:event-store-design","backend-development:projection-patterns","backend-development:microservices-patterns","backend-development:architecture-patterns","backend-development:temporal-python-testing","backend-development:cqrs-implementation","documentation-generation:openapi-spec-generation","documentation-generation:architecture-decision-records","documentation-generation:changelog-automation","llm-application-dev:prompt-engineering-patterns","llm-application-dev:llm-evaluation","llm-application-dev:embedding-strategies","llm-application-dev:hybrid-search-implementation","llm-application-dev:langchain-architecture","llm-application-dev:rag-implementation","llm-application-dev:vector-index-tuning","llm-application-dev:similarity-search-patterns","observability-monitoring:distributed-tracing","observability-monitoring:grafana-dashboards","observability-monitoring:prometheus-configuration","observability-monitoring:slo-implementation","cicd-automation:gitlab-ci-patterns","cicd-automation:secrets-management","cicd-automation:deployment-pipeline-design","cicd-automation:github-actions-templates","business-analytics:kpi-dashboard-design","business-analytics:data-storytelling","systems-programming:rust-async-patterns","systems-programming:memory-safety-patterns","systems-programming:go-concurrency-patterns","quantitative-trading:risk-metrics-calculation","quantitative-trading:backtesting-frameworks","payment-processing:pci-compliance","payment-processing:stripe-integration","payment-processing:billing-automation","payment-processing:paypal-integration","playground:playground","compact","context","cost","init","pr-comments","release-notes","review","security-review","mcp__fetch__fetch"],"apiKeySource":"none","claude_code_version":"2.1.29","output_style":"default","agents":["Bash","general-purpose","statusline-setup","Explore","Plan","flow-next:repo-scout","flow-next:env-scout","flow-next:memory-scout","flow-next:security-scout","flow-next:build-scout","flow-next:observability-scout","flow-next:workflow-scout","flow-next:testing-scout","flow-next:epic-scout","flow-next:quality-auditor","flow-next:claude-md-scout","flow-next:docs-scout","flow-next:plan-sync","flow-next:github-scout","flow-next:flow-gap-analyst","flow-next:docs-gap-scout","flow-next:context-scout","flow-next:practice-scout","flow-next:tooling-scout","flow-next:worker","agent-orchestration:context-manager","python-development:fastapi-pro","python-development:python-pro","python-development:django-pro","javascript-typescript:typescript-pro","javascript-typescript:javascript-pro","backend-development:temporal-python-pro","backend-development:graphql-architect","backend-development:tdd-orchestrator","backend-development:event-sourcing-architect","backend-development:backend-architect","full-stack-orchestration:deployment-engineer","full-stack-orchestration:test-automator","full-stack-orchestration:performance-engineer","full-stack-orchestration:security-auditor","code-documentation:tutorial-engineer","code-documentation:docs-architect","code-documentation:code-reviewer","debugging-toolkit:debugger","debugging-toolkit:dx-optimizer","documentation-generation:mermaid-expert","documentation-generation:reference-builder","documentation-generation:tutorial-engineer","documentation-generation:docs-architect","documentation-generation:api-documenter","c4-architecture:c4-component","c4-architecture:c4-container","c4-architecture:c4-code","c4-architecture:c4-context","code-refactoring:legacy-modernizer","code-refactoring:code-reviewer","dependency-management:legacy-modernizer","error-debugging:debugger","error-debugging:error-detective","llm-application-dev:vector-database-engineer","llm-application-dev:ai-engineer","llm-application-dev:prompt-engineer","context-management:context-manager","observability-monitoring:network-engineer","observability-monitoring:performance-engineer","observability-monitoring:database-optimizer","observability-monitoring:observability-engineer","distributed-debugging:error-detective","distributed-debugging:devops-troubleshooter","deployment-strategies:deployment-engineer","deployment-strategies:terraform-specialist","deployment-validation:cloud-architect","cicd-automation:deployment-engineer","cicd-automation:terraform-specialist","cicd-automation:cloud-architect","cicd-automation:kubernetes-architect","cicd-automation:devops-troubleshooter","backend-api-security:backend-architect","backend-api-security:backend-security-coder","frontend-mobile-security:frontend-developer","frontend-mobile-security:frontend-security-coder","frontend-mobile-security:mobile-security-coder","codebase-cleanup:test-automator","codebase-cleanup:code-reviewer","business-analytics:business-analyst","jvm-languages:java-pro","jvm-languages:scala-pro","jvm-languages:csharp-pro","systems-programming:cpp-pro","systems-programming:golang-pro","systems-programming:rust-pro","systems-programming:c-pro","quantitative-trading:quant-analyst","quantitative-trading:risk-manager","payment-processing:payment-integration"],"skills":["keybindings-help","flow-next:flow-next-plan-review","flow-next:flow-next","flow-next:browser","flow-next:flow-next-impl-review","flow-next:flow-next-plan","flow-next:flow-next-sync","flow-next:flow-next-epic-review","flow-next:flow-next-rp-explorer","flow-next:flow-next-setup","flow-next:flow-next-interview","flow-next:flow-next-prime","flow-next:flow-next-work","flow-next:flow-next-worktree-kit","flow-next:flow-next-export-context","flow-next:flow-next-deps","flow-next:flow-next-ralph-init","python-development:async-python-patterns","python-development:python-performance-optimization","python-development:python-testing-patterns","python-development:uv-package-manager","python-development:python-packaging","javascript-typescript:modern-javascript-patterns","javascript-typescript:nodejs-backend-patterns","javascript-typescript:typescript-advanced-types","javascript-typescript:javascript-testing-patterns","backend-development:api-design-principles","backend-development:saga-orchestration","backend-development:workflow-orchestration-patterns","backend-development:event-store-design","backend-development:projection-patterns","backend-development:microservices-patterns","backend-development:architecture-patterns","backend-development:temporal-python-testing","backend-development:cqrs-implementation","documentation-generation:openapi-spec-generation","documentation-generation:architecture-decision-records","documentation-generation:changelog-automation","llm-application-dev:prompt-engineering-patterns","llm-application-dev:llm-evaluation","llm-application-dev:embedding-strategies","llm-application-dev:hybrid-search-implementation","llm-application-dev:langchain-architecture","llm-application-dev:rag-implementation","llm-application-dev:vector-index-tuning","llm-application-dev:similarity-search-patterns","observability-monitoring:distributed-tracing","observability-monitoring:grafana-dashboards","observability-monitoring:prometheus-configuration","observability-monitoring:slo-implementation","cicd-automation:gitlab-ci-patterns","cicd-automation:secrets-management","cicd-automation:deployment-pipeline-design","cicd-automation:github-actions-templates","business-analytics:kpi-dashboard-design","business-analytics:data-storytelling","systems-programming:rust-async-patterns","systems-programming:memory-safety-patterns","systems-programming:go-concurrency-patterns","quantitative-trading:risk-metrics-calculation","quantitative-trading:backtesting-frameworks","payment-processing:pci-compliance","payment-processing:stripe-integration","payment-processing:billing-automation","payment-processing:paypal-integration","playground:playground"],"plugins":[{"name":"flow-next","path":"/home/agent/.claude/plugins/cache/gmickel-claude-marketplace/flow-next/0.20.8"},{"name":"gopls-lsp","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/gopls-lsp/1.0.0"},{"name":"csharp-lsp","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/csharp-lsp/1.0.0"},{"name":"rust-analyzer-lsp","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/rust-analyzer-lsp/1.0.0"},{"name":"clangd-lsp","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/clangd-lsp/1.0.0"},{"name":"pyright-lsp","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/pyright-lsp/1.0.0"},{"name":"agent-orchestration","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/agent-orchestration/1.2.0"},{"name":"python-development","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/python-development/1.2.1"},{"name":"javascript-typescript","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/javascript-typescript/1.2.1"},{"name":"backend-development","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/backend-development/1.2.4"},{"name":"full-stack-orchestration","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/full-stack-orchestration/1.2.1"},{"name":"code-documentation","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/code-documentation/1.2.0"},{"name":"debugging-toolkit","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/debugging-toolkit/1.2.0"},{"name":"documentation-generation","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/documentation-generation/1.2.1"},{"name":"c4-architecture","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/c4-architecture/1.0.0"},{"name":"code-refactoring","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/code-refactoring/1.2.0"},{"name":"dependency-management","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/dependency-management/1.2.0"},{"name":"error-debugging","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/error-debugging/1.2.0"},{"name":"llm-application-dev","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/llm-application-dev/2.0.2"},{"name":"context-management","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/context-management/1.2.0"},{"name":"observability-monitoring","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/observability-monitoring/1.2.1"},{"name":"distributed-debugging","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/distributed-debugging/1.2.0"},{"name":"deployment-strategies","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/deployment-strategies/1.2.0"},{"name":"deployment-validation","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/deployment-validation/1.2.0"},{"name":"cicd-automation","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/cicd-automation/1.2.1"},{"name":"backend-api-security","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/backend-api-security/1.2.0"},{"name":"frontend-mobile-security","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/frontend-mobile-security/1.2.0"},{"name":"codebase-cleanup","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/codebase-cleanup/1.2.0"},{"name":"business-analytics","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/business-analytics/1.2.1"},{"name":"jvm-languages","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/jvm-languages/1.2.0"},{"name":"systems-programming","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/systems-programming/1.2.1"},{"name":"quantitative-trading","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/quantitative-trading/1.2.1"},{"name":"payment-processing","path":"/home/agent/.claude/plugins/cache/claude-code-workflows/payment-processing/1.2.1"},{"name":"playground","path":"/home/agent/.claude/plugins/cache/claude-plugins-official/playground/27d2b86d72da"}],"uuid":"3b3af6c5-d794-41af-8acf-b95c4f621c0e"}
{"type":"assistant","message":{"id":"4e61cd2e-29cc-47e1-a079-860b38392f83","container":null,"model":"<synthetic>","role":"assistant","stop_reason":"stop_sequence","stop_sequence":"","type":"message","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":null,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}},"content":[{"type":"text","text":"API Error: 500 {\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"Internal server error\"},\"request_id\":\"req_011CXmP6tDyBud7jK7kPgUjR\"}"}],"context_management":null},"parent_tool_use_id":null,"session_id":"bacf2df7-93a7-4ac4-b2ec-868b2caebcbb","uuid":"36cac210-6ab3-4926-9c06-cc2b69c5e807","error":"unknown"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Stop hook feedback:\nCannot stop: implementation review not completed.\nYou MUST invoke `/flow-next:impl-review fn-49-devcontainer-integration.3` to complete the review.\nThe skill writes the receipt on SHIP verdict.\nDo NOT write the receipt manually - that skips the actual review."}]},"parent_tool_use_id":null,"session_id":"bacf2df7-93a7-4ac4-b2ec-868b2caebcbb","uuid":"1d95b684-7cba-4e96-95a0-f08bda09a4eb","isSynthetic":true}
{"type":"assistant","message":{"id":"065f8e86-7c09-4632-8f8c-393128c8df8f","container":null,"model":"<synthetic>","role":"assistant","stop_reason":"stop_sequence","stop_sequence":"","type":"message","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":null,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}},"content":[{"type":"text","text":"API Error: 500 {\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"Internal server error\"},\"request_id\":\"req_011CXmP6uPR4J2LwdpMA4Eg8\"}"}],"context_management":null},"parent_tool_use_id":null,"session_id":"bacf2df7-93a7-4ac4-b2ec-868b2caebcbb","uuid":"0ac41e1d-f487-4ed4-9947-96d46a190ad4","error":"unknown"}
{"type":"result","subtype":"success","is_error":true,"duration_ms":778,"duration_api_ms":0,"num_turns":2,"result":"API Error: 500 {\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"Internal server error\"},\"request_id\":\"req_011CXmP6uPR4J2LwdpMA4Eg8\"}","session_id":"bacf2df7-93a7-4ac4-b2ec-868b2caebcbb","total_cost_usd":0,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}},"modelUsage":{},"permission_denials":[],"uuid":"9a12a2fc-8acf-4711-af2b-fab58259435e"}
ralph: missing impl review receipt; forcing retry
ralph: task not done; forcing retry
## Evidence
- Commits:
- Tests:
- PRs:
