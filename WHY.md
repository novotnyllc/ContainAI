# Why ContainAI Exists

AI agents have gone from novelty to daily habit: GitHub Copilot, Cursor, Claude, Codex, Gemini CLI, and others are now woven into how many of us write software. But as soon as you move beyond “inline suggestions in an editor” and give an AI agent real power—running commands, installing packages, editing lots of files—you’re hit with a hard set of questions:

* How do I stop an agent from trashing my machine or repo?
* How do I let multiple agents work on the same codebase without stepping on each other?
* How do I give them the tools and credentials they need *without* spraying secrets around?
* How do I review and merge what they did like a normal teammate?

ContainAI exists to answer those questions with a practical, security-first, developer-friendly workflow.

The short version: it lets you run one or more “unrestricted” agents per repository, each inside its own hardened container and Git branch, integrated with your existing tools (.NET, VS Code, GitHub, etc.), with a security model that assumes the agent is untrusted and keeps your host, your secrets, and your main branches safe.

This file explains why the project exists and how it differs from other tools in the same space.

---

## The Problems We’re Solving

### 1. Unsafe “unrestricted” agents

Once an AI agent can run shell commands, install dependencies, and modify files arbitrarily, it’s very easy to end up with:

* `rm -rf` in the wrong place
* broken dev environments from conflicting package installs
* sensitive files accidentally uploaded or logged

Running those agents directly on your laptop or CI host is a bad idea. ContainAI assumes the agent is *malicious or buggy by default* and contains it accordingly.

### 2. Multi-agent chaos on a single repo

As soon as you try to run more than one agent against the same repository you hit:

* conflicting edits
* clobbered or half-applied migrations
* unreviewable mixtures of machine and human changes

ContainAI’ answer is “one agent, one container, one Git branch”. Each agent gets:

* its own isolated filesystem view of your repo
* its own branch where it commits changes
* its own runtime environment and toolchain

Agents can work in parallel on the same repo without colliding. You then review and merge like you would for human contributors.

### 3. Secrets, credentials, and code privacy

Agents need credentials to call APIs (GitHub, OpenAI, Azure, etc.) and sometimes need access to private repositories or services. Hard-coding keys in containers or checking them into repos is an obvious non-starter.

ContainAI:

* reuses the auth you already have on the host (OAuth tokens, CLI logins, etc.),
* never bakes secrets into images, and
* never writes secrets into the repo or container filesystem.

Instead, it uses a host-side broker and “capability tokens” that can be redeemed inside the container by small stubs, only in memory, only for as long as needed. The agent never sees raw API keys; it just gets to call tools that internally talk to the broker.

### 4. Real workflows, not toy demos

Lots of AI agent demos assume:

* a throwaway toy repo,
* Linux-only,
* Python-only,
* no IDE, no existing CI, no existing tooling.

ContainAI is explicitly designed to fit real developer workflows:

* works on Windows (via WSL2), macOS, and Linux
* containers come preloaded with modern .NET SDKs (8/9/10), PowerShell, Node, and common CLIs
* one-shot CLI launchers (`run-copilot`, `run-codex`, etc.) you can run in any repo
* VS Code Dev Containers integration so you can attach to an agent’s container and inspect its workspace live
* tmux-based sessions so you can detach/resume long-running agents

You don’t have to swap editors, rearchitect your stack, or run everything in someone else’s cloud to get value.

---

## What ContainAI Actually Does

At a high level, ContainAI gives each agent:

* A **dedicated Docker container** running as a non-root user with dropped capabilities, seccomp, AppArmor, resource limits, and a minimal, hardened surface.
* A **dedicated Git branch** cloned from your repo. The agent edits code there and commits on that branch only.
* A **standardized toolchain** (especially for .NET) so `dotnet build/test`, language servers, and other tooling “just work”.
* A **safe way to use secrets** via a host-side broker and in-container stubs that redeem capability tokens into temporary in-memory credentials.
* **Optional network modes**:

  * “allow all” for experimentation,
  * “offline” (no outbound network),
  * “proxy-logged” (all egress through a Squid proxy with whitelists and logs).

The host side (trusted zone) handles Docker, the broker, and integrity checks. The agent side (untrusted zone) is everything running inside the container. The design assumes the untrusted side can’t be relied on for anything except producing code that you will review.

---

## How We Compare to Other Tools

There are now a few projects in roughly the same space. The fact they exist is good; it validates that devs want this pattern. ContainAI exists because we wanted a solution with a different set of priorities.

### Dagger’s Container-Use

Dagger’s “container-use” is a well-known tool that:

* gives each AI agent its own container
* ties them to Git branches
* integrates nicely with agents like Cursor and Claude
* emphasizes real-time logging and broad compatibility

It’s fantastic if you mainly want “parallel agents in containers” with strong Go/DevOps ergonomics.

**Where ContainAI differs:**

* **Security depth over pure convenience**
  Container-Use focuses on ease of use and broad compatibility. ContainAI pushes harder on *defense-in-depth*:

  * mandatory non-root containers with dropped capabilities
  * strict seccomp and AppArmor profiles
  * an explicit threat model that treats the agent as hostile
  * immutable install + SBOM-based integrity checks for core scripts and binaries

* **Secret handling architecture**
  Container-Use leans on environment and config for API keys. ContainAI uses a **capability token + broker** model:

  * secrets live on the host in a broker
  * containers get sealed tokens and redeem them via stubs
  * secrets are never written to disk inside the container or repo

* **.NET-first experience**
  Container-Use is Go-based and naturally oriented toward typical container-native stacks (Python/JS/etc.). ContainAI makes .NET a first-class citizen:

  * images preloaded with .NET 8/9/10 and workloads (ASP.NET, MAUI, WASM, etc.)
  * guidance for WSL2 and AppArmor on Windows dev machines
  * smooth use from PowerShell, VS Code, and typical .NET workflows

* **Developer-centric vs platform-centric**
  Container-Use sits naturally in Dagger’s world and CI pipelines. ContainAI is aimed squarely at “I’m a dev on my machine (or in a dev container) and I want to safely let an AI loose on this repo.”

### StrongDM’s Leash

Leash is another important project:

* wraps AI agents in monitored containers
* uses Cedar policies to control what agents can do
* logs file and network operations extensively
* comes with a UI and more of an enterprise policy flavor

If you want a centrally-managed, policy-driven, UI-managed agent runtime, Leash is great.

**Where ContainAI differs:**

* **CLI-first, repo-first**
  Leash feels like a managed environment with a control plane and UI. ContainAI is aimed at developers who want:

  * a set of CLI tools they can script and version
  * per-repo workflows they control directly
  * less “platform” and more “tooling”

* **Opinionated but minimal surface**
  Leash uses Cedar and a broad policy model—it can do a lot. ContainAI intentionally keeps the enforcement model simple and auditable:

  * containers are hardened with seccomp/AppArmor
  * the runner mediates particularly dangerous syscalls
  * secrets are mediated by a broker
  * network egress can be fully disabled and all egress is forced through a proxy and logged

  There’s no custom policy language to learn; instead, it tries to bake in sane defaults that align with typical dev needs.

* **Tight integration with .NET and MCP tooling**
  ContainAI has images tuned for the GitHub/Microsoft ecosystem:

  * .NET SDKs built in
  * integration with Model Context Protocol (MCP) tools like GitHub CLI and Microsoft Docs
  * workflows that feel natural for VS Code + GitHub users

Leash is more “enterprise control plane for agents”. ContainAI is more “developer sandbox and workflow for agents”.

### Everyone else (Copilot, Cursor, Ghostwriter, raw Docker hacks…)

Most AI agent tools today don’t try to solve this problem at all:

* Copilot and similar tools stay inside the IDE and don’t run commands.
* Cursor and others may run tools but generally within the editor or a single, lightly-isolated environment.
* Some people roll their own ad-hoc “just run AutoGPT in Docker” setups with no consistent security story.

ContainAI is explicitly about the *“agents can run commands and do real work on the codebase”* scenario, with:

* strong containment
* reproducible environments
* reviewable Git branches
* realistic, cross-platform tooling

---

## Why This Matters Especially for .NET

Most early AI-agent frameworks and experiments have been Python-centric. If you’re in .NET land, you probably recognized the pattern but didn’t have a ready-made solution that:

* understands Windows + WSL2 realities
* ships with current .NET SDKs and workloads out of the box
* plays nicely with Visual Studio Code dev containers
* respects the expectations of enterprise .NET shops around security and repeatability

ContainAI exists in part because of that gap.

It gives .NET teams:

* a safe way to experiment with autonomous agents on real codebases
* containers that mirror the production stack (Linux, .NET, typical tooling)
* Git-based branch isolation for agent output
* integration with tools like Azure DevOps / GitHub workflows via CLI and CI support

It doesn’t exclude other stacks—Python, Node, and general CLI tools work fine—but it treats .NET as a first-class target instead of an afterthought.

---

## Security Philosophy: Assume the Agent Is Untrusted

A lot of AI tooling still implicitly treats the model as “helpful” and “trusted”. ContainAI takes the opposite position:

> The agent is untrusted. Contain it like untrusted code.

Key principles:

* **Isolation by default**
  Each agent runs as a non-root user in a hardened container:

  * capabilities dropped
  * seccomp profile blocking dangerous syscalls
  * AppArmor profile limiting filesystem and kernel access
  * CPU/memory/PID limits to prevent resource abuse

* **Least privilege everywhere**

  * Host launcher and broker are the only trusted pieces with Docker and secret access.
  * The container only sees the repo checkout and the tools it needs.
  * In-container helper processes (“MCP stubs”) run as a different user than the agent, with access only to their tmpfs for secret redemption.

* **No secrets on disk**

  * Secrets never land in the repo or in container layers.
  * Capability tokens are passed into a tmpfs and redeemed just-in-time by stubs.
  * Actual tokens/keys live in a host broker and can be revoked independently.

* **Integrity checks and auditability**

  * The install is meant to be immutable; core scripts/binaries are checked against a signed SBOM or known Git state.
  * If you run a modified version, you have to explicitly opt-out, and that fact is logged.
  * Security-relevant actions (capability issuance, override flags, certain syscalls) are logged for post-incident analysis.

The goal isn’t “prove the AI is trustworthy”. The goal is “make it safe to *not* trust the AI, while still getting value from it”.

---

## What This Project Is (and Isn’t)

**Is:**

* A way to run powerful AI agents *safely* on real codebases
* A workflow for parallel, branch-isolated agent contributions you can review and merge
* A security-conscious, .NET-friendly toolkit that plugs into existing dev tooling

**Is not:**

* A hosted AI service or platform
* A replacement for your IDE’s inline assistant
* A magic productivity guarantee

The project is still early. It’s engineered seriously (docs, tests, careful security model), but adoption is just beginning. It will evolve as real teams use it and as the ecosystem around MCP and agents matures.

ContainAI exists because we wanted a way to actually *trust* giving agents more power—by not trusting them at all, and instead giving them tight, reviewable boxes to work in.
