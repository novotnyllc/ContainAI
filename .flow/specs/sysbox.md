# PRD: ContainAI Secure Sandboxed Agent Runtime (Docker Sandboxes + ECI-equivalent without Business)

**Document status:** Draft
**Last updated:** 2026-01-18
**Primary implementer:** Ralph
**Product area:** ContainAI runtime / launcher

## 1. Background and problem statement

ContainAI needs to run AI coding agents locally in a way that minimizes the risk of host compromise and credential exfiltration.

Docker has introduced **Docker Sandboxes** (invoked via `docker sandbox run`) as an **experimental** feature to run agents like Claude Code in an isolated containerized workspace, intended to preserve a familiar developer experience while reducing host exposure. Docker Sandboxes require Docker Desktop 4.50+ and an enabled experimental feature gate. ([Docker Documentation][1])

Docker also offers **Enhanced Container Isolation (ECI)**, which uses Linux user namespaces and the `sysbox-runc` runtime to increase isolation and block several unsafe behaviors (notably Docker socket mounts by default). However, ECI is **Docker Business-only**. ([Docker Documentation][2])

**Problem:** Many ContainAI users will not have Docker Desktop Business (and therefore cannot use ECI), but we still want a “most secure practical default” that:

* Always runs agents via Docker Sandboxes (mandatory).
* Uses Sysbox + user namespace isolation (ECI or an equivalent) whenever possible.
* Avoids giving the sandboxed agent access to the host Docker socket and host credentials by default.

## 2. Goals

### 2.1 Primary goals

1. **Sandbox is mandatory:** ContainAI must run agents via `docker sandbox run` (Docker Sandboxes) in all supported environments. ([Docker Documentation][3])
2. **Prefer ECI when available:** If Docker Desktop Business + ECI is available and enabled, ContainAI should use it and validate it is active. ([Docker Documentation][2])
3. **Provide an ECI-equivalent path without Business:** If ECI is not available, ContainAI should guide the user to (or automatically) set up a **separate, isolated Docker Engine (“Secure Engine”)** configured to:

   * run containers with `sysbox-runc`
   * enable user namespace remapping
   * optionally apply a daemon-wide seccomp profile
     and then run Docker Sandboxes against that engine via a Docker context.
4. **Prevent host Docker socket access:** ContainAI must ensure the agent container does **not** get host Docker socket access by default (no `--mount-docker-socket`) and must make enabling it an explicit, “unsafe” opt-in. Docker explicitly warns that mounting the Docker socket grants root-level control and can enable sandbox escape. ([Docker Documentation][4])
5. **Prevent host credential sharing by default:** ContainAI must not use `--credentials=host` by default (as it shares `~/.gitconfig`, `~/.ssh`, etc.). ([Docker Documentation][5])
6. **No mandatory Docker build:** “Docker build” / Docker-in-Docker are optional workflows. The default experience must not require Docker socket exposure.

### 2.2 Success metrics

* **Default safe run succeeds** for:

  * Docker Desktop Business with ECI enabled
  * Docker Desktop Personal/Pro without ECI, using Secure Engine
* In both paths, `docker sandbox run <agent>` completes successfully (agent starts).
* In the secure paths, runtime validation shows `sysbox-runc` is active where expected (ECI path and Secure Engine path). ([Docker Documentation][2])
* No host Docker socket mount occurs in default runs; no host credential sharing occurs in default runs.

## 3. Non-goals

* No Windows-native PowerShell UX. On Windows, ContainAI supports invocation from **WSL** only.
* No attempt to replicate every Docker Desktop Business control (e.g., org-wide Settings Management enforcement).
* No promise that this replaces enterprise security tooling. This is a developer-centric hardening approach.
* No requirement that every user can build containers inside the sandbox.

## 4. Target users and use cases

### 4.1 Personas

* **Individual developer (non-Business Docker Desktop)**: Wants safe local agent runs without changing their existing Docker Desktop environment.
* **Enterprise developer (Business Docker Desktop)**: Already has ECI available; wants ContainAI to validate and use it.
* **macOS developer using Docker Desktop**: Wants the same secure experience; may not have Business.

### 4.2 Core use cases

1. Run a sandboxed agent in a repo directory with minimal risk.
2. (Optional) Enable additional mounts (datasets, config) safely.
3. (Optional) Enable container builds in a way that does not mount the host Docker socket.

## 5. Key constraints and external dependencies

### 5.1 Docker Sandboxes requirements and operational constraints

* Docker Sandboxes are **experimental** and require **Docker Desktop 4.50+**. ([Docker Documentation][3])
* Users may need to enable the experimental feature gate; Docker’s documentation and blog note enabling “Experimental Feature” in Docker Desktop 4.50+. ([Docker][6])
* Docker notes that beta/experimental features are for testing/feedback and not supported for production usage. ([Docker Documentation][7])
* Sandboxes are **one per workspace**; config changes (env vars, mounts, socket access, credentials mode) require removing/recreating the sandbox. ([Docker Documentation][4])

### 5.2 ECI constraints

* ECI requires **Docker Business** and Docker Desktop 4.13+. ([Docker Documentation][2])
* When ECI is enabled:

  * containers use user namespaces (UID mapping shows root mapped to an unprivileged UID range) ([Docker Documentation][2])
  * runtime becomes `sysbox-runc` (validated via `docker inspect`) ([Docker Documentation][2])
  * Docker socket mounts are blocked by default unless exceptions are configured ([Docker Documentation][2])

### 5.3 Seccomp configuration

* Docker Engine (`dockerd`) supports a daemon-wide `--seccomp-profile` (builtin by default). ([Docker Documentation][8])
* Docker’s default seccomp profile is intended as a “sane default” baseline and disables a subset of syscalls for security. ([Docker Documentation][9])

## 6. Product requirements

## 6.1 Functional requirements

### FR-1: Mandatory sandbox execution

* ContainAI must run agents via:

  * `docker sandbox run <agent>` (Claude Code, Gemini CLI, etc.), not via `docker run`. ([Docker Documentation][3])

### FR-2: “Doctor” and guided remediation

Implement `containai doctor` that performs:

1. **Verify Docker Desktop + Sandboxes availability**

   * Detect Docker Desktop version ≥ 4.50.
   * Detect that `docker sandbox` CLI plugin is present (e.g., `docker sandbox version`).
   * Detect that Sandboxes feature is enabled (handle the common “beta features disabled by admin” case and provide remediation messaging). ([Docker Documentation][10])

2. **Detect ECI**

   * Run ECI validation per Docker guidance:

     * Start an ephemeral container and check `/proc/self/uid_map` mapping. ([Docker Documentation][2])
     * Check runtime via `docker inspect --format '{{.HostConfig.Runtime}}' ...` expecting `sysbox-runc` under ECI. ([Docker Documentation][2])

3. **Decide runtime strategy**

   * If ECI is active: select “ECI path.”
   * Else: select “Secure Engine path” and prompt to install/enable it (or auto-install if permitted).

### FR-3: Secure Engine (ECI-equivalent) setup without Business

Implement `containai install secure-engine` that creates a **separate Docker Engine + context** without altering the user’s default Docker Desktop engine.

Secure Engine requirements:

* Runs on Linux (WSL distro on Windows; dedicated Linux VM on macOS).
* Configures:

  * Sysbox runtime available and used (default runtime or per-run runtime selection).
  * User namespace remapping enabled.
  * Optional daemon-wide seccomp profile.
* Creates a Docker context: `containai-secure` that points at the Secure Engine endpoint.
* Does not modify the user’s default Docker context or Docker Desktop settings.

### FR-4: Safe defaults for sandbox execution

Implement `containai run` as a wrapper around Docker Sandboxes.

Default behavior:

* Uses `docker sandbox run` with:

  * `--credentials=none`; **never** `host` by default. ([Docker Documentation][5])
  * No `--mount-docker-socket`. ([Docker Documentation][4])
  * No additional volume mounts beyond the workspace mount, unless explicitly allowlisted.

Context selection:

* If ECI active: run on the default Docker Desktop context.
* If ECI not active: run using `docker --context containai-secure sandbox run ...`.

### FR-5: Explicit unsafe opt-ins

ContainAI may support the following flags, but they must be explicit and gated:

* `--allow-host-credentials`

  * Enables `docker sandbox run --credentials=host` and prints a strong warning that it shares host credentials including `~/.ssh`. ([Docker Documentation][5])
  * Requires `--i-understand-this-exposes-host-credentials` (or similar “typed acknowledgement”) to proceed.

* `--allow-host-docker-socket`

  * Enables `docker sandbox run --mount-docker-socket`, with warnings that Docker socket mount provides root-level daemon access and can allow sandbox escape. ([Docker Documentation][4])
  * Requires typed acknowledgement and an additional confirmation that the workspace is trusted.

### FR-6: Optional build workflows without host Docker socket

Provide optional capability for builds without mounting the host Docker socket, using one of these approaches:

* **Option A (preferred): Nested Docker inside the Sysbox sandbox**

  * If the container runtime is Sysbox (`sysbox-runc`), allow ContainAI to start an inner `dockerd` inside the sandbox (Docker-in-Docker without host socket mount), gated behind `--enable-nested-docker`.
  * This remains optional; default is off.

* **Option B: Host-side build**

  * Provide guidance or helper commands that run builds outside the sandbox and only run the agent sandbox against the working tree.

### FR-7: Reset / cleanup

Implement:

* `containai sandbox reset` to remove the current workspace sandbox (`docker sandbox rm ...`) so configuration changes can take effect. ([Docker Documentation][4])
* `containai sandbox clear-credentials` to remove sandbox credential volumes when applicable (agent-specific), aligned with Docker troubleshooting guidance. ([Docker Documentation][10])

## 6.2 Non-functional requirements

### NFR-1: Security posture

* Default execution must not expose:

  * host Docker socket
  * host SSH keys / host credential stores
* The system must keep “unsafe toggles” off by default and make them frictionful to enable.

### NFR-2: Minimal environment disruption

* Do not overwrite the user’s default Docker context.
* Do not require uninstalling Docker Desktop.
* Secure Engine uses separate data-root and configuration.

### NFR-3: Deterministic, inspectable behavior

* `containai doctor` must provide concrete commands and outputs that prove:

  * sandbox availability
  * ECI detection
  * runtime selection
  * selected Docker context

### NFR-4: Portability

* Must support:

  * Windows (WSL invocation only)
  * macOS (Docker Desktop + VM-based Secure Engine option)
* Linux host support is out of scope unless explicitly added later.

## 7. UX and CLI specification

### 7.1 Commands

* `containai doctor`

  * Outputs:

    * Docker Desktop version + sandbox availability
    * whether Sandboxes is enabled (and remediation steps if not)
    * ECI detection results (uid_map + runtime check)
    * recommended path: ECI vs Secure Engine
* `containai install secure-engine`

  * Installs and configures the isolated engine + Docker context
* `containai run [--agent claude|gemini] [--workspace <path>] [-- <agent args>]`

  * Always uses `docker sandbox run`
  * Chooses Docker context automatically
* `containai sandbox reset`

  * Removes sandbox for current workspace so changes apply ([Docker Documentation][4])
* `containai sandbox clear-credentials`

  * Removes the relevant sandbox credential volume if used ([Docker Documentation][10])

### 7.2 Configuration file

* File: `.containai/config.toml` (repo-local) and/or `~/.config/containai/config.toml` (user-global)
* Key settings:

  * `agent = "claude"`
  * `credentials_mode = "sandbox"` (disallow “host” unless explicitly overridden)
  * `allow_extra_mounts = false`
  * `secure_engine.enabled = true|false|auto`
  * `secure_engine.context_name = "containai-secure"`
  * `secure_engine.seccomp_profile = "/path/to/profile.json" (optional)`
  * `danger.allow_host_credentials = false`
  * `danger.allow_host_docker_socket = false`

## 8. Secure Engine design

## 8.1 Windows (WSL) approach

* Create a dedicated WSL distro or a dedicated directory layout inside an existing WSL distro for Secure Engine assets.
* Run dockerd as a user-managed process (systemd may not exist) and expose the engine via:

  * unix socket in a known path, or
  * localhost TCP bound only to loopback (with TLS optional for later)
* Configure `daemon.json` with:

  * `default-runtime: "sysbox-runc"` (or enforce runtime via ContainAI run invocation)
  * `userns-remap: "default"`
  * optional `seccomp-profile: "<path>"` (daemon-wide) ([Docker Documentation][8])
* Create Docker context `containai-secure` pointing to this daemon.

## 8.2 macOS approach

Because Sysbox is a Linux runtime, implement Secure Engine using a dedicated Linux VM and keep Docker Desktop untouched:

* Provision a Linux VM (e.g., Lima-based VM) with:

  * Docker Engine
  * Sysbox runtime installed/configured
  * userns-remap enabled
  * optional daemon-wide seccomp profile
* Expose Docker Engine to macOS via SSH-based Docker context or TCP endpoint restricted to localhost.
* Create Docker context `containai-secure` pointing to this VM.

**Important:** Docker Sandboxes requires Docker Desktop, so macOS users still need Docker Desktop installed/enabled for `docker sandbox` feature and CLI plugin availability. ([Docker Documentation][3])
(ContainAI’s responsibility is to ensure sandboxes run against the correct context once the feature exists.)

## 9. Security model

### 9.1 Threats addressed

* Accidental or malicious agent executing code that exfiltrates host secrets.
* Agent gaining control of Docker daemon via `/var/run/docker.sock`.
* Agent using host credential material to access/push to GitHub.

### 9.2 Key controls

* Always run within Docker Sandboxes. ([Docker Documentation][1])
* No host Docker socket mounting by default; explicit warnings if enabled. ([Docker Documentation][4])
* No host credential sharing by default; disallow `--credentials=host` unless explicitly opted in. ([Docker Documentation][5])
* Prefer Sysbox + user namespaces via ECI where possible; else via Secure Engine. ([Docker Documentation][2])
* Optional daemon-wide seccomp profile on Secure Engine (defense-in-depth). ([Docker Documentation][8])

### 9.3 Verification commands (used by `containai doctor`)

* Verify sandbox is present:

  * `docker sandbox version`
* Verify ECI userns mapping:

  * `docker run --rm alpine cat /proc/self/uid_map` ([Docker Documentation][2])
* Verify runtime:

  * `docker inspect --format '{{.HostConfig.Runtime}}' <container>` expecting `sysbox-runc` when ECI active ([Docker Documentation][2])

## 10. Edge cases and failure modes

1. **Sandboxes command missing**

   * Error: “docker: 'sandbox' is not a docker command”
   * Remedy: instruct user to upgrade Docker Desktop to 4.50+ and enable experimental feature. ([Docker Documentation][3])

2. **Sandboxes disabled by admin policy**

   * Docker docs indicate beta features can be disabled/locked via settings management; ContainAI must surface this clearly and provide next steps. ([Docker Documentation][10])

3. **User toggles unsafe flags but sandbox doesn’t reflect changes**

   * Sandboxes require removal/recreation to pick up changes to env vars, mounts, docker socket access, credentials. ContainAI must either:

     * auto-reset sandbox, or
     * instruct user to run `containai sandbox reset`. ([Docker Documentation][4])

4. **ECI present but not enabled**

   * ContainAI should detect and provide exact steps to enable (requires Business). ([Docker Documentation][2])

5. **Secure Engine installed but `docker sandbox run` does not honor context**

   * Treat as a critical spike item; if it fails, ContainAI must fall back to:

     * using ECI-only (Business path), and
     * providing a non-sandboxed hardened `docker run` alternative only if you decide to relax the “sandbox mandatory” rule (not currently allowed by this PRD).

## 11. Implementation plan (epics)

### Epic A: Sandbox-first launcher

* A1: Implement `containai run` wrapper
* A2: Enforce safe defaults (no host creds, no docker socket)
* A3: Implement unsafe opt-ins with typed acknowledgements
* A4: Implement `containai sandbox reset` and `clear-credentials`

### Epic B: Doctor and decision engine

* B1: Implement `containai doctor` capability detection (Desktop version, sandbox command, feature gate messaging)
* B2: Implement ECI detection (uid_map + runtime check) ([Docker Documentation][2])
* B3: Context selection logic + output formatting

### Epic C: Secure Engine without Business

* C1: WSL Secure Engine provisioning + context creation
* C2: macOS VM-based Secure Engine provisioning + context creation
* C3: Optional daemon seccomp profile support ([Docker Documentation][8])
* C4: Runtime validation + regression tests

## 12. Acceptance criteria

1. On Docker Desktop 4.50+ with Sandboxes enabled, `containai run --agent claude` launches Claude via `docker sandbox run`. ([Docker Documentation][3])
2. On Docker Desktop Business with ECI enabled:

   * `containai doctor` reports ECI active using uid_map + runtime checks. ([Docker Documentation][2])
   * Default run does not mount Docker socket.
3. On non-Business systems:

   * `containai install secure-engine` creates `containai-secure` context and engine.
   * `containai run` uses the Secure Engine context.
   * Default run does not share host credentials and does not mount host Docker socket.
4. Attempting to enable `--allow-host-docker-socket` triggers warnings and requires explicit acknowledgement; same for host credentials. ([Docker Documentation][4])

## 13. Open questions to resolve early (spike items)

1. Does `docker sandbox` reliably respect `--context` / `DOCKER_CONTEXT` in all target environments (Windows WSL + macOS)?
2. What is the minimal Secure Engine packaging that is least disruptive on macOS (Lima vs other)?
3. Compatibility matrix: Sysbox + userns-remap + daemon seccomp profile + Docker Sandboxes.

---


[1]: https://docs.docker.com/ai/sandboxes/ "https://docs.docker.com/ai/sandboxes/"
[2]: https://docs.docker.com/enterprise/security/hardened-desktop/enhanced-container-isolation/enable-eci/ "https://docs.docker.com/enterprise/security/hardened-desktop/enhanced-container-isolation/enable-eci/"
[3]: https://docs.docker.com/ai/sandboxes/get-started/ "https://docs.docker.com/ai/sandboxes/get-started/"
[4]: https://docs.docker.com/ai/sandboxes/advanced-config/ "https://docs.docker.com/ai/sandboxes/advanced-config/"
[5]: https://docs.docker.com/reference/cli/docker/sandbox/run/ "https://docs.docker.com/reference/cli/docker/sandbox/run/"
[6]: https://www.docker.com/blog/aws-reinvent-kiro-docker-sandboxes-mcp-catalog/ "https://www.docker.com/blog/aws-reinvent-kiro-docker-sandboxes-mcp-catalog/"
[7]: https://docs.docker.com/desktop/settings-and-maintenance/settings/ "https://docs.docker.com/desktop/settings-and-maintenance/settings/"
[8]: https://docs.docker.com/reference/cli/dockerd/ "https://docs.docker.com/reference/cli/dockerd/"
[9]: https://docs.docker.com/engine/security/seccomp/ "https://docs.docker.com/engine/security/seccomp/"
[10]: https://docs.docker.com/ai/sandboxes/troubleshooting/ "https://docs.docker.com/ai/sandboxes/troubleshooting/"
