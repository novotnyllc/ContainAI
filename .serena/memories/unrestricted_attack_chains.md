# Attack Chains & Mitigations

## AC-01: Secret Exfiltration via Allow-All Network
1. Prompt injection convinces agent to `cat ~/.config/gh/hosts.yml`.
2. Agent runs `curl` to attacker-controlled domain over unrestricted bridge to upload tokens.
3. Attacker reuses PAT to pivot into other repos; host unaware.

**Mitigation in Hardened Design:**
- Default Squid proxy (HDN-NET-01) blocks unknown domains and logs all requests, preventing the outbound upload.
- Secret broker (HDN-SEC-01) removes long-lived gh configs from the container; only scoped session tokens are present and expire when kill switch triggered.
- Safe shell wrapper (SA-01) logs the `cat` command and optionally redacts sensitive file reads, giving defenders an audit trail.

## AC-02: Persistence via Launcher Tampering
1. Agent edits `scripts/launchers/launch-agent` to remove capability drop and insert malicious payload executed on next launch.
2. Auto-push syncs the modified script back to host; developer unknowingly runs compromised launcher which spins up privileged containers.
3. Attacker now has path to host-level compromise via new docker mounts.

**Mitigation in Hardened Design:**
- Writable path whitelist (HDN-FS-02) prevents modifying `/scripts/launchers` inside the container because only `/workspace` + tmpfs are writable.
- Snapshot + policy diff (HDN-FS-01) ensures host sees the change before adoption and can roll back automatically.
- Tool matrix Tier 3 classification for editing launcher scripts means Serena’s `safe_write` guard requires explicit confirmation before touching those files.
