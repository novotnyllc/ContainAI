#!/usr/bin/env python3
"""
Convert config.toml to agent-specific MCP JSON configurations.

This script transforms ContainAI's unified config.toml into the JSON format
expected by each AI agent (Copilot, Claude, Codex).

MCP Server Types:
-----------------
1. REMOTE servers (have 'url'):
   - Accessed via a local helper proxy that forwards requests through Squid
   - The proxy handles bearer token injection and TLS termination
   - Config points to http://127.0.0.1:<port> instead of the real URL

2. LOCAL servers (have 'command'):
   - Run as child processes inside the container
   - Wrapped by mcp-wrapper to inject secrets from sealed capabilities
   - Secrets are decrypted at runtime, never stored in plaintext configs

Output Files:
-------------
- ~/.config/<agent>/mcp/config.json  - Agent-specific MCP server configs
- ~/.config/containai/helpers.json   - Helper proxy manifest for remote servers
- ~/.config/containai/wrappers/      - Wrapper specs for local servers
"""

import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Tuple

import tomllib

# Allow import of sibling modules
sys.path.insert(0, str(Path(__file__).parent))
from _mcp_common import (  # noqa: E402  # pylint: disable=wrong-import-position
    collect_placeholders,
    load_secret_file,
    resolve_value,
)

# Agent config directories (relative to ~)
DEFAULT_AGENTS = {
    "github-copilot": "~/.config/github-copilot/mcp",
    "codex": "~/.config/codex/mcp",
    "claude": "~/.config/claude/mcp",
}

# Where wrapper specs are written
WRAPPER_SPEC_DIR = "~/.config/containai/wrappers"
# The wrapper binary that reads specs and injects secrets
WRAPPER_COMMAND = "/home/agentuser/.local/bin/mcp-wrapper-{name}"

# Helper proxy settings for remote MCP servers
HELPER_LISTEN_HOST = "127.0.0.1"
HELPER_PORT_BASE = 52100

DEFAULT_CONFIG_ROOT = Path(
    os.environ.get("CONTAINAI_CONFIG_ROOT", Path.home() / ".config" / "containai-dev")
)
DEFAULT_HELPER_ACL_CONFIG = Path(
    os.environ.get(
        "CONTAINAI_SQUID_HELPERS_CONFIG", DEFAULT_CONFIG_ROOT / "squid-helpers.json"
    )
)


def collect_secrets() -> Dict[str, str]:
    """Combine secrets from file sources and the current environment."""
    secret_paths: List[str] = []
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

    secrets: Dict[str, str] = {}
    seen: set = set()
    for candidate in secret_paths:
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        file_secrets = load_secret_file(Path(candidate))
        secrets.update({k: v for k, v in file_secrets.items() if k not in secrets})

    return secrets


def resolve_var(name: str, secrets: Dict[str, str]) -> str | None:
    """Resolve a variable name from secrets or environment."""
    if name in secrets and secrets[name]:
        return secrets[name]
    if name in os.environ and os.environ[name]:
        return os.environ[name]
    return None


def _is_already_proxied(server_config):
    """Check if a server config is already going through our proxy mechanism."""
    if not isinstance(server_config, dict):
        return False
    # Check for wrapper (local server already wrapped)
    env = server_config.get("env", {})
    if env.get("CONTAINAI_WRAPPER_SPEC") or env.get("CONTAINAI_WRAPPER_NAME"):
        return True
    # Check for helper proxy (remote server already proxied)
    url = server_config.get("url", "")
    if isinstance(url, str) and url.startswith(f"http://{HELPER_LISTEN_HOST}:"):
        return True
    # Check for wrapper command
    cmd = server_config.get("command", "")
    if isinstance(cmd, str) and "mcp-wrapper-" in cmd:
        return True
    return False


def convert_remote_server(
    name: str,
    settings: Dict,
    secrets: Dict[str, str],
    missing_tokens: List[Tuple[str, str]],
    port_state: Dict[str, int],
) -> Tuple[Dict, Dict]:
    """Convert a remote MCP server to use a local helper proxy."""
    converted: Dict = {}
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

    listen_port = port_state["value"]
    port_state["value"] += 1
    listen_addr = f"{HELPER_LISTEN_HOST}:{listen_port}"
    target_url = converted.get("url")
    converted["url"] = f"http://{listen_addr}"
    helper_entry = {"name": name, "listen": listen_addr, "target": target_url}
    if bearer_token:
        helper_entry["bearerToken"] = bearer_token
    return converted, helper_entry


def convert_local_server(
    name: str,
    settings: Dict,
    secrets: Dict[str, str],
    warnings: List[str],
) -> Tuple[Dict, Dict]:
    """Convert a local MCP server to use a wrapper for secret injection."""
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

    available = {k for k, v in secrets.items() if v}
    available |= {k for k, v in os.environ.items() if v}
    required_secrets = sorted(p for p in placeholders if p in available)
    missing = sorted(p for p in placeholders if p not in available)
    for placeholder in missing:
        msg = f"⚠️  Secret '{placeholder}' referenced by MCP server '{name}' is not defined"
        warnings.append(msg)

    spec = {
        "name": name,
        "command": command,
        "args": args,
        "env": env,
        "secrets": required_secrets,
    }
    if cwd:
        spec["cwd"] = str(cwd)

    spec_dir = os.path.expanduser(WRAPPER_SPEC_DIR)
    os.makedirs(spec_dir, exist_ok=True)
    spec_file = os.path.join(spec_dir, f"{name}.json")
    try:
        with open(spec_file, "w", encoding="utf-8") as handle:
            json.dump(spec, handle, indent=2, sort_keys=True)
    except OSError as exc:
        warnings.append(f"⚠️  Could not write wrapper spec for '{name}': {exc}")

    rendered_entry = dict(config)
    rendered_entry["command"] = WRAPPER_COMMAND.format(name=name)
    rendered_entry["args"] = []
    rendered_entry["env"] = {
        "CONTAINAI_WRAPPER_SPEC": spec_file,
        "CONTAINAI_WRAPPER_NAME": name,
    }
    return rendered_entry, spec


def process_servers(
    mcp_servers: Dict,
    secrets: Dict[str, str],
    missing_tokens: List[Tuple[str, str]],
    warnings: List[str],
    helpers: List[Dict],
    wrappers: List[Dict],
    known_helpers: Dict[str, Dict],
) -> Tuple[Dict, Dict[str, int]]:
    """Process and convert all MCP servers from the config."""
    resolved_servers: Dict = {}
    port_state = {"value": HELPER_PORT_BASE}

    for name, settings in mcp_servers.items():
        settings = dict(settings or {})
        if "command" in settings:
            rendered, spec = convert_local_server(name, settings, secrets, warnings)
            resolved_servers[name] = rendered
            wrappers.append(spec)
        else:
            rendered, helper_entry = convert_remote_server(
                name, settings, secrets, missing_tokens, port_state
            )
            resolved_servers[name] = rendered
            helpers.append(helper_entry)
            known_helpers[name] = helper_entry

    return resolved_servers, port_state


def rewrite_existing_servers(
    existing_servers: Dict,
    resolved_servers: Dict,
    secrets: Dict[str, str],
    missing_tokens: List[Tuple[str, str]],
    warnings: List[str],
    helpers: List[Dict],
    wrappers: List[Dict],
    known_helpers: Dict[str, Dict],
    port_state: Dict[str, int],
) -> Dict:
    """Rewrite existing servers to go through proxy mechanism."""
    rewritten_existing: Dict = {}
    for name, server_config in existing_servers.items():
        if name in resolved_servers:
            # Already handled by config.toml, skip
            continue
        if _is_already_proxied(server_config):
            # Already going through our proxy, keep as-is
            rewritten_existing[name] = server_config
        elif "command" in server_config:
            # Local server: wrap it
            rendered, spec = convert_local_server(
                name, server_config, secrets, warnings
            )
            rewritten_existing[name] = rendered
            wrappers.append(spec)
        elif "url" in server_config:
            # Remote server: route through helper proxy
            rewritten_existing[name] = _rewrite_remote_server(
                name,
                server_config,
                secrets,
                missing_tokens,
                helpers,
                known_helpers,
                port_state,
            )
        else:
            # Unknown format, preserve but warn
            msg = f"⚠️  Unknown MCP server format for '{name}', preserving unchanged"
            warnings.append(msg)
            rewritten_existing[name] = server_config
    return rewritten_existing


def _rewrite_remote_server(
    name: str,
    server_config: Dict,
    secrets: Dict[str, str],
    missing_tokens: List[Tuple[str, str]],
    helpers: List[Dict],
    known_helpers: Dict[str, Dict],
    port_state: Dict[str, int],
) -> Dict:
    """Rewrite a remote server to use helper proxy."""
    if name in known_helpers:
        # Reuse existing helper
        helper = known_helpers[name]
        rendered = dict(server_config)
        rendered.pop("bearer_token_env_var", None)
        for k, v in rendered.items():
            rendered[k] = resolve_value(v, secrets)
        rendered["url"] = f"http://{helper['listen']}"
        return rendered

    rendered, helper_entry = convert_remote_server(
        name, server_config, secrets, missing_tokens, port_state
    )
    helpers.append(helper_entry)
    known_helpers[name] = helper_entry
    return rendered


def _load_toml_config(config_path: str) -> Dict | None:
    """Load and parse the TOML config file."""
    if not os.path.exists(config_path):
        print(f"⚠️  No config.toml found at {config_path}", file=sys.stderr)
        return None
    try:
        with open(config_path, "rb") as handle:
            return tomllib.load(handle)
    except Exception as exc:  # pylint: disable=broad-except
        print(f"❌ Error parsing TOML: {exc}", file=sys.stderr)
        return None


def _write_agent_config(
    agent_name: str,
    agent_config_path: str,
    resolved_servers: Dict,
    secrets: Dict[str, str],
    missing_tokens: List[Tuple[str, str]],
    warnings: List[str],
    helpers: List[Dict],
    wrappers: List[Dict],
    known_helpers: Dict[str, Dict],
    port_state: Dict[str, int],
) -> bool:
    """Write MCP config for a single agent."""
    config_dir = os.path.expanduser(agent_config_path)
    os.makedirs(config_dir, exist_ok=True)
    config_file = os.path.join(config_dir, "config.json")

    existing_config, existing_servers = _load_existing_config(config_file, agent_name)

    rewritten_existing = rewrite_existing_servers(
        existing_servers,
        resolved_servers,
        secrets,
        missing_tokens,
        warnings,
        helpers,
        wrappers,
        known_helpers,
        port_state,
    )

    merged_servers = {**rewritten_existing, **resolved_servers}
    mcp_config = {**existing_config, "mcpServers": merged_servers}

    try:
        with open(config_file, "w", encoding="utf-8") as handle:
            json.dump(mcp_config, handle, indent=2)
        return True
    except Exception as exc:  # pylint: disable=broad-except
        print(f"❌ Error writing {agent_name} config: {exc}", file=sys.stderr)
        return False


def _load_existing_config(
    config_file: str, agent_name: str
) -> Tuple[Dict, Dict]:
    """Load existing agent config if present."""
    existing_config: Dict = {}
    existing_servers: Dict = {}
    if os.path.exists(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as handle:
                existing_config = json.load(handle)
                existing_servers = existing_config.get("mcpServers", {})
        except (json.JSONDecodeError, OSError) as exc:
            msg = f"⚠️  Could not read existing {agent_name} config, will overwrite: {exc}"
            print(msg, file=sys.stderr)
    return existing_config, existing_servers


def _write_helper_manifest(config_path: str, helpers: List[Dict]) -> None:
    """Write the helper proxy manifest."""
    helper_manifest = {"helpers": helpers, "source": str(config_path)}
    helper_path = os.path.expanduser("~/.config/containai/helpers.json")
    os.makedirs(os.path.dirname(helper_path), exist_ok=True)
    try:
        with open(helper_path, "w", encoding="utf-8") as handle:
            json.dump(helper_manifest, handle, indent=2, sort_keys=True)
    except Exception as exc:  # pylint: disable=broad-except
        print(f"⚠️  Unable to write helper manifest: {exc}", file=sys.stderr)


def _print_summary(
    config_path: str,
    resolved_servers: Dict,
    helpers: List[Dict],
    wrappers: List[Dict],
    missing_tokens: List[Tuple[str, str]],
    warnings: List[str],
) -> None:
    """Print conversion summary and warnings."""
    print("✅ MCP configurations generated for all agents")
    print(f"   Config source: {config_path}")
    server_names = ", ".join(sorted(resolved_servers.keys()))
    print(f"   Servers configured: {server_names}")
    if helpers:
        helper_names = ", ".join(h["name"] for h in helpers)
        print(f"   Remote servers (via helper proxy): {helper_names}")
    if wrappers:
        wrapper_names = ", ".join(w["name"] for w in wrappers)
        print(f"   Local servers (via wrapper): {wrapper_names}")

    for server_name, env_var in missing_tokens:
        msg = f"⚠️  Missing secret '{env_var}' for MCP server '{server_name}'"
        print(f"{msg} (bearer token not injected)", file=sys.stderr)
    for warning in warnings:
        print(warning, file=sys.stderr)


def convert_toml_to_mcp(config_path: str) -> bool:
    """Convert TOML config to MCP JSON format for all agents."""
    config = _load_toml_config(config_path)
    if config is None:
        return False

    mcp_servers = config.get("mcp_servers", {})
    if not mcp_servers:
        print("⚠️  No mcp_servers found in config.toml", file=sys.stderr)
        return False

    secrets = collect_secrets()
    missing_tokens: List[Tuple[str, str]] = []
    warnings: List[str] = []
    helpers: List[Dict] = []
    wrappers: List[Dict] = []
    known_helpers: Dict[str, Dict] = {}

    resolved_servers, port_state = process_servers(
        mcp_servers, secrets, missing_tokens, warnings, helpers, wrappers, known_helpers
    )

    for agent_name, agent_config_path in DEFAULT_AGENTS.items():
        if not _write_agent_config(
            agent_name,
            agent_config_path,
            resolved_servers,
            secrets,
            missing_tokens,
            warnings,
            helpers,
            wrappers,
            known_helpers,
            port_state,
        ):
            return False

    _write_helper_manifest(config_path, helpers)
    _print_summary(
        config_path, resolved_servers, helpers, wrappers, missing_tokens, warnings
    )
    return True


if __name__ == "__main__":
    toml_file = sys.argv[1] if len(sys.argv) > 1 else "/workspace/config.toml"
    success = convert_toml_to_mcp(toml_file)
    sys.exit(0 if success else 1)
