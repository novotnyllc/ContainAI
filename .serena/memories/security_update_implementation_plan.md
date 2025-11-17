# Security Update Implementation Plan

1. **Launcher Integrity + Config Generation**
   - Enforce git-clean checks for `scripts/launchers/**` and stub binaries at launch, logging commit/tree hashes; allow host override token with explicit logging.
   - Build session config renderer (reads `config.toml`, merges runtime data, writes to per-session tmpfs, logs SHA256).
   - Tests: git cleanliness unit/integration; config renderer permissions + hashing.

2. **Broker Enhancements**
   - Generate/store per-stub mutual-auth keys in host-only config (chmod 600, chattr +i); add HMAC capability redemption and per-session envelope encryption.
   - Add rate limiting/backoff, watchdog that halts launches if broker dies or sandbox degrades; run broker under systemd sandbox (ProtectSystem=strict, PrivateTmp, seccomp/AppArmor).
   - Tests: unit coverage for HMAC/encryption; integration verifying rejection of bad HMAC, watchdog triggers, rate limiting.

3. **Stub/Helper Isolation**
   - Enforce `ptrace_scope=3`, seccomp/AppArmor blocks for ptrace/process_vm, launch stubs/helpers in dedicated PID namespaces with hardened tmpfs mounts (`nosuid,nodev,noexec`), sandbox helpers to intended loopback/HTTPS targets only.
   - Tests: ensure agent cannot ptrace stub; helper profile blocks forbidden syscalls/network paths.

4. **Logging & Override Workflow**
   - Emit issuance telemetry (config hash, git hash, capability IDs) to journald + append-only file; optional off-host shipping.
   - Require/log override token use when launching with dirty trusted files.
   - Tests: log format/rotation + override enforcement integration.

5. **Documentation & Guidance**
   - Update SECURITY.md, secret-broker-architecture doc, launcher README for new controls and test expectations; add helper profile/ptrace guidance.
   - Tests: CI lint + manual verification checklist.

Execution order: broker + launcher updates → sandboxing → logging/watchdogs → documentation/tests; ensure CI gates on new suites.