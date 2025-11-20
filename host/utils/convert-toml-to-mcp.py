#!/usr/bin/env python3
"""
Convert config.toml to agent-specific MCP JSON configurations.
Reads a single source of truth (config.toml) and generates config files for each agent.
"""

import json
import os
import re
import sys
from pathlib import Path

import tomllib


ENV_PATTERN = re.compile(r"\$\{(?P<braced>[A-Za-z_][A-Za-z0-9_]*)\}|\$(?P<bare>[A-Za-z_][A-Za-z0-9_]*)")
DEFAULT_AGENTS = {
    "github-copilot": "~/.config/github-copilot/mcp",
    "codex": "~/.config/codex/mcp",
    "claude": "~/.config/claude/mcp",
}


def load_secret_file(path):
    """Load KEY=VALUE pairs from an env-style file."""

    secrets = {}
    if not path or not os.path.exists(path):
        return secrets

    try:
        with open(path, "r", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()
                if not key:
                    continue
                if value and ((value[0] == value[-1]) and value.startswith(("'", '"'))):
                    value = value[1:-1]
                secrets.setdefault(key, value)
    except OSError as exc:
        print(f"⚠️  Unable to read secrets from {path}: {exc}", file=sys.stderr)

    return secrets


def collect_secrets():
    """Combine secrets from file sources and the current environment."""

    secret_paths = []
    override = os.environ.get("MCP_SECRETS_FILE")
    if override:
        secret_paths.append(override)

    secret_paths.extend(
        [
            "/home/agentuser/.mcp-secrets.env",
            str(Path.home() / ".mcp-secrets.env"),
            str(Path.home() / ".config/coding-agents/mcp-secrets.env"),
        ]
    )

    secrets = {}
    seen = set()
    for candidate in secret_paths:
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        secrets.update({k: v for k, v in load_secret_file(candidate).items() if k not in secrets})

    return secrets


def resolve_var(name, secrets):
    if name in secrets and secrets[name]:
        return secrets[name]
    if name in os.environ and os.environ[name]:
        return os.environ[name]
    return None


def substitute_placeholders(value, secrets):
    def _replace(match):
        var = match.group("braced") or match.group("bare")
        resolved = resolve_var(var, secrets)
        if resolved is None:
            return match.group(0)
        return resolved

    return ENV_PATTERN.sub(_replace, value)


def resolve_value(value, secrets):
    if isinstance(value, str):
        return substitute_placeholders(value, secrets)
    if isinstance(value, list):
        return [resolve_value(item, secrets) for item in value]
    if isinstance(value, dict):
        return {key: resolve_value(val, secrets) for key, val in value.items()}
    return value


def convert_server_config(name, settings, secrets, missing_tokens):
    converted = {}
    bearer_var = settings.get("bearer_token_env_var")

    for key, value in settings.items():
        if key == "bearer_token_env_var":
            continue
        converted[key] = resolve_value(value, secrets)

    if bearer_var:
        token = resolve_var(bearer_var, secrets)
        if token:
            converted["bearerToken"] = token
        else:
            missing_tokens.append((name, bearer_var))

    return converted


def convert_toml_to_mcp(toml_path):
    """Convert TOML config to MCP JSON format for all agents."""

    if not os.path.exists(toml_path):
        print(f"⚠️  No config.toml found at {toml_path}", file=sys.stderr)
        return False

    try:
        with open(toml_path, "rb") as handle:
            config = tomllib.load(handle)
    except Exception as exc:  # pylint: disable=broad-except
        print(f"❌ Error parsing TOML: {exc}", file=sys.stderr)
        return False

    mcp_servers = config.get("mcp_servers", {})
    if not mcp_servers:
        print("⚠️  No mcp_servers found in config.toml", file=sys.stderr)
        return False

    secrets = collect_secrets()
    missing_tokens = []
    resolved_servers = {
        name: convert_server_config(name, settings, secrets, missing_tokens)
        for name, settings in mcp_servers.items()
    }

    agents = dict(DEFAULT_AGENTS)

    for agent_name, config_path in agents.items():
        config_dir = os.path.expanduser(config_path)
        os.makedirs(config_dir, exist_ok=True)

        mcp_config = {"mcpServers": resolved_servers}

        config_file = os.path.join(config_dir, "config.json")
        try:
            with open(config_file, "w", encoding="utf-8") as handle:
                json.dump(mcp_config, handle, indent=2)
        except Exception as exc:  # pylint: disable=broad-except
            print(f"❌ Error writing {agent_name} config: {exc}", file=sys.stderr)
            return False

    print("✅ MCP configurations generated for all agents")
    print(f"   Servers configured: {', '.join(resolved_servers.keys())}")
    print(f"   Config source: {toml_path}")

    if missing_tokens:
        for server_name, env_var in missing_tokens:
            print(
                f"⚠️  Missing secret '{env_var}' for MCP server '{server_name}' (bearer token not injected)",
                file=sys.stderr,
            )

    return True


if __name__ == "__main__":
    toml_path = sys.argv[1] if len(sys.argv) > 1 else "/workspace/config.toml"
    success = convert_toml_to_mcp(toml_path)
    sys.exit(0 if success else 1)
