#!/usr/bin/env python3
"""Network helper utilities for integration tests.

Provides deterministic-ish random subnet selection and host IP picking
without relying on inline heredocs in shell.
"""

import argparse
import hashlib
import ipaddress
import random
import sys


def cmd_random_subnet(args: argparse.Namespace) -> int:
    """Print a pseudo-random subnet within a base CIDR.

    The subnet is derived from the (session, test) identifiers plus a small
    random salt to avoid collisions when multiple tests run concurrently.
    """
    base = ipaddress.ip_network(args.base)
    if args.prefix <= base.prefixlen:
        raise ValueError("prefix must be larger than base prefixlen")
    step = 1 << (32 - args.prefix)
    max_subnets = 1 << (args.prefix - base.prefixlen)

    seed_str = f"{args.session}-{args.test}-{random.randint(0, 1_000_000)}"
    h = int(hashlib.sha256(seed_str.encode()).hexdigest(), 16)
    offset = h % max_subnets

    net_int = int(base.network_address) + offset * step
    subnet = ipaddress.ip_network((net_int, args.prefix))
    print(subnet)
    return 0


def cmd_host_ip(args: argparse.Namespace) -> int:
    """Print the Nth host IP for a subnet.

    If the index exceeds the precomputed host list length, fall back to a
    deterministic arithmetic offset from the network address.
    """
    net = ipaddress.ip_network(args.subnet)
    hosts = list(net.hosts())
    idx = args.index
    if idx < len(hosts):
        addr = hosts[idx]
    else:
        addr = net.network_address + idx + 1
    print(addr)
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI argument parser."""
    parser = argparse.ArgumentParser(description="Network helpers for tests")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_subnet = sub.add_parser("random-subnet", help="Generate random subnet")
    p_subnet.add_argument("--session", required=True)
    p_subnet.add_argument("--test", required=True)
    p_subnet.add_argument("--base", default="100.64.0.0/10")
    p_subnet.add_argument("--prefix", type=int, default=28)
    p_subnet.set_defaults(func=cmd_random_subnet)

    p_host = sub.add_parser("host-ip", help="Pick host IP from subnet by index")
    p_host.add_argument("--subnet", required=True)
    p_host.add_argument("--index", type=int, required=True)
    p_host.set_defaults(func=cmd_host_ip)

    return parser


def main(argv: list[str]) -> int:
    """CLI entrypoint."""
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
