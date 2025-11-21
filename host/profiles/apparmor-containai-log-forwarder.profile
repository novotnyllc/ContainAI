#include <tunables/global>

profile containai-log-forwarder flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/user-tmp>

  network,
  capability,
  file,
  umount,

  /var/log/squid/** r,
  /certs/** r,
  /tmp/** rw,
  deny /home/** rwklx,
  deny /root/** rwklx,
  deny /proc/** wklx,
  deny /sys/** wklx,
  deny mount,

  ptrace (trace,read,tracedby,readby) peer=containai-log-forwarder,
}
