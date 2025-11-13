#!/usr/bin/env python3
"""Merge Copilot tokens from host config into container config."""
import json
import sys

if len(sys.argv) != 3:
    print("Usage: merge-copilot-tokens.py <host_config> <container_config>", file=sys.stderr)
    sys.exit(1)

host_cfg, container_cfg = sys.argv[1], sys.argv[2]

try:
    with open(container_cfg, "r", encoding="utf-8") as f:
        container = json.load(f)
except Exception:
    container = {}

try:
    with open(host_cfg, "r", encoding="utf-8") as f:
        host = json.load(f)
except Exception:
    print("⚠️ Unable to read host Copilot config – skipping token import", file=sys.stderr)
    sys.exit(0)

for key in ("copilot_tokens", "last_logged_in_user", "logged_in_users"):
    if key in host:
        container[key] = host[key]

with open(container_cfg, "w", encoding="utf-8") as f:
    json.dump(container, f, indent=2)
