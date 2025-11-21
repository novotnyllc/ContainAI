#!/usr/bin/env python3
"""
Convert config.toml to agent-specific MCP JSON configurations.
Reads a single source of truth (config.toml) and generates config files for each agent.
"""

import base64
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
STUB_COMMAND_TEMPLATE = "/home/agentuser/.local/bin/mcp-stub-{name}"
HELPER_LISTEN_HOST = "127.0.0.1"
HELPER_PORT_BASE = 52100
DEFAULT_CONFIG_ROOT = Path(os.environ.get("CONTAINAI_CONFIG_ROOT", Path.home() / ".config" / "containai-dev"))
DEFAULT_HELPER_ACL_CONFIG = Path(
    os.environ.get("CONTAINAI_SQUID_HELPERS_CONFIG", DEFAULT_CONFIG_ROOT / "squid-helpers.json")
)


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
            str(Path.home() / ".config/containai/mcp-secrets.env"),
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


def collect_placeholders(value):
    names = set()
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


def convert_remote_server(name, settings, secrets, missing_tokens, next_port):
    converted = {}
    bearer_var = settings.get("bearer_token_env_var")
    bearer_token = None

    for key, value in settings.items():
        if key == "bearer_token_env_var":
            continue
        converted[key] = resolve_value(value, secrets)

    if bearer_var:
        token = resolve_var(bearer_var, secrets)
        if token:
            bearer_token = token
            converted["bearerToken"] = token
        else:
            missing_tokens.append((name, bearer_var))

    listen_port = next_port()
    listen_addr = f"{HELPER_LISTEN_HOST}:{listen_port}"
    target_url = converted.get("url")
    converted["url"] = f"http://{listen_addr}"
    helper_entry = {"name": name, "listen": listen_addr, "target": target_url}
    if bearer_token:
        helper_entry["bearerToken"] = bearer_token
    return converted, helper_entry


def convert_stub_server(name, settings, secrets, warnings):
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

    placeholders = collect_placeholders(command)
    placeholders.update(collect_placeholders(args))
    placeholders.update(collect_placeholders(env))
    if cwd:
        placeholders.update(collect_placeholders(cwd))

    available = {k for k, v in secrets.items() if v} | {k for k, v in os.environ.items() if v}
    stub_secrets = sorted(name for name in placeholders if name in available)
    missing = sorted(name for name in placeholders if name not in available)
    for placeholder in missing:
        warnings.append(
            f"⚠️  Secret '{placeholder}' referenced by MCP server '{name}' is not defined"
        )

    spec = {
        "stub": name,
        "server": name,
        "command": command,
        "args": args,
        "env": env,
        "secrets": stub_secrets,
    }
    if cwd:
        spec["cwd"] = str(cwd)

    rendered_entry = dict(config)
    rendered_entry["command"] = STUB_COMMAND_TEMPLATE.format(name=name)
    rendered_entry["args"] = []
    rendered_entry["env"] = {
        "CONTAINAI_STUB_SPEC": base64.b64encode(json.dumps(spec, sort_keys=True).encode("utf-8")).decode("ascii"),
        "CONTAINAI_STUB_NAME": name,
    }
    return rendered_entry


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
    warnings = []
    helpers = []
    port_state = {"value": HELPER_PORT_BASE}

    def next_port():
        value = port_state["value"]
        port_state["value"] += 1
        return value

    resolved_servers = {}
    for name, settings in mcp_servers.items():
        settings = dict(settings or {})
        if "command" in settings:
            resolved_servers[name] = convert_stub_server(name, settings, secrets, warnings)
        else:
            rendered, helper_entry = convert_remote_server(name, settings, secrets, missing_tokens, next_port)
            resolved_servers[name] = rendered
            helpers.append(helper_entry)

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

    helper_manifest = {"helpers": helpers, "source": str(toml_path)}
    helper_path = os.path.expanduser("~/.config/containai/helpers.json")
    os.makedirs(os.path.dirname(helper_path), exist_ok=True)
    try:
        with open(helper_path, "w", encoding="utf-8") as handle:
            json.dump(helper_manifest, handle, indent=2, sort_keys=True)
    except Exception as exc:  # pylint: disable=broad-except
        print(f"⚠️  Unable to write helper manifest: {exc}", file=sys.stderr)

    print("✅ MCP configurations generated for all agents")
    print(f"   Servers configured: {', '.join(resolved_servers.keys())}")
    print(f"   Config source: {toml_path}")
    if helpers:
        helper_names = ", ".join(helper["name"] for helper in helpers)
        print(f"   Helper proxies: {helper_names}")

    if missing_tokens:
        for server_name, env_var in missing_tokens:
            print(
                f"⚠️  Missing secret '{env_var}' for MCP server '{server_name}' (bearer token not injected)",
                file=sys.stderr,
            )
    for warning in warnings:
        print(warning, file=sys.stderr)

    return True


if __name__ == "__main__":
    toml_path = sys.argv[1] if len(sys.argv) > 1 else "/workspace/config.toml"
    success = convert_toml_to_mcp(toml_path)
    sys.exit(0 if success else 1)
