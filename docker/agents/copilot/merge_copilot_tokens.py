#!/usr/bin/env python3
"""Merge Copilot tokens from a host config into the container config.

This script is intentionally forgiving:
- If the container config is missing or invalid JSON, it is treated as empty.
- If the host config cannot be read/parsed, token import is skipped.
"""

from __future__ import annotations

import json
import pathlib
import sys


def _load_json_or_default(path: pathlib.Path, default: dict) -> dict:
    """Load JSON from path or return default for missing/invalid files."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return dict(default)
    except json.JSONDecodeError:
        return dict(default)
    except OSError:
        return dict(default)


def main(argv: list[str]) -> int:
    """CLI entrypoint."""
    if len(argv) != 2:
        print("Usage: merge-copilot-tokens.py <host_config> <container_config>", file=sys.stderr)
        return 1

    host_cfg = pathlib.Path(argv[0])
    container_cfg = pathlib.Path(argv[1])

    container = _load_json_or_default(container_cfg, default={})

    try:
        host = json.loads(host_cfg.read_text(encoding="utf-8"))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        print(
            "⚠️ Unable to read host Copilot config – skipping token import",
            file=sys.stderr,
        )
        return 0

    for key in ("copilot_tokens", "last_logged_in_user", "logged_in_users"):
        if key in host:
            container[key] = host[key]

    container_cfg.write_text(json.dumps(container, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
