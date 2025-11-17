# Prioritized Action Plan (Updated for Shared-Token Constraint)

1. **Runtime Hardening Parity**
   - Apply `run-agent` security flags to `launch-agent` (cap drop, seccomp/AppArmor, read-only root, tmpfs safe zones) so every session—persistent or ephemeral—has the same container isolation baseline.

2. **Proxy-First Networking & Monitoring**
   - Make Squid proxy the default, expand allowlists to cover required dev/MCP domains, block RFC1918/metadata ranges, and stream per-session logs + token-bucket alerts back to the host for auditing.

3. **Secret Broker (Shared Credential Exposure Control)**
   - Introduce the broker that hands out short-lived copies of shared API tokens, injects them via env vars, wipes them on teardown, and records which session accessed the secret even though upstream services cannot issue per-agent credentials.

4. **Snapshot & Writable-Path Controls (Package-Safe)**
   - Automate git snapshots/tags, provide rollback helpers, enforce writable-path whitelist with package-manager scratch overlays + `safe_pkg` wrapper so dev builds continue to work while preventing stealthy tampering of system files.

5. **Safe Abstractions + Tool Tier Enforcement**
   - Implement `safe_sh`, `safe_write`, `safe_net`, `safe_secret` plus the Tool Danger Matrix enforcement so Tier 1 actions remain prompt-free, Tier 2 actions are logged/throttled, and Tier 3 actions require explicit confirmation or are blocked.

6. **SSH/GPG Policy Layer & Kill Switch**
   - Wrap forwarded sockets with host-allowlist daemons, disable forwarding by default, and wire `coding-agents kill <session>` to stop containers and revoke brokered secrets immediately when suspicious behavior is detected.
