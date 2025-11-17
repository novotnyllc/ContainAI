# UX / Prompt Policy

- **Tier 1 (Silent)**: File edits, tests, formatting, git status, git commit, git push to `local`, invoking Serena/Context7/Microsoft Docs, reading documentation. Actions auto-logged with session ID; no prompts.
- **Tier 2 (Silent + Logged + Rate-Limited)**: Package installs (`npm install`, `pip install`), running builds that pull remote artifacts, bulk file rewrites, network downloads via safe_net to allowlisted domains. Proxy and command logs capture metadata; repeated large transfers trigger non-blocking alerts.
- **Tier 3 (Prompted or Blocked)**:
  1. `git push origin` or adding new git remotes → require explicit confirmation referencing target URL, or block if repo not allowlisted.
  2. Requests to modify launcher/runtime scripts, Squid allowlist, or security policy files → require host approval.
  3. Attempts to reach non-allowlisted domains or enable allow-all networking → require one-time approval per session and produce prominent warning.
  4. Secret broker scope escalation (requesting admin tokens) → require confirmation outside container (e.g., OS prompt or hardware token).
- **Blocked Outright**: Mounting docker.sock, requesting privileged containers, writing outside approved mounts, disabling seccomp/SELinux flags.
- **Kill Switch UX**: Launcher UI exposes `coding-agents kill <session>` that stops container, revokes tokens, and marks session as quarantined; no prompt because action is protective.
