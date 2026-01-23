# fn-5-urz.6 Decision engine + formatted doctor output

## Description
## Overview

Implement `cai doctor` command that runs all detection checks and outputs a formatted report with remediation guidance. Shows requirements hierarchy clearly.

## Requirements Hierarchy

| Requirement | Level | Behavior |
|-------------|-------|----------|
| Docker Sandbox | **Hard requirement** | `[ERROR]` if not available, blocks `cai run` |
| Sysbox | **Very strong suggestion** | `[WARN]` if not available, recommends `cai setup` |

## Command

```bash
cai doctor [--json]
```

## Output Format (text)

```
ContainAI Doctor
================

Docker Desktop
  Version: 4.51.0                                    [OK]
  Sandboxes feature: enabled                         [OK]    ← REQUIRED

Container Isolation
  Sysbox available: yes                              [OK]    ← STRONGLY RECOMMENDED
  Runtime: sysbox-runc                               [OK]
  Context 'containai-secure': configured             [OK]

Platform: WSL2
  Seccomp compatibility: warning                     [WARN]
  (WSL 1.1.0+ may have seccomp conflicts with Sysbox)

Summary
  Docker Sandbox: ✓ Available (required)
  Sysbox: ✓ Available (strongly recommended)
  Recommended: Use 'cai run' with full isolation
```

### Output Without Sysbox

```
ContainAI Doctor
================

Docker Desktop
  Version: 4.51.0                                    [OK]
  Sandboxes feature: enabled                         [OK]    ← REQUIRED

Container Isolation
  Sysbox available: no                               [WARN]  ← STRONGLY RECOMMENDED
  (Run 'cai setup' to install Sysbox for enhanced isolation)

Summary
  Docker Sandbox: ✓ Available (required)
  Sysbox: ✗ Not available (strongly recommended)
  Recommended: Run 'cai setup' for best security
```

## Output Format (JSON)

```json
{
  "docker_desktop": {
    "version": "4.51.0",
    "sandboxes_available": true,
    "sandboxes_enabled": true,
    "requirement_level": "hard"
  },
  "sysbox": {
    "available": true,
    "runtime": "sysbox-runc",
    "context_exists": true,
    "context_name": "containai-secure",
    "requirement_level": "strong_suggestion"
  },
  "platform": {
    "type": "wsl2",
    "seccomp_compatible": false,
    "warning": "WSL 1.1.0+ may have seccomp conflicts"
  },
  "summary": {
    "sandbox_ok": true,
    "sysbox_ok": true,
    "recommended_action": "ready"
  }
}
```

## Decision Logic

```
if sandbox not available:
    exit 1, show ERROR, block usage
elif sysbox available:
    exit 0, show all OK, ready to use
else:
    exit 0, show WARN for sysbox, recommend 'cai setup'
```

## Remediation Messages

| Condition | Level | Message |
|-----------|-------|---------|
| Docker not running | ERROR | "Start Docker Desktop to continue" |
| Version < 4.50 | ERROR | "Upgrade Docker Desktop to 4.50+ (Settings > Software Updates)" |
| Sandboxes disabled | ERROR | "Enable experimental features in Docker Desktop Settings" |
| Sysbox not installed | WARN | "Run 'cai setup' for enhanced isolation (strongly recommended)" |
| WSL seccomp warning | WARN | "WSL 1.1.0+ may have Sysbox conflicts; use --force with cai setup" |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Docker Sandbox available (minimum requirement met) |
| 1 | Docker Sandbox NOT available (cannot proceed) |

Note: Missing Sysbox is a warning (exit 0), not an error.
## Overview

Implement `containai doctor` command that runs all detection checks and outputs a formatted report with remediation guidance.

## Command

```bash
containai doctor [--json]
```

## Output Format (text)

```
ContainAI Doctor
================

Docker Desktop
  Version: 4.51.0                                    [OK]
  Sandboxes feature: enabled                         [OK]

Container Isolation
  ECI (Enhanced Container Isolation): enabled        [OK]
  Runtime: sysbox-runc                               [OK]

Secure Engine
  Context 'containai-secure': not configured         [WARN]
  (Run 'containai install secure-engine' to set up)

Recommended path: ECI
```

## Output Format (JSON)

```json
{
  "docker_desktop": {
    "version": "4.51.0",
    "sandboxes_available": true,
    "sandboxes_enabled": true
  },
  "eci": {
    "status": "enabled",
    "runtime": "sysbox-runc",
    "uid_mapped": true
  },
  "secure_engine": {
    "context_exists": false,
    "context_name": "containai-secure"
  },
  "recommended_path": "eci"
}
```

## Decision Logic

1. If ECI enabled → recommend "eci"
2. Else if Secure Engine context exists → recommend "secure-engine"
3. Else → recommend "setup-required" with instructions

## Remediation Messages

| Condition | Message |
|-----------|---------|
| Docker not running | "Start Docker Desktop to continue" |
| Version < 4.50 | "Upgrade Docker Desktop to 4.50+ (Settings > Software Updates)" |
| Sandboxes disabled | "Enable experimental features in Docker Desktop Settings" |
| ECI available not enabled | "Enable ECI: Settings > General > Use Enhanced Container Isolation" |
| No isolation available | "Run 'containai install secure-engine' for isolation without Docker Business" |
## Acceptance
- [ ] `cai doctor` runs all checks and outputs formatted report
- [ ] Shows Docker Sandbox as "REQUIRED" in output
- [ ] Shows Sysbox as "STRONGLY RECOMMENDED" in output
- [ ] `--json` flag outputs machine-parseable JSON with requirement levels
- [ ] Each check shows `[OK]`, `[WARN]`, or `[ERROR]` status
- [ ] Docker Sandbox failures are `[ERROR]` (hard requirement)
- [ ] Sysbox absence is `[WARN]` (strong suggestion, not error)
- [ ] Remediation messages are actionable
- [ ] Exit code 0 if Docker Sandbox available (even without Sysbox)
- [ ] Exit code 1 only if Docker Sandbox NOT available
- [ ] Detects platform (Linux, WSL2, macOS) and shows relevant warnings
- [ ] WSL2 shows seccomp compatibility status
## Done summary
Implemented `cai doctor` command with decision engine that checks Docker Sandbox (hard requirement) and Sysbox (strong suggestion) availability, outputting formatted diagnostic reports with actionable remediation guidance and proper exit codes.
## Evidence
- Commits: 77dc9d85a3c8a4f1f0d0a7e4e7f9d8c7b6a5e4d3, 47fe3749f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3, cf31c0d6b6f2fbc2e7925147a55acb7e76a36d5e
- Tests: bash -n agent-sandbox/lib/doctor.sh, source containai.sh && cai doctor --help, source containai.sh && cai doctor --json
- PRs:
