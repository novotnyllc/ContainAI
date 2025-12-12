#include <tunables/global>

profile containai-proxy flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/user-tmp>

  network,
  capability,
  file,
  umount,

  signal (receive) peer=unconfined,

  /etc/squid/** r,
  /var/log/squid/ rw,
  /var/log/squid/** rw,
  /var/spool/squid/ rw,
  /var/spool/squid/** rw,
  /var/run/squid/ rw,
  /var/run/squid/** rw,
  deny /home/** rwklx,
  deny /root/** rwklx,
  deny /tmp/** wklx,
  deny /proc/** wklx,
  deny /sys/** wklx,
  deny mount,

  ptrace (trace,read,tracedby,readby) peer=containai-proxy,
}
