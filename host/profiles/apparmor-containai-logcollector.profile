# ContainAI LogCollector AppArmor Profile
# See docs/security/logcollector-architecture.md for design rationale.
#
# Security model: Minimal permissions for audit log collection.
# The LogCollector runs in an isolated user namespace as a dedicated user
# (logcollector, UID 1001) separate from the untrusted agent (agentuser).
#
# Permissions granted:
#   - Read from audit socket (/run/containai/audit.sock)
#   - Write to log directory (/var/log/containai/)
#   - Basic process operations (no network, no capability escalation)

#include <tunables/global>

profile containai-logcollector flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Deny network access - LogCollector only writes to local files
  deny network,

  # Deny all capabilities - LogCollector needs no special privileges
  deny capability,

  # Audit socket - read events from untrusted processes
  /run/containai/ r,
  /run/containai/audit.sock rw,

  # Log output directory - append-only semantics enforced by collector
  /var/log/containai/ r,
  /var/log/containai/** rw,

  # Runtime state directory
  /run/agent-task-runner/ r,
  /run/agent-task-runner/collector.log rw,

  # Binary and libraries
  /usr/local/bin/containai-log-collector mr,
  /lib/** mr,
  /usr/lib/** mr,
  /lib64/** mr,

  # Process introspection (own process only)
  /proc/sys/kernel/random/uuid r,
  /proc/self/** r,
  owner /proc/*/fd/ r,
  owner /proc/*/maps r,

  # Environment and basic system files
  /etc/passwd r,
  /etc/group r,
  /etc/nsswitch.conf r,
  /etc/localtime r,
  /usr/share/zoneinfo/** r,

  # Deny dangerous paths
  deny /home/** rwklx,
  deny /root/** rwklx,
  deny /workspace/** rwklx,
  deny /run/agent-secrets/** rwklx,
  deny /run/agent-data/** rwklx,
  deny /proc/sys/** w,
  deny /sys/** rwklx,
  deny mount,
  deny umount,
  deny ptrace,

  # Signal handling - only from within same profile or unconfined (dockerd)
  signal (receive) peer=unconfined,
  signal (send,receive) peer=containai-logcollector,
}
