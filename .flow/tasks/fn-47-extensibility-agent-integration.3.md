# fn-47-extensibility-agent-integration.3 Network Policy Files - Implement .containai/network.conf parsing

## Description

Allow users to configure **opt-in** network egress restrictions via a simple config file. This is for users who want stricter policies than the default.

### Default Behavior (No Config File)

**Without `network.conf`:** Allow all egress, except existing hard blocks:
- Private ranges blocked (RFC 1918: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
- Link-local blocked (169.254.0.0/16)
- Cloud metadata blocked (169.254.169.254, etc.)

This is the current behavior and remains unchanged.

### Opt-In Restriction (With Config File)

Users who want stricter egress control create `network.conf`:

```ini
# .containai/network.conf
# OPTIONAL - only create if you want to restrict egress

[egress]
# Use presets (expand to known domains)
preset = package-managers
preset = git-hosts

# Allow specific domains/IPs
allow = api.anthropic.com
allow = 10.0.0.0/8

# REQUIRED to enable blocking - without this, config has no effect
default_deny = true
```

**Key point:** `default_deny = true` is required to enable blocking. Without it, the config is informational only (logged but not enforced).

### Config Semantics

| Setting | Meaning |
|---------|---------|
| No `network.conf` | Allow all (except hard blocks) - **default** |
| `network.conf` without `default_deny` | Allow all, log allowed list (informational) |
| `network.conf` with `default_deny = true` | Allow only listed, block rest |

### Presets

Define in `src/lib/network.sh`:

| Preset | Domains/CIDRs |
|--------|---------------|
| `package-managers` | registry.npmjs.org, pypi.org, files.pythonhosted.org, crates.io, rubygems.org |
| `git-hosts` | github.com, gitlab.com, bitbucket.org |
| `ai-apis` | api.anthropic.com, api.openai.com |

### Implementation

1. **New function in `src/lib/network.sh`:**
   - `_cai_parse_network_conf()` - Parse INI-style config
   - `_cai_resolve_domain_to_ips()` - DNS resolution (with timeout)
   - `_cai_apply_network_policy()` - Generate iptables from config

2. **Integration point:**
   - Call from host side before container start (can use host DNS)
   - Only applies rules if `default_deny = true`

3. **Rule application:**
   - Existing private-range blocks remain (always applied)
   - If `default_deny = true`: add ACCEPT rules for allowed, then DROP default
   - If no `default_deny`: log config, don't add rules

4. **Error handling:**
   - Invalid config syntax: warn and skip
   - DNS resolution failure: warn and skip that domain
   - Missing `default_deny`: log info, continue with allow-all

### Gotchas

- DNS resolution returns multiple IPs - add all
- CDNs change IPs - document this limitation
- IPv6 support: skip if not enabled
- Hard blocks (private ranges, metadata) always apply regardless of config

## Acceptance

- [ ] No `network.conf` = allow all egress (except hard blocks) - unchanged default
- [ ] `network.conf` without `default_deny` = informational only, no blocking
- [ ] `network.conf` with `default_deny = true` = enforce allowlist
- [ ] `preset` keyword expands to predefined domain lists
- [ ] `allow` entries resolved to IPs and added to iptables
- [ ] DNS resolution failures logged as warnings, don't fail start
- [ ] Invalid config syntax logged as warning
- [ ] Existing private-range blocking always applies
- [ ] Integration test with network policy

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
