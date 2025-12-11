# ContainAI Agent AppArmor Profile
# See docs/security/profile-architecture.md for design rationale.
#
# Security model: Defense-in-depth with seccomp (primary), AppArmor (this),
# capabilities (CAP_DROP=ALL + SYS_ADMIN for sandbox), namespaces, read-only rootfs.
#
# Broad grants (network, capability, file) are intentional - agents need flexibility
# for dev tasks. Security boundaries enforced via seccomp hard-deny and cap-drop.

#include <tunables/global>

profile containai-agent flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/user-tmp>
  #include <abstractions/authentication>

  network,
  capability,
  file,
  umount,

  # Host processes (dockerd) may send signals for lifecycle operations
  signal (receive) peer=unconfined,
  # Processes within the container run under this profile and must signal each other
  # (e.g., shell to children, agent-task-sandbox to spawned commands)
  signal (send,receive) peer=containai-agent,

  deny @{PROC}/* w,
  deny @{PROC}/{[^1-9],[^1-9][^0-9],[^1-9s][^0-9y][^0-9s],[^1-9][^0-9][^0-9][^0-9]*}/** w,
  deny @{PROC}/sys/[^k]** w,
  deny @{PROC}/sys/kernel/{?,??,[^s][^h][^m]**} w,
  deny @{PROC}/sysrq-trigger rwklx,
  deny @{PROC}/kcore rwklx,

  # MOUNT RULES - Required for agent-task-sandbox namespace isolation.
  # These allow `unshare --mount --pid` to create isolated namespaces for each
  # agent command. Docker's --tmpfs handles tmpfs creation; these rules permit
  # the propagation changes needed by unshare.

  # Audit shim bind mount
  mount options=(rw,bind) /run/ld.so.preload -> /etc/ld.so.preload,

  # /proc hardening remount
  mount options=(rw,remount) -> /proc/,

  # Sensitive tmpfs mounts
  mount fstype=tmpfs -> /run/agent-secrets/,
  mount fstype=tmpfs -> /run/agent-data/,
  mount fstype=tmpfs -> /run/agent-data-export/,
  mount fstype=tmpfs -> /home/*/,
  mount fstype=tmpfs -> /home/*/.config/containai/capabilities/,

  # Remount with restrictive flags
  mount options=(rw,remount) -> /run/agent-secrets/,
  mount options=(rw,remount) -> /run/agent-data/,
  mount options=(rw,remount) -> /run/agent-data-export/,
  mount options=(rw,remount) -> /home/*/,
  mount options=(rw,remount) -> /home/*/.config/containai/capabilities/,

  # Mount propagation isolation
  mount options=(rw,make-private) -> /run/agent-secrets/,
  mount options=(rw,make-private) -> /run/agent-data/,
  mount options=(rw,make-private) -> /run/agent-data-export/,
  mount options=(rw,make-private) -> /home/*/.config/containai/capabilities/,
  mount options=(rw,make-unbindable) -> /run/agent-secrets/,
  mount options=(rw,make-unbindable) -> /run/agent-data/,
  mount options=(rw,make-unbindable) -> /run/agent-data-export/,
  mount options=(rw,make-unbindable) -> /home/*/.config/containai/capabilities/,

  # Deny all other mounts
  deny mount,

  deny /sys/[^f]*/** wklx,
  deny /sys/f[^s]*/** wklx,
  deny /sys/fs/[^c]*/** wklx,
  deny /sys/fs/c[^g]*/** wklx,
  deny /sys/fs/cg[^r]*/** wklx,
  deny /sys/firmware/** rwklx,
  deny /sys/kernel/security/** rwklx,

  # ptrace is hard-blocked by seccomp (SCMP_ACT_ERRNO). This deny rule provides
  # defense-in-depth and prevents audit log noise if seccomp is misconfigured.
  deny ptrace,
}
