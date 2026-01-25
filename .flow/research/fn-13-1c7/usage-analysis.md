# Devcontainer Usage Analysis

Analysis of real-world devcontainer.json configurations to understand usage patterns and estimate compatibility with ContainAI's security model.

## Methodology

### Selection Criteria (Stratified Sampling)

**Sample strategy:**
- Stratified by ecosystem: JavaScript/TypeScript, Python, Go, Rust, Java
- Stratified by popularity: High stars (>10k), medium stars (1k-10k), and DevContainer tooling repos
- Org caps: max 2-3 repos per org for most orgs; Microsoft/devcontainers allowed higher counts as reference implementations
- Monorepo handling: Each `.devcontainer/devcontainer.json` counted once per repo

**Note on analysis baseline:** 51 repos were sampled; 1 failed parsing (JetBrains/devcontainers-examples). All frequency statistics use N=50 (successfully parsed configs).

**Sources:**
- GitHub code search API: `filename:devcontainer.json`
- Known orgs with quality devcontainer examples: microsoft, devcontainers, vercel, google, aws, kubernetes-sigs
- Curated repos from devcontainer-related GitHub topics

### JSONC Parsing Approach

1. Strip `//` single-line comments (excluding URLs)
2. Strip `/* */` multi-line comments
3. Remove trailing commas before `}` or `]`
4. Parse with standard JSON parser

**Parse success rate:** 98% (50/51 files)

**Parse failure:** JetBrains/devcontainers-examples - root file contains multiple JSON objects (monorepo index)

### Data Collection Date

January 2026

---

## Sample Composition

| Ecosystem | Count | Percentage |
|-----------|-------|------------|
| JavaScript/TypeScript | 29 | 56.9% |
| Go | 10 | 19.6% |
| Python | 7 | 13.7% |
| Rust | 4 | 7.8% |
| Java | 1 | 2.0% |
| **Total** | **51** | **100%** |

**Note:** JavaScript/TypeScript is overrepresented because devcontainers originated in the VS Code ecosystem. This reflects real-world adoption patterns.

### Repos Analyzed

<details>
<summary>Full repo list (51 repos)</summary>

**High stars (>10k):**
- microsoft/vscode
- microsoft/TypeScript
- vercel/next.js
- vercel/turborepo
- facebook/docusaurus
- moby/moby
- etcd-io/etcd
- denoland/deno
- tauri-apps/tauri
- cilium/cilium
- pulumi/pulumi

**Medium stars (1k-10k):**
- microsoft/AI-For-Beginners
- microsoft/Web-Dev-For-Beginners
- microsoft/ML-For-Beginners
- microsoft/SynapseML
- microsoft/RulesEngine
- microsoft/TaskWeaver
- langchain-ai/langchain
- kubernetes-sigs/cluster-api-provider-aws
- quarkusio/quarkus
- containerd/containerd
- loft-sh/devpod
- coder/envbuilder
- astral-sh/ruff
- python/cpython
- numpy/numpy
- scikit-learn/scikit-learn
- pallets/flask
- hashicorp/terraform-provider-aws

**DevContainer tooling (reference configs):**
- devcontainers/templates
- devcontainers/features
- devcontainers/cli
- devcontainers/images
- devcontainers/template-starter
- devcontainers/feature-starter
- JetBrains/devcontainers-examples

**Cloud provider SDKs:**
- Azure/azure-sdk-for-python
- Azure/azure-sdk-for-js
- Azure/azure-cli
- aws/aws-cdk
- aws/aws-parallelcluster-cookbook
- aws/aws-pdk
- google/android-fhir
- google/bumble
- google/chrome-ssh-agent
- google/crosvm
- google/kf

**GitHub templates:**
- github/codespaces-react
- github/codespaces-jupyter

**Rust ecosystem:**
- rust-lang/a-mir-formality
- rust-lang/rust-project-goals

</details>

---

## Property Frequency Analysis

### Top 25 Properties

| Property | Count | Percentage | Security Category |
|----------|-------|------------|-------------------|
| `customizations` | 36 | 72.0% | SAFE |
| `name` | 34 | 68.0% | SAFE |
| `features` | 34 | 68.0% | WARN* |
| `postCreateCommand` | 32 | 64.0% | SAFE (container) |
| `image` | 32 | 64.0% | SAFE |
| `remoteUser` | 18 | 36.0% | FILTERED |
| `build` | 12 | 24.0% | FILTERED |
| `runArgs` | 10 | 20.0% | FILTERED |
| `mounts` | 9 | 18.0% | FILTERED |
| `hostRequirements` | 7 | 14.0% | SAFE |
| `workspaceFolder` | 7 | 14.0% | FILTERED |
| `onCreateCommand` | 7 | 14.0% | SAFE (container) |
| `forwardPorts` | 6 | 12.0% | SAFE |
| `overrideCommand` | 5 | 10.0% | WARN |
| `workspaceMount` | 5 | 10.0% | FILTERED |
| `updateContentCommand` | 5 | 10.0% | SAFE (container) |
| `settings` | 4 | 8.0% | SAFE (deprecated) |
| `extensions` | 4 | 8.0% | SAFE (deprecated) |
| `containerEnv` | 3 | 6.0% | SAFE |
| `privileged` | 3 | 6.0% | BLOCKED |
| `waitFor` | 3 | 6.0% | SAFE |
| `dockerFile` | 3 | 6.0% | FILTERED |
| `portsAttributes` | 2 | 4.0% | SAFE |
| `postAttachCommand` | 2 | 4.0% | SAFE |
| `postStartCommand` | 2 | 4.0% | SAFE |

*Features run `install.sh` during build - security depends on allowlist policy

---

## Lifecycle Commands Usage

| Command | Count | Percentage | Execution Context |
|---------|-------|------------|-------------------|
| `postCreateCommand` | 32 | 64.0% | Inside container |
| `onCreateCommand` | 7 | 14.0% | Inside container |
| `updateContentCommand` | 5 | 10.0% | Inside container |
| `postStartCommand` | 2 | 4.0% | Inside container |
| `postAttachCommand` | 2 | 4.0% | Inside container |
| **`initializeCommand`** | **0** | **0.0%** | **HOST machine** |

### Key Finding: initializeCommand

**`initializeCommand` was NOT used in any of the 50 successfully parsed repositories.**

This is significant because:
1. `initializeCommand` is the most dangerous property (runs on host before container creation)
2. Its absence suggests most projects don't need host-side setup
3. ContainAI can block this property with minimal impact on compatibility

**postCreateCommand patterns:**
- String (single command): 30 repos (94%)
- Object (named commands): 2 repos (6%)

---

## Security-Relevant Properties

| Property | Count | Percentage | Risk Level |
|----------|-------|------------|------------|
| `mounts` | 9 | 18.0% | Medium |
| `runArgs` with `--privileged` | 4 | 8.0% | High |
| `runArgs` with `--cap-add` | 4 | 8.0% | Medium |
| `privileged: true` | 3 | 6.0% | High |
| `initializeCommand` | 0 | 0.0% | Critical |
| `securityOpt` | 0 | 0.0% | Medium |
| `capAdd` | 0 | 0.0% | Medium |

### Privileged Mode Users (7 repos, 14%)

| Repository | Reason | Use Case |
|------------|--------|----------|
| microsoft/vscode | `privileged: true` | VNC/GUI testing |
| loft-sh/devpod | `privileged: true` | Docker-in-Docker |
| aws/aws-pdk | `privileged: true` | Docker socket access |
| Azure/azure-sdk-for-python | `--privileged` runArgs | Testing with containers |
| Azure/azure-sdk-for-js | `--privileged` runArgs | Testing with containers |
| containerd/containerd | `--privileged` runArgs | Container runtime testing |
| moby/moby | `--privileged` runArgs | Docker development |

**Pattern:** Privileged mode is used primarily for:
1. Docker-in-Docker scenarios (container runtime testing)
2. GUI/VNC access for visual testing
3. Low-level container/kernel development

### Mount Patterns (9 repos, 18%)

| Mount Type | Example | Risk |
|------------|---------|------|
| Named volumes | `source=vscode-dev,target=/vscode-dev,type=volume` | Low |
| Bind cache dirs | `source=${localWorkspaceFolder}/.devcontainer/cache,target=/home/vscode/.cache` | Low |
| Docker socket | `source=/var/run/docker.sock,target=/var/run/docker.sock` | HIGH |
| Kernel modules | `source=/lib/modules,target=/lib/modules,readonly` | Medium |
| Cargo cache | `source=devcontainer-cargo-cache-${devcontainerId}` | Low |

**Docker socket mounts:** 3 repos (Azure SDK, aws-pdk) - major security concern

### runArgs Patterns

| Argument | Count | Repos |
|----------|-------|-------|
| `--cap-add` | 4 | turborepo, azure-sdk-*, deno |
| `--security-opt` | 4 | turborepo, azure-sdk-*, deno |
| `--privileged` | 4 | azure-sdk-*, containerd, moby |
| `--volume` | 2 | containerd |
| `--init` | 1 | ML-For-Beginners |
| `--env-file` | 1 | azure-cli |
| `--sysctl` | 1 | cilium |
| `--pids-limit` | 1 | crosvm |

---

## Features Usage (Top 15)

| Feature | Count | Security Note |
|---------|-------|---------------|
| `ghcr.io/devcontainers/features/docker-in-docker:2` | 11 | Requires privileged or DinD setup |
| `ghcr.io/devcontainers/features/github-cli:1` | 8 | SAFE - just installs gh CLI |
| `ghcr.io/devcontainers/features/go:1` | 3 | SAFE - installs Go |
| `ghcr.io/devcontainers/features/git:1` | 3 | SAFE - installs git |
| `ghcr.io/devcontainers/features/rust:1` | 2 | SAFE - installs Rust |
| `ghcr.io/devcontainers/features/azure-cli:1` | 2 | SAFE - installs az CLI |
| `ghcr.io/devcontainers/features/node:1` | 2 | SAFE - installs Node.js |
| `ghcr.io/devcontainers/features/common-utils:2` | 2 | SAFE - common utilities |

### Docker-in-Docker Feature

**22% of repos** (11/50) use the docker-in-docker feature. This is significant because:
1. It's the most popular feature
2. It requires special handling (elevated privileges or nested containers)
3. ContainAI's Sysbox runtime naturally supports this without `--privileged`

---

## Build Patterns

| Pattern | Count | Percentage |
|---------|-------|------------|
| Image only | 32 | 64.0% |
| Dockerfile build | 15 | 30.0% |
| Build with context | 5 | 10.0% |
| Docker Compose | 1 | 2.0% |

### Base Images (Top 10)

| Image | Count |
|-------|-------|
| `mcr.microsoft.com/devcontainers/*` | 26 (52%) |
| `ghcr.io/*` | 2 |
| `mcr.microsoft.com/vscode/*` | 1 |
| Custom/org-specific | 3 |

**Key insight:** 52% of configs use official Microsoft devcontainer images, which are:
- Well-maintained and regularly updated
- Include common development tools
- Compatible with features system

---

## workspaceMount and workspaceFolder Patterns

### workspaceMount (5 repos)

| Repository | Mount Pattern |
|------------|---------------|
| Azure/azure-sdk-for-python | `${localWorkspaceFolder}` → `/home/codespace/workspace` |
| Azure/azure-sdk-for-js | `${localWorkspaceFolder}` → `/home/codespace/workspace` |
| containerd/containerd | `${localWorkspaceFolder}` → `/go/src/github.com/containerd/containerd` |
| moby/moby | `${localWorkspaceFolder}` → `/go/src/github.com/docker/docker` |
| cilium/cilium | `${localWorkspaceFolder}` → `/go/src/github.com/cilium/cilium` |

**Pattern:** Go projects often mount to `$GOPATH/src/` for module compatibility.

### workspaceFolder Defaults

| Pattern | Count |
|---------|-------|
| `/workspaces/<project>` | Most common (default) |
| `/home/codespace/workspace` | 2 (Azure SDKs) |
| `$GOPATH/src/github.com/<org>/<repo>` | 3 (Go projects) |

---

## Safe Subset Compatibility Estimate

### Criteria for "Safe Subset"

A devcontainer configuration is considered "safe" for ContainAI if it:
1. Does NOT use `initializeCommand` (host-side execution)
2. Does NOT use `privileged: true`
3. Does NOT use `--privileged` in runArgs
4. Does NOT mount Docker socket or host filesystem
5. Does NOT use `capAdd` or privileged capabilities

### Compatibility Analysis

| Criterion | Configs Affected | Compatible |
|-----------|------------------|------------|
| No `initializeCommand` | 0 blocked | 50/50 (100%) |
| No `privileged` property | 3 blocked | 47/50 (94%) |
| No `--privileged` runArgs | 4 blocked | 46/50 (92%) |
| No `--cap-add` runArgs | 4 blocked | 46/50 (92%) |
| No dangerous mounts | 3 blocked (docker.sock) | 47/50 (94%) |

### Estimated Compatibility

**Conservative estimate (blocking only the most dangerous):**
- Block `initializeCommand` only: **100% compatible** (0 repos affected)
- Block `privileged` modes: **86% compatible** (7 repos need privileged)

**Strict estimate (maximum security):**
- Block `initializeCommand` + `privileged` + dangerous mounts: **~82-86% compatible**

### Repos Requiring Special Handling

These 7 repos (14%) would need privileged mode or special accommodation:
1. microsoft/vscode - GUI testing
2. loft-sh/devpod - Docker-in-Docker
3. aws/aws-pdk - Docker socket
4. Azure/azure-sdk-for-python - Container testing
5. Azure/azure-sdk-for-js - Container testing
6. containerd/containerd - Runtime development
7. moby/moby - Docker development

**Mitigation:** ContainAI's Sysbox runtime provides Docker-in-Docker without `--privileged`, which may enable some of these use cases.

---

## Notable Patterns and Examples

### Pattern 1: Simple Image + Features (Most Common)
```json
{
  "name": "Project Name",
  "image": "mcr.microsoft.com/devcontainers/typescript-node:22",
  "features": {
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },
  "postCreateCommand": "npm install",
  "customizations": {
    "vscode": {
      "extensions": ["dbaeumer.vscode-eslint"]
    }
  }
}
```
**Compatibility:** SAFE - works with ContainAI unchanged

### Pattern 2: Dockerfile Build
```json
{
  "name": "Custom Build",
  "build": {
    "dockerfile": "Dockerfile"
  },
  "postCreateCommand": "./scripts/setup.sh"
}
```
**Compatibility:** FILTERED - ContainAI controls build location (DinD)

### Pattern 3: Docker-in-Docker
```json
{
  "name": "Container Development",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {}
  }
}
```
**Compatibility:** WARN - works in Sysbox without privileged, but needs DinD feature allowlist

### Pattern 4: Privileged Mode (Rare)
```json
{
  "name": "Kernel Development",
  "privileged": true,
  "mounts": [
    {"source": "/var/run/docker.sock", "target": "/var/run/docker.sock", "type": "bind"}
  ]
}
```
**Compatibility:** BLOCKED - requires explicit user approval or rejection

---

## Recommendations for ContainAI

### 1. Block with Zero Impact
- `initializeCommand` - 0% of repos use it

### 2. Block with Minimal Impact (~6% affected)
- `privileged: true`
- `--privileged` in runArgs

### 3. Filter/Transform
- `mounts` - allow named volumes, block bind mounts to host paths
- `workspaceMount` - remap to ContainAI's workspace model
- `runArgs` - allowlist safe options, block dangerous ones
- `remoteUser` - map to ContainAI's agent user

### 4. Allow with Warning
- `features` with docker-in-docker - works in Sysbox but warn user
- `overrideCommand` - conflicts with ContainAI's systemd model

### 5. Pass Through Unchanged
- `name`, `customizations`, `postCreateCommand`, `image`
- `forwardPorts`, `portsAttributes`, `containerEnv`
- All lifecycle commands except `initializeCommand`

---

## Appendix: Raw Data

### Repos by Organization

| Organization | Count | Repos |
|--------------|-------|-------|
| microsoft | 8 | vscode, TypeScript, AI-For-Beginners, Web-Dev-For-Beginners, ML-For-Beginners, SynapseML, RulesEngine, TaskWeaver |
| devcontainers | 6 | templates, features, cli, images, template-starter, feature-starter |
| google | 5 | android-fhir, bumble, chrome-ssh-agent, crosvm, kf |
| Azure | 3 | azure-sdk-for-python, azure-sdk-for-js, azure-cli |
| aws | 3 | aws-cdk, aws-parallelcluster-cookbook, aws-pdk |
| vercel | 2 | next.js, turborepo |
| kubernetes-sigs | 1 | cluster-api-provider-aws |
| (others) | 23 | Various single-repo orgs |

### Data Collection Commands

```bash
# GitHub API code search
gh api "search/code?q=filename:devcontainer.json+org:ORG&per_page=50"

# Fetch file content
gh api "repos/OWNER/REPO/contents/.devcontainer/devcontainer.json" --jq '.content' | base64 -d

# JSONC parsing (Python - illustrative, not production)
import re, json
text = re.sub(r'/\*[\s\S]*?\*/', '', text)           # strip block comments
text = re.sub(r'(?<![:\"])//.*?(?=\n|$)', '', text)  # strip line comments (preserve URLs)
text = re.sub(r',(\s*[}\]])', r'\1', text)           # remove trailing commas
data = json.loads(text)
```
