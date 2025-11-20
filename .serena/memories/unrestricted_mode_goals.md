# Safe-Unrestricted Mode Goals

## GOAL-UX-01: Frictionless Default Flow
- Category: Policy Decision / UX Goal
- Description: Common Tier 1 development actions (editing files, running tests, invoking allowlisted MCP servers) must execute without confirmation dialogs once unrestricted mode is enabled. Users should be able to "click once" to enter unrestricted mode and work normally without repeated prompts.

## GOAL-SEC-01: Absolute Host Isolation
- Category: Security Goal
- Description: Containers must never mount docker.sock, host root filesystems, or other device nodes that would allow host control. All host interactions should be mediated through read-only config mounts, ephemeral sockets with narrowly scoped APIs (credential proxy), or network calls to explicitly approved services.

## GOAL-SEC-02: Bounded Damage Radius
- Category: Security Goal
- Description: Even when an agent behaves maliciously, destructive changes must remain confined to the container workspace copy plus any explicitly scoped git branches/bare remotes. Automatic snapshots/branches must let humans revert changes without prompts.

## GOAL-SEC-03: Secrets Minimization & Scope
- Category: Security Goal
- Description: Only the minimal secret set required for agent functionality (e.g., repo-scoped Git token, MCP API keys) should enter the container, each with least-privilege scopes and short lifetimes. Infra or admin credentials stay on the host.

## GOAL-NET-01: Useful but Governed Network Access
- Category: Networking Goal
- Description: MCP and developer tooling that require internet access must continue to function, but outbound requests should traverse an enforcement point (proxy/egress controller) that logs activity, blocks prohibited domains (metadata endpoints, private nets), and can throttle bulk transfers to deter exfiltration.

## GOAL-MON-01: Observability & Kill Switch
- Category: Security Goal
- Description: Every unrestricted session should produce auditable network/proxy logs and git snapshots; operators must have a one-step kill switch that stops the container and revokes temporary credentials without additional prompts.
