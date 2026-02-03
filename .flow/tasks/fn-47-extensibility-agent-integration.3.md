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

# Allow specific domains/IPs (one per line)
allow = api.anthropic.com
allow = my-internal-service.local

# REQUIRED to enable blocking - without this, config has no effect
default_deny = true
```

**Key point:** `default_deny = true` is required to enable blocking. Without it, the config is informational only (logged but not enforced).

**Note:** Hard blocks (private ranges, cloud metadata) CANNOT be overridden. If an `allow` entry conflicts with a hard block, it is logged as a warning and ignored.

### Config Semantics

| Setting | Meaning |
|---------|---------|
| No `network.conf` | Allow all (except hard blocks) - **default** |
| `network.conf` without `default_deny` | Allow all, log allowed list (informational) |
| `network.conf` with `default_deny = true` | Allow only listed, block rest |

### Config Format

One value per line. Each `preset =` or `allow =` line specifies a single value:
```ini
[egress]
preset = package-managers
preset = git-hosts
allow = api.anthropic.com
allow = example.com
default_deny = true
```

### Per-Container Rule Scoping

**Problem:** Existing network enforcement is host-side iptables on the ContainAI bridge (`DOCKER-USER` chain in `src/lib/network.sh`). Multiple containers can share the same bridge. A naive "default deny" would affect ALL containers.

**Solution:** Scope rules per-container using container IP:
- Use `-s <container_ip>` in iptables rules to scope ACCEPT rules to specific container
- Apply rules on container start/attach (not just creation)
- Remove rules on container stop/remove
- On container recreate, rules automatically updated (removed on stop, added on start)

**Getting container IP reliably:**
```bash
# Handle multi-network setups - get IP from ContainAI bridge network
docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{if eq $k "bridge"}}{{$v.IPAddress}}{{end}}{{end}}' <container>
# Or get first available IP as fallback
docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' <container> | head -1
```

**Rule order in DOCKER-USER chain:**
1. Existing hard blocks (private ranges, metadata) - always present, global
2. Per-container ACCEPT rules: `-s <container_ip> -d <allowed_ip> -j ACCEPT`
3. Per-container DROP default: `-s <container_ip> -j DROP` (only if default_deny=true)

### Rule Lifecycle

**Apply rules on:**
- Container creation (new container)
- Container start (existing stopped container)
- Container attach (reconnecting to running container)

**Remove rules on:**
- Container stop
- Container remove

**Integration points (all stop paths):**
- `_containai_stop_all()` - handles `cai stop --all`
- `containai.sh` stop with `--container` flag
- Workspace-based stop in `containai.sh`
- Factor a shared helper `_cai_cleanup_container_network()` called by all paths

### Presets (Expanded)

Define in `src/lib/network.sh`:

| Preset | Domains/CIDRs |
|--------|---------------|
| `package-managers` | registry.npmjs.org, pypi.org, files.pythonhosted.org, crates.io, dl.crates.io, static.crates.io, rubygems.org |
| `git-hosts` | github.com, api.github.com, codeload.github.com, raw.githubusercontent.com, objects.githubusercontent.com, media.githubusercontent.com, gitlab.com, registry.gitlab.com, bitbucket.org |
| `ai-apis` | api.anthropic.com, api.openai.com |

### Implementation

1. **New functions in `src/lib/network.sh`:**
   - `_cai_parse_network_conf()` - Parse INI-style config file (one value per line)
   - `_cai_resolve_domain_to_ips()` - DNS resolution (with timeout, returns all IPs)
   - `_cai_expand_preset()` - Expand preset name to domain list
   - `_cai_get_container_ip()` - Get container IP, handling multi-network setups
   - `_cai_apply_container_network_policy()` - Apply iptables for specific container
   - `_cai_remove_container_network_rules()` - Clean up rules for specific container

2. **Integration points:**
   - **Start:** Call `_cai_apply_container_network_policy()` from all start/attach paths in `_containai_start_container()`
   - **Stop:** Factor `_cai_cleanup_container_network()` and call from:
     - `_containai_stop_all()`
     - `containai.sh` stop with `--container`
     - `containai.sh` workspace stop path
   - Use container name as rule identifier (comment in iptables for cleanup)

3. **Rule application:**
   - Existing hard blocks remain (always applied, global)
   - If `default_deny = true` for a container:
     - Add `-s <container_ip> -d <allowed_ip> -j ACCEPT -m comment --comment "cai:<container_name>"`
     - Add `-s <container_ip> -j DROP -m comment --comment "cai:<container_name>"`
   - If no `default_deny`: log config, don't add rules

4. **Error handling:**
   - Invalid config syntax: warn and skip
   - DNS resolution failure: warn and skip that domain (don't fail start)
   - Missing `default_deny`: log info, continue with allow-all
   - Allow entry conflicts with hard block: warn and ignore

### Gotchas

- DNS resolution returns multiple IPs - add all
- CDNs change IPs - document this limitation
- IPv6 support: skip if not enabled
- Hard blocks (private ranges, metadata) always apply regardless of config
- Use iptables comments for cleanup identification

## Acceptance

- [ ] No `network.conf` = allow all egress (except hard blocks) - unchanged default
- [ ] `network.conf` without `default_deny` = informational only, no blocking
- [ ] `network.conf` with `default_deny = true` = enforce allowlist
- [ ] Rules scoped per-container using `-s <container_ip>`
- [ ] Rules applied on container start/attach (not just creation)
- [ ] Rules removed on container stop/remove
- [ ] All stop paths cleaned up (not just `_containai_stop_all`)
- [ ] `preset` keyword expands to predefined domain lists
- [ ] `allow` entries resolved to IPs and added to iptables
- [ ] Hard block conflicts logged as warnings and ignored
- [ ] DNS resolution failures logged as warnings, don't fail start
- [ ] Invalid config syntax logged as warning
- [ ] Existing private-range blocking always applies (global)
- [ ] Config format: one value per `allow=` or `preset=` line
- [ ] Integration test with network policy

## Done summary
## Implementation Summary

Verified existing implementation of opt-in network egress control via `.containai/network.conf` parsing.

### Changes Already Committed

1. **src/lib/network.sh** - Added per-container network policy functions:
   - `_cai_parse_network_conf()` - Parse INI-style config file
   - `_cai_expand_preset()` - Expand preset names to domain lists (package-managers, git-hosts, ai-apis)
   - `_cai_resolve_domain_to_ips()` - DNS resolution with fallbacks (getent, dig, host)
   - `_cai_ip_conflicts_with_hard_block()` - Check for conflicts with hard blocks (private ranges, metadata)
   - `_cai_get_container_ip()` - Get container IP from Docker
   - `_cai_apply_container_network_policy()` - Apply iptables rules per-container
   - `_cai_remove_container_network_rules()` - Remove per-container rules
   - `_cai_cleanup_container_network()` - Cleanup helper for stop paths

2. **src/lib/container.sh** - Integration with container lifecycle:
   - Apply network policy after container start (3 paths: exited, created, new)
   - Clean up network rules before stop/remove in `_containai_stop_all` (5 cleanup call sites)

3. **src/containai.sh** - Integration with stop command:
   - Clean up network rules in `--container` stop path (2 sites: rm and stop)
   - Clean up network rules in workspace-based stop path (2 sites: rm and stop)

4. **tests/integration/test-network-policy.sh** - Comprehensive unit tests

### Features Implemented

- Config parsing with comments, whitespace handling
- Preset support: `package-managers`, `git-hosts`, `ai-apis`
- Hard block conflict detection and warning
- Per-container iptables rules using `-s <container_ip>` and comment tags
- Rule cleanup on all stop paths
- Template-level and workspace-level config merge
- DNS resolution with timeout and fallback strategies
## Implementation Summary

Implemented opt-in network egress control via `.containai/network.conf` parsing.

### Changes Made

1. **src/lib/network.sh** - Added per-container network policy functions:
   - `_cai_parse_network_conf()` - Parse INI-style config file
   - `_cai_expand_preset()` - Expand preset names to domain lists
   - `_cai_resolve_domain_to_ips()` - DNS resolution with fallbacks (getent, dig, host)
   - `_cai_ip_conflicts_with_hard_block()` - Check for conflicts with hard blocks
   - `_cai_get_container_ip()` - Get container IP from Docker
   - `_cai_apply_container_network_policy()` - Apply iptables rules per-container
   - `_cai_remove_container_network_rules()` - Remove per-container rules
   - `_cai_cleanup_container_network()` - Cleanup helper for stop paths

2. **src/lib/container.sh** - Integration with container lifecycle:
   - Apply network policy after container start (exited/created and new cases)
   - Clean up network rules before stop/remove in `_containai_stop_all`

3. **src/containai.sh** - Integration with stop command:
   - Clean up network rules in `--container` stop path
   - Clean up network rules in workspace-based stop path

4. **tests/integration/test-network-policy.sh** - Comprehensive unit tests

### Features Implemented

- Config parsing with comments, whitespace handling
- Preset support: `package-managers`, `git-hosts`, `ai-apis`
- Hard block conflict detection and warning
- Per-container iptables rules using `-s <container_ip>`
- Rule cleanup on all stop paths
- Template-level and workspace-level config merge
## Evidence
- Commits: 5c93171, 4645487, 10a7d6c
- Tests:
- PRs:
