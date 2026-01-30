# Option B: Direct JSON Parsing Approach

## Overview

Evaluate parsing devcontainer.json directly with jq/Python, building container configuration from scratch without using @devcontainers/cli. This provides maximum control over the parsing and launch pipeline at the cost of implementing spec-compliant parsing.

## Minimum Viable Parsing Requirements

### Properties ContainAI MUST Understand

Based on the security classification (fn-13-1c7.1) and usage analysis (50 real-world repos):

| Property | Usage | Why Required |
|----------|-------|--------------|
| `image` | 64% | Primary container source |
| `name` | 68% | Display/identification |
| `features` | 68% | Feature installation |
| `build.dockerfile` | 30% | Custom image builds |
| `build.context` | 10% | Build context path |
| `workspaceFolder` | 14% | Container workspace path |
| `workspaceMount` | 10% | How workspace is mounted |
| `postCreateCommand` | 64% | Critical for repo setup |
| `onCreateCommand` | 14% | Setup hook |
| `remoteUser` | 36% | User context |
| `containerEnv` | 6% | Environment variables |
| `forwardPorts` | 12% | Port exposure |
| `mounts` | 18% | Additional volumes |
| `runArgs` | 20% | Docker run options |
| `privileged` | 6% | Security-critical (BLOCK) |
| `capAdd` | 0% (in props) | Security-critical (FILTER) |
| `securityOpt` | 0% | Security-critical (FILTER) |
| `initializeCommand` | 0% | Security-critical (BLOCK) |

**Minimum viable set (covers ~95% of repos):**
- `image`, `name`, `build`, `workspaceFolder`, `postCreateCommand`, `remoteUser`, `features`, `mounts`

### Properties That Can Be Safely Ignored

| Property | Reason |
|----------|--------|
| `customizations.vscode.*` | IDE-specific, not needed for container launch |
| `customizations.codespaces.*` | GitHub Codespaces-specific |
| `portsAttributes`, `otherPortsAttributes` | Metadata only, not runtime |
| `hostRequirements` | Advisory only |
| `secrets` | Metadata only (not values) |
| `waitFor` | IDE orchestration |
| `$schema` | Validation hint |

---

## JSONC Parsing Challenge

Devcontainer.json officially supports JSON with Comments (JSONC) per the spec.

### Option 1: Strip Comments Then jq (Recommended)

**Approach:** Preprocess JSONC to JSON, then parse with jq.

```bash
# Strip comments and trailing commas
_strip_jsonc() {
    local input="$1"
    # Use sed or Python for preprocessing
    python3 -c "
import re, sys
text = sys.stdin.read()
# Strip block comments
text = re.sub(r'/\*[\s\S]*?\*/', '', text)
# Strip line comments (preserve URLs like https://)
text = re.sub(r'(?<![:\"])//.*?(?=\n|$)', '', text)
# Remove trailing commas before } or ]
text = re.sub(r',(\s*[}\]])', r'\\1', text)
print(text)
" < "$input"
}

# Usage
_strip_jsonc devcontainer.json | jq '.image'
```

**Pros:**
- jq is already a ContainAI dependency
- Minimal additional code
- Fast for most configs

**Cons:**
- Regex-based comment stripping is fragile
- Comments inside strings could theoretically break (rare)
- Two-pass processing

**Parse success rate from usage analysis:** 98% (50/51 files) with this approach.

### Option 2: Python json5 Library

**Approach:** Use Python `json5` or `pyjson5` for native JSONC support.

```bash
# Install: pip install json5 OR pyjson5
python3 -c "
import json5
import sys
data = json5.load(sys.stdin)
import json
print(json.dumps(data))
" < devcontainer.json | jq '.image'
```

**Pros:**
- Robust JSONC parsing
- Handles edge cases (comments in strings, trailing commas)
- Well-tested library

**Cons:**
- Adds Python dependency for parsing
- json5 package size: ~50KB
- pyjson5 (C extension) is faster but requires compilation

### Option 3: Custom Comment Stripper in Bash

**Approach:** Pure bash/sed implementation.

```bash
# Extremely fragile - NOT recommended
sed -e 's|//.*||g' -e ':a;N;$!ba;s|/\*.*\*/||g' devcontainer.json | jq .
```

**Verdict:** Too fragile. Real JSONC has edge cases that sed cannot handle correctly.

### Recommendation

**Option 1 (Strip + jq) for MVP**, with Option 2 (Python json5) as fallback for complex configs.

ContainAI already has:
- `jq` as a hard dependency
- `python3` in the image (used for TOML parsing)

Adding json5: `pip install json5` adds ~50KB, acceptable tradeoff.

**Hybrid approach:**
1. Try strip + jq first (fast path)
2. If jq fails (parse error), fall back to json5
3. If json5 fails, report clear error

---

## Variable Expansion Requirements

Devcontainer spec supports several variable formats.

### Variables to Implement

| Variable | Meaning | Implementation |
|----------|---------|----------------|
| `${localWorkspaceFolder}` | Host workspace path | Replace with source path |
| `${localWorkspaceFolderBasename}` | Workspace directory name | `basename` of workspace |
| `${containerWorkspaceFolder}` | Container workspace path | `/home/agent/workspace` |
| `${localEnv:VAR}` | Host environment variable | `$VAR` from shell |
| `${localEnv:VAR:default}` | With default value | `${VAR:-default}` |
| `${containerEnv:VAR}` | Container environment | Only in remoteEnv context |
| `${devcontainerId}` | Unique container ID | Generate hash |

### Implementation Complexity

**Simple substitution (covers most cases):**

```bash
_expand_devcontainer_vars() {
    local config="$1"
    local workspace_folder="$2"
    local workspace_basename
    workspace_basename=$(basename "$workspace_folder")

    # Static substitutions
    config="${config//\$\{localWorkspaceFolder\}/$workspace_folder}"
    config="${config//\$\{localWorkspaceFolderBasename\}/$workspace_basename}"
    config="${config//\$\{containerWorkspaceFolder\}/\/home\/agent\/workspace}"

    # localEnv substitutions (with optional default)
    while [[ "$config" =~ \$\{localEnv:([^:}]+)(:([^}]*))?\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local default_value="${BASH_REMATCH[3]}"
        local var_value="${!var_name:-$default_value}"
        config="${config//\$\{localEnv:$var_name\}/$var_value}"
        config="${config//\$\{localEnv:$var_name:$default_value\}/$var_value}"
    done

    printf '%s' "$config"
}
```

**Estimated effort:** 1-2 days for robust implementation with tests.

---

## Feature Merging Complexity

Features are a significant challenge for direct parsing.

### How Features Work

1. Each feature is a Git repository or OCI artifact
2. Contains `devcontainer-feature.json` metadata + `install.sh`
3. CLI downloads, extracts, and runs `install.sh` during build
4. Features can declare dependencies on other features
5. Features can add `containerEnv`, `mounts`, `capAdd`, etc.

### Merge Algorithm (from spec)

| Property Type | Merge Strategy |
|--------------|----------------|
| Boolean (`init`, `privileged`) | `true` if ANY is true |
| Array (`capAdd`, `securityOpt`) | Union, no duplicates |
| Object (`containerEnv`) | Merge, later wins |
| Command (`postCreateCommand`) | Collect all, run in order |

### Implementation Complexity Assessment

**Minimal (feature passthrough):**
- Don't process features at all
- Build Dockerfile with `FROM` base image
- Let user install tools manually
- **Effort:** 0 (but defeats purpose of features)

**Basic (download + execute):**
- Download feature tarballs
- Extract to temp directory
- Run `install.sh` during build
- No metadata merging
- **Effort:** 3-5 days

**Full (spec-compliant):**
- Parse `devcontainer-feature.json`
- Resolve dependencies
- Merge metadata into config
- Handle versioning, options
- **Effort:** 2-4 weeks

### Recommendation

**Do NOT implement full feature support in direct parsing.**

The feature system is complex enough that the CLI should be used for this specific task:

1. Use `devcontainer features resolve` to get feature metadata
2. Or allowlist specific features and hardcode their behavior
3. Or skip features entirely for MVP

---

## Configuration File Precedence Rules

### Discovery Locations (per spec)

1. `.devcontainer/devcontainer.json` (most common)
2. `.devcontainer.json` (root level)
3. `.devcontainer/<folder>/devcontainer.json` (named configs)

**Priority:** First match wins, but spec allows user selection for multiple configs.

### Implementation

```bash
_discover_devcontainer_config() {
    local workspace="$1"
    local configs=()

    # Check in priority order
    if [[ -f "$workspace/.devcontainer/devcontainer.json" ]]; then
        configs+=("$workspace/.devcontainer/devcontainer.json")
    fi

    if [[ -f "$workspace/.devcontainer.json" ]]; then
        configs+=("$workspace/.devcontainer.json")
    fi

    # Check for named configs (one level deep)
    for dir in "$workspace"/.devcontainer/*/; do
        if [[ -f "${dir}devcontainer.json" ]]; then
            configs+=("${dir}devcontainer.json")
        fi
    done

    printf '%s\n' "${configs[@]}"
}
```

### Multi-Config Selection UX

When multiple configs exist:
1. If `--config` flag provided, use that
2. If only one config, use it
3. If multiple, prompt user (interactive) or error (non-interactive)

**Link to fn-12-css:** Workspace-centric config may affect devcontainer discovery. Consider allowing workspace config to specify preferred devcontainer.

---

## Build Handling Analysis

### How to Obtain Final Image?

**Scenario A: `image` property (64% of configs)**
```json
{"image": "mcr.microsoft.com/devcontainers/base:ubuntu"}
```

- Pull image directly: `docker pull <image>`
- Apply features as build layer if needed
- Straightforward, no build required

**Scenario B: `build.dockerfile` property (30% of configs)**
```json
{
  "build": {
    "dockerfile": "Dockerfile",
    "context": "..",
    "args": {"VARIANT": "22.04"}
  }
}
```

- Build with `docker build -f <dockerfile> -t <tag> <context>`
- Pass build args
- Apply features as subsequent build

### Where Does Build Execute?

| Location | Pros | Cons |
|----------|------|------|
| **Host Docker daemon** | Fast (shared cache) | Breaks isolation model |
| **DinD inside Sysbox** | Already sandboxed | Slower (no shared cache) |
| **Kaniko (daemonless)** | Maximum isolation | Partial feature support |

**Recommendation:** Build inside Sysbox's DinD.

- Host is already sandboxed (Sysbox outer container)
- Supply chain risks contained
- Natural integration with ContainAI's DinD feature

### Feature Installation Control

**Allowlist approach (recommended):**
- Only permit `ghcr.io/devcontainers/features/*`
- Hardcode behavior of top features:
  - `docker-in-docker:2` - already supported by Sysbox
  - `github-cli:1` - safe, just installs gh
  - `git:1` - safe
  - `node:1`, `go:1`, `rust:1` - safe language installs

**Block third-party features:**
- Warn user if config uses non-official features
- Require explicit `--allow-third-party-features` flag

### Supply-Chain Risk Handling

| Component | Risk | Mitigation |
|-----------|------|------------|
| Base images | Arbitrary image pull | Log image + digest |
| Features | install.sh runs as root | Allowlist official only |
| Dockerfile | User-controlled build | Sandboxed in DinD |
| Build args | Can inject values | Sanitize special chars |

**Digest pinning (future consideration):**
- Allow specifying image digests in config
- Warn on `latest` tags
- Not MVP scope

---

## Discovery and Multi-Config Selection

### Discovery Rules Summary

```
WORKSPACE/
├── .devcontainer/
│   ├── devcontainer.json          # Default config
│   ├── python/
│   │   └── devcontainer.json      # Named: "python"
│   └── node/
│       └── devcontainer.json      # Named: "node"
└── .devcontainer.json             # Root config (alternative)
```

**Precedence:**
1. If `--config` specified, use that path exactly
2. If `.devcontainer/devcontainer.json` exists, use it (most common)
3. If `.devcontainer.json` exists (root), use it
4. If multiple named configs exist, require selection

### UX for Multi-Config Selection

**Interactive mode:**
```bash
cai devcontainer start
# Multiple configurations found:
# 1) python (Python development environment)
# 2) node (Node.js development environment)
# Select configuration [1-2]:
```

**Non-interactive mode:**
```bash
cai devcontainer start --config .devcontainer/python/devcontainer.json
# OR
cai devcontainer start --name python
```

**Link to fn-12-css workspace state:**
- Could store last-used devcontainer in workspace config
- Allow workspace to declare default devcontainer

---

## Maintenance Burden Estimate

### Spec Changes to Track

The devcontainer spec is versioned and evolves. Key areas:

| Area | Change Frequency | Impact |
|------|------------------|--------|
| New properties | ~quarterly | Low (ignore unknown) |
| Feature format | ~yearly | Medium (if supporting) |
| Variable syntax | Rare | Low |
| Merge algorithms | Rare | Medium |
| Compose support | Rare | High (if supporting) |

### Estimated Annual Maintenance

| Task | Effort |
|------|--------|
| Property additions | 2-4 days/year |
| Feature updates (if supporting) | 5-10 days/year |
| Security patches | 2-4 days/year |
| Bug fixes | 3-5 days/year |
| **Total** | **12-23 days/year** |

**Comparison with CLI wrapping:**
- CLI wrapping: ~2-5 days/year (mostly dependency updates)
- Direct parsing: 12-23 days/year

---

## Pros and Cons vs CLI Wrapping

### Pros of Direct Parsing

| Benefit | Explanation |
|---------|-------------|
| **Full control** | Complete control over every parsing decision |
| **No Node.js** | Avoids 150-200MB Node.js dependency |
| **Simpler security** | No black-box CLI behavior to worry about |
| **No interception gap** | Don't need to work around CLI re-reading files |
| **Faster startup** | No npm CLI overhead |
| **Pure shell** | Consistent with ContainAI's architecture |

### Cons of Direct Parsing

| Drawback | Explanation |
|----------|-------------|
| **Partial spec compliance** | Cannot fully implement all spec features |
| **No extends support** | Configuration inheritance not practical to implement |
| **Limited feature support** | Full feature system is 2-4 weeks to implement |
| **Variable edge cases** | May miss subtle variable expansion rules |
| **Higher maintenance** | Must track spec changes manually |
| **No Compose support** | Multi-container orchestration very complex |
| **Testing burden** | Must test against real-world configs |

### Critical Missing Capabilities

Without these, some devcontainers won't work:

1. **`extends` property** - Configuration inheritance
2. **Feature dependencies** - Features that require other features
3. **Image metadata merging** - `devcontainer.metadata` label processing
4. **Compose file parsing** - Multi-container setups
5. **Full variable expansion** - All `${...}` variants

---

## Comparison Summary

| Criterion | Direct Parsing | CLI Wrapping |
|-----------|---------------|--------------|
| **Spec compliance** | ~70-80% | ~100% |
| **Security control** | Maximum | Moderate |
| **Implementation effort** | 2-4 weeks (MVP) | 1-2 weeks |
| **Maintenance** | 12-23 days/year | 2-5 days/year |
| **Dependencies** | None (jq + python3 exist) | Node.js 150-200MB |
| **Feature support** | Basic (allowlist) | Full |
| **Extends support** | No | Yes |
| **Compose support** | No | Yes |
| **Image size impact** | +0 | +150-200MB |

---

## Recommendation

### Viability: MODERATE-HIGH for MVP, LOW for full spec

Direct parsing is viable for a subset of devcontainer configs:

**Good fit:**
- Simple image + commands configs (64% of repos)
- Configs without features or with allowlisted features
- Single-container configurations
- Environments where Node.js is undesirable

**Poor fit:**
- Configs using `extends`
- Complex feature dependencies
- Compose-based multi-container setups
- Configs requiring full variable expansion

### Recommended Implementation Path

If direct parsing is chosen:

**Phase 1: MVP (2 weeks)**
1. JSONC parsing with strip + jq
2. Basic variable expansion (5 common variables)
3. Image-based configs only (64% coverage)
4. No feature support initially
5. Security property filtering

**Phase 2: Basic Features (2 weeks)**
1. Feature allowlist (official only)
2. Hardcoded behavior for top 5 features
3. Simple metadata merging

**Phase 3: Extended Coverage (4 weeks)**
1. Dockerfile build support
2. More variable types
3. Feature options parsing
4. Multi-config selection UX

### Alternative: Hybrid Approach (Recommended)

Use direct parsing for simple cases, fall back to CLI for complex:

```bash
_parse_devcontainer() {
    local config="$1"

    # Check if config needs CLI
    if _config_needs_cli "$config"; then
        # Has extends, complex features, or compose
        _parse_via_cli "$config"
    else
        # Simple config - parse directly
        _parse_directly "$config"
    fi
}

_config_needs_cli() {
    local config="$1"
    jq -e '.extends or .dockerComposeFile or
           (.features | keys | any(startswith("ghcr.io/devcontainers/features") | not))' \
        "$config" >/dev/null 2>&1
}
```

This provides:
- Fast path for simple configs (64%+)
- Full compatibility via CLI fallback
- Gradual migration as direct parsing improves

---

## References

- [Dev Container JSON Reference](https://containers.dev/implementors/json_reference/)
- [Dev Container Specification](https://containers.dev/implementors/spec/)
- [Dev Container Features](https://containers.dev/implementors/features/)
- [json5 Python package](https://pypi.org/project/json5/)
- [jq Manual](https://stedolan.github.io/jq/manual/)
- [ContainAI Security Classification](security-classification.md)
- [ContainAI Usage Analysis](usage-analysis.md)
