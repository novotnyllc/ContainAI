 PRD: ContainAI Reliability Pack — Sysbox Updates, Doctor‑Driven Repair, Packaging Fix, SSH Execution (Final Update)

  Summary
  This PRD covers four reliability issues plus a critical update‑flow gap:

  1. Sysbox/Docker upgrades while containers are running can taint id‑mapped mounts.
  2. Data volume ownership can be repaired, but needs a workflow under cai doctor.
  3. Custom sysbox deb expects fusermount3, but depends only on fuse (fuse2).
  4. cai shell can incorrectly background SSH commands.
  5. Sysbox update mechanism must work correctly on WSL2, Linux, and Lima.

  ———

  ## 1) Safe Sysbox/Docker Update Flow + Systemd Stop Hooks

  Problem
  Restarting sysbox or dockerd while containers are running breaks id‑mapped mounts.

  Goals

  - Only stop containers when sysbox/docker updates are actually needed.
  - Cleanly stop ContainAI containers on both sysbox and containai‑docker service stop/restart.

  Functional Requirements

  - cai update checks if sysbox/docker updates are needed.
      - If no updates needed: no warnings.
      - If updates needed and containers running: warn that containers will be stopped.
      - --stop-containers stops + updates + restarts.
      - --force proceeds without stopping (strong warning).
      - --dry-run prints what would be stopped.
  - Systemd stop hooks
      - Add a unit (or drop‑ins) so stopping either sysbox.service or containai-docker.service stops ContainAI containers in the containai context:
          - PartOf=containai-docker.service sysbox.service
          - Before=containai-docker.service sysbox.service on stop/restart
          - Executes “stop ContainAI containers” safely.

  Acceptance Criteria

  - Containers only stopped when updates are required.
  - Systemd stop/restart of sysbox/docker cleanly stops ContainAI containers.

  ———

  ## 2) Data Volume Repair — Integrated into cai doctor

  Problem
  Sysbox restarts can corrupt id‑mapped mounts; files show nobody:nogroup.

  Goals

  - Repair workflow lives under cai doctor.
  - Auto‑detect UID/GID where possible; default 1000 if unknown.

  Functional Requirements

  - cai doctor --fix includes ownership repair if detected.
  - Explicit repair subcommands:
      - cai doctor --repair
      - cai doctor --repair --container <id|name>
      - cai doctor --repair --all
      - cai doctor --repair --dry-run
  - UID/GID detection:
      - Running container: id -u agent / id -g agent.
      - Stopped container: attempt detection; fallback 1000:1000 (warn).
  - Safe repair:
      - Only under /var/lib/containai-docker/volumes.
      - No symlink traversal, no cross‑filesystem.
  - Rootfs taint detection:
      - If /usr/bin/sudo not root‑owned, warn to recreate container.

  Acceptance Criteria

  - cai doctor --repair --all repairs all managed volumes.
  - Auto‑detect works; fallback is explicit.

  ———

  ## 3) Sysbox Packaging Dependency Fix

  Problem
  Custom sysbox deb expects fusermount3 but only depends on fuse (fuse2).

  Requirements

  - Add dependency on fuse3 (or fuse3 | fuse based on distro support).
  - CI validation:
      - dpkg -s sysbox-ce shows fuse3 dependency.
      - command -v fusermount3 present after install.

  Acceptance Criteria

  - sysbox-fs starts without manual apt install fuse3.

  ———

  ## 4) SSH Background Execution & cai shell Reliability

  Problem
  cai shell sometimes prints “Running command in background via SSH…” and exits; remote command doesn’t execute.

  Requirements

  - cai shell always allocates TTY and never detaches.
  - Detached SSH execution:
      - Use sh -lc for consistent parsing.
      - Correct quoting for env vars and args.
      - Confirm background launch or surface errors.

  Acceptance Criteria

  - cai shell always opens interactive shell.
  - Detached mode reliably executes command.

  ———

  ## 5) Sysbox Update Mechanism Across Platforms (Critical Gap)

  Problem
  Sysbox update does not properly update on WSL2, Linux, or Lima in all cases (e.g., WSL2 early‑return on installed sysbox).

  Goals

  - Ensure sysbox updates are correctly applied on WSL2, native Linux, and Lima.

  Functional Requirements

  - WSL2: remove early‑return behavior in _cai_install_sysbox_wsl2 so upgrades are applied when needed.
  - Linux: ensure update flow upgrades existing sysbox when version mismatch exists.
  - Lima (macOS):
      - Update sysbox inside the VM when cai update runs.
      - Ensure sysbox version check reflects VM state, not host.

  Acceptance Criteria

  - cai update upgrades sysbox on WSL2/Linux when newer bundled version exists.
  - On macOS, cai update updates sysbox inside Lima VM as needed.
  - cai doctor reports correct sysbox version for each platform.
