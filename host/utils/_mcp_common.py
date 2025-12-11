#!/usr/bin/env python3
"""Shared utilities for MCP configuration scripts."""

from __future__ import annotations

import os
import pathlib
import re
import sys
from typing import Dict, List, Set

ENV_PATTERN = re.compile(
    r"\$\{(?P<braced>[A-Za-z_][A-Za-z0-9_]*)\}|\$(?P<bare>[A-Za-z_][A-Za-z0-9_]*)"
)


def load_secret_file(path: pathlib.Path) -> Dict[str, str]:
    """Load KEY=VALUE pairs from an env-style file.

    Handles optional export prefix and quoted values.
    """
    result: Dict[str, str] = {}
    if not path.exists():
        return result
    try:
        content = path.read_text(encoding="utf-8")
        for raw_line in content.splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:]
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip()
            if not key:
                continue
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
                value = value[1:-1]
            result.setdefault(key, value)
    except OSError as exc:
        print(f"⚠️  Unable to read secrets from {path}: {exc}", file=sys.stderr)
    return result


def collect_placeholders(value) -> Set[str]:
    """Recursively collect environment variable placeholders from a value."""
    names: Set[str] = set()
    if isinstance(value, str):
        for match in ENV_PATTERN.finditer(value):
            names.add(match.group("braced") or match.group("bare"))
    elif isinstance(value, list):
        for item in value:
            names.update(collect_placeholders(item))
    elif isinstance(value, dict):
        for item in value.values():
            names.update(collect_placeholders(item))
    return names


def resolve_value(value, secrets: Dict[str, str]):
    """Recursively resolve environment variable placeholders."""

    def _replace(match: re.Match[str]) -> str:
        var = match.group("braced") or match.group("bare")
        if var in secrets and secrets[var]:
            return secrets[var]
        env_val = os.environ.get(var)
        if env_val:
            return env_val
        return match.group(0)

    if isinstance(value, str):
        return ENV_PATTERN.sub(_replace, value)
    if isinstance(value, list):
        return [resolve_value(item, secrets) for item in value]
    if isinstance(value, dict):
        return {key: resolve_value(val, secrets) for key, val in value.items()}
    return value


def parse_mcp_server_config(
    name: str,
    settings: Dict,
) -> tuple[str, List[str], Dict[str, str], str | None]:
    """Parse common MCP server configuration fields.

    Returns (command, args, env, cwd).
    """
    config = dict(settings)
    command = str(config.pop("command", "")).strip()
    if not command:
        raise ValueError(f"MCP server '{name}' is missing a command")

    raw_args = config.pop("args", []) or []
    args = [str(item) for item in raw_args]
    raw_env = config.pop("env", {}) or {}
    env = {str(k): str(v) for k, v in raw_env.items()}
    cwd = config.pop("cwd", None)
    config.pop("bearer_token_env_var", None)

    return command, args, env, cwd
