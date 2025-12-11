#!/usr/bin/env python3
"""Render host-side session MCP configs with runtime metadata."""

from __future__ import annotations

import argparse
import ast
import base64
import datetime as _dt
import hashlib
import json
import os
import pathlib
import re
import sys
from typing import Dict, List, Optional, Set, Tuple

# Allow import of sibling modules
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from _mcp_common import (  # noqa: E402  # pylint: disable=wrong-import-position
    ENV_PATTERN,
    collect_placeholders as _collect_placeholders,
    load_secret_file,
    resolve_value as _resolve_value,
)

AGENT_CONFIG_TARGETS: Dict[str, str] = {
    "github-copilot": "/home/agentuser/.config/github-copilot/mcp/config.json",
    "codex": "/home/agentuser/.config/codex/mcp/config.json",
    "claude": "/home/agentuser/.config/claude/mcp/config.json",
}
STUB_COMMAND_TEMPLATE = "/home/agentuser/.local/bin/mcp-stub-{name}"
HELPER_LISTEN_HOST = "127.0.0.1"
HELPER_PORT_BASE = 52100
DEFAULT_CONFIG_ROOT = pathlib.Path(
    os.environ.get(
        "CONTAINAI_CONFIG_ROOT", pathlib.Path.home() / ".config" / "containai-dev"
    )
)
DEFAULT_HELPER_ACL_CONFIG = pathlib.Path(
    os.environ.get(
        "CONTAINAI_SQUID_HELPERS_CONFIG", DEFAULT_CONFIG_ROOT / "squid-helpers.json"
    )
)
DEFAULT_SECRET_PATHS = [
    pathlib.Path("~/.config/containai/mcp-secrets.env").expanduser(),
    pathlib.Path("~/.mcp-secrets.env").expanduser(),
]


def _collect_secrets(explicit_files: List[pathlib.Path]) -> Dict[str, str]:
    """Collect secrets from multiple file sources."""
    candidates: List[pathlib.Path] = []

    # Check environment overrides first
    env_override = os.environ.get("CONTAINAI_MCP_SECRETS_FILE") or os.environ.get(
        "MCP_SECRETS_FILE"
    )
    if env_override:
        candidates.append(pathlib.Path(env_override).expanduser())

    # Add explicit files and defaults
    candidates.extend(explicit_files)
    candidates.extend(DEFAULT_SECRET_PATHS)

    merged_secrets: Dict[str, str] = {}
    processed_paths: Set[str] = set()

    for file_path in candidates:
        resolved_path = file_path.expanduser()
        path_key = str(resolved_path)

        if path_key in processed_paths:
            continue

        processed_paths.add(path_key)
        file_secrets = load_secret_file(resolved_path)

        # Only add secrets that haven't been defined yet (first wins)
        for key, value in file_secrets.items():
            if key not in merged_secrets:
                merged_secrets[key] = value

    return merged_secrets


def _load_acl_policies(path: pathlib.Path) -> Dict[str, Dict[str, Dict[str, List[str]]]]:
    if not path.exists():
        return {"helpers": {}, "agents": {}}
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {"helpers": {}, "agents": {}}
    helpers_raw = data.get("helpers", []) if isinstance(data, dict) else data
    agents_raw = data.get("agents", []) if isinstance(data, dict) else []
    helpers: Dict[str, Dict[str, List[str]]] = {}
    agents: Dict[str, Dict[str, List[str]]] = {}
    for entry, target in ((helpers_raw, helpers), (agents_raw, agents)):
        for item in entry:
            if not isinstance(item, dict):
                continue
            name = item.get("name")
            if not name:
                continue
            allow = item.get("allow") or item.get("domains") or []
            block = item.get("block") or item.get("deny") or []
            if not isinstance(allow, list) or not isinstance(block, list):
                continue
            target[name] = {"allow": [str(d) for d in allow], "block": [str(d) for d in block]}
    return {"helpers": helpers, "agents": agents}


def _write_squid_acls(
    output_path: pathlib.Path,
    helpers: List[Dict[str, object]],
    policies: Dict[str, Dict[str, Dict[str, List[str]]]],
) -> None:
    lines: List[str] = [
        "# Auto-generated helper ACLs",
        "# Each helper must present X-CA-Helper header; allow lists are per helper",
    ]
    agent_policies = policies.get("agents", {})
    for agent_name, policy in agent_policies.items():
        lines.append(f"acl agent_hdr_{agent_name} req_header X-CA-Agent {agent_name}")
        if policy.get("block"):
            lines.append(f"acl agent_block_{agent_name} dstdomain {' '.join(policy['block'])}")
            lines.append(f"http_access deny agent_hdr_{agent_name} agent_block_{agent_name}")
        if policy.get("allow"):
            lines.append(f"acl agent_allow_{agent_name} dstdomain {' '.join(policy['allow'])}")
            lines.append(f"http_access allow agent_hdr_{agent_name} agent_allow_{agent_name}")
        else:
            lines.append(f"http_access allow agent_hdr_{agent_name} allowed_domains")

    seen = set()
    helper_policies = policies.get("helpers", {})
    for helper in helpers:
        name = str(helper.get("name", "")).strip()
        if not name or name in seen:
            continue
        seen.add(name)
        lines.append(f"acl helper_hdr_{name} req_header X-CA-Helper {name}")
        policy = helper_policies.get(name, {})
        allow_domains = policy.get("allow", [])
        block_domains = policy.get("block", [])
        if block_domains:
            lines.append(f"acl helper_block_{name} dstdomain {' '.join(block_domains)}")
            lines.append(f"http_access deny helper_hdr_{name} helper_block_{name}")
        if allow_domains:
            lines.append(f"acl helper_allow_{name} dstdomain {' '.join(allow_domains)}")
            lines.append(f"http_access allow helper_hdr_{name} helper_allow_{name}")
        else:
            lines.append(f"http_access allow helper_hdr_{name} allowed_domains")
    if not seen:
        lines.append("acl helper_hdr_default req_header X-CA-Helper .")
        lines.append("http_access allow helper_hdr_default allowed_domains")
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _encode_stub_spec(spec: Dict) -> str:
    payload = json.dumps(spec, sort_keys=True).encode("utf-8")
    return base64.b64encode(payload).decode("ascii")


def _sha256_file(path: pathlib.Path) -> Optional[str]:
    if not path.exists():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _sha256_bytes(data: bytes) -> str:
    digest = hashlib.sha256()
    digest.update(data)
    return digest.hexdigest()


def _parse_value(raw: str):
    candidate = raw.strip()
    lowered = candidate.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    try:
        return ast.literal_eval(candidate)
    except (ValueError, TypeError, SyntaxError, MemoryError, RecursionError):
        return candidate.strip('"').strip("'")


def _read_toml(path: pathlib.Path) -> Dict:
    result: Dict = {}
    current: Dict = result
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1].strip()
                current = result
                for part in section.split('.'):
                    current = current.setdefault(part, {})  # type: ignore[assignment]
                continue
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            current[key] = _parse_value(value)
    return result


def _ensure_directory(path: pathlib.Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def _render_remote_server(
    name: str,
    settings: Dict,
    secrets: Dict[str, str],
    warnings: List[str],
    next_port,
) -> Tuple[Dict, Dict]:
    rendered: Dict = {}
    bearer_var = settings.get("bearer_token_env_var")
    bearer_token = None
    for key, value in settings.items():
        if key == "bearer_token_env_var":
            continue
        rendered[key] = _resolve_value(value, secrets)
    if bearer_var:
        token = secrets.get(bearer_var) or os.environ.get(bearer_var)
        if token:
            bearer_token = token
            rendered["bearerToken"] = token
        else:
            warnings.append(
                f"⚠️  Missing bearer token '{bearer_var}' for MCP server '{name}'"
            )
    listen_port = next_port()
    listen_addr = f"{HELPER_LISTEN_HOST}:{listen_port}"
    target_url = rendered.get("url") or ""
    rendered["url"] = f"http://{listen_addr}"
    helper_entry = {
        "name": name,
        "listen": listen_addr,
        "target": target_url,
    }
    if bearer_token:
        helper_entry["bearerToken"] = bearer_token
    return rendered, helper_entry


def _render_stub_server(
    name: str,
    settings: Dict,
    secrets: Dict[str, str],
    warnings: List[str],
) -> Tuple[Dict, List[str]]:
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

    placeholder_names = _collect_placeholders(command)
    placeholder_names.update(_collect_placeholders(args))
    placeholder_names.update(_collect_placeholders(env))
    if cwd:
        placeholder_names.update(_collect_placeholders(cwd))
    available_names = set(secrets.keys()) | {k for k, v in os.environ.items() if v}
    stub_secrets = sorted(name for name in placeholder_names if name in available_names)
    missing = sorted(name for name in placeholder_names if name not in available_names)
    for placeholder in missing:
        warnings.append(
            f"⚠️  Secret '{placeholder}' referenced by MCP server '{name}' is not defined"
        )

    spec: Dict[str, object] = {
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
        "CONTAINAI_STUB_SPEC": _encode_stub_spec(spec),
        "CONTAINAI_STUB_NAME": name,
    }
    return rendered_entry, stub_secrets


def _process_source_servers(
    source_servers: Dict,
    secrets: Dict[str, str],
    warnings: List[str],
    helpers: List[Dict],
    port_counter: Dict[str, int],
) -> Tuple[Dict[str, Dict], Dict[str, List[str]], List[str]]:
    """Process source servers and return rendered servers, secret map, and stub names."""
    rendered_servers: Dict[str, Dict] = {}
    stub_secret_map: Dict[str, List[str]] = {}
    stubbed_server_names: List[str] = []

    def _next_port() -> int:
        port = port_counter["value"]
        port_counter["value"] += 1
        return port

    for server_name, server_cfg in source_servers.items():
        settings = dict(server_cfg or {})
        if "command" in settings:
            rendered_entry, stub_secrets = _render_stub_server(
                server_name, settings, secrets, warnings
            )
            rendered_servers[server_name] = rendered_entry
            if stub_secrets:
                stub_secret_map[server_name] = stub_secrets
            stubbed_server_names.append(server_name)
        else:
            rendered_entry, helper = _render_remote_server(
                server_name, settings, secrets, warnings, _next_port
            )
            rendered_servers[server_name] = rendered_entry
            helpers.append(helper)

    return rendered_servers, stub_secret_map, stubbed_server_names


def _write_agent_configs(
    output_dir: pathlib.Path,
    session_id: str,
    agent_name: str,
    container_name: str,
    network_policy: str,
    repo_name: str,
    generated_at: str,
    rendered_servers: Dict[str, Dict],
) -> List[Dict]:
    """Write agent-specific config files and return file metadata."""
    files: List[Dict] = []
    for agent_key, target_path in AGENT_CONFIG_TARGETS.items():
        payload = {
            "session": {
                "id": session_id,
                "agent": agent_name,
                "container": container_name,
                "networkPolicy": network_policy,
                "generatedAt": generated_at,
                "target": target_path,
                "sourceRepo": repo_name,
            },
            "mcpServers": rendered_servers,
        }
        content = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
        agent_dir = output_dir / agent_key
        _ensure_directory(agent_dir)
        dest = agent_dir / "config.json"
        dest.write_bytes(content)
        files.append({
            "agent": agent_key,
            "path": str(dest),
            "sha256": _sha256_bytes(content),
            "target": target_path,
        })
    return files


def _write_manifest_files(
    output_dir: pathlib.Path,
    stub_secret_map: Dict[str, List[str]],
    stubbed_server_names: List[str],
    helpers: List[Dict],
) -> Tuple[pathlib.Path, pathlib.Path, pathlib.Path]:
    """Write manifest auxiliary files and return their paths."""
    servers_path = output_dir / "servers.txt"
    if stubbed_server_names:
        servers_path.write_text("\n".join(stubbed_server_names) + "\n", encoding="utf-8")
    else:
        servers_path.write_text("", encoding="utf-8")

    stub_secret_path = output_dir / "stub-secrets.txt"
    with stub_secret_path.open("w", encoding="utf-8") as handle:
        for stub in sorted(stub_secret_map.keys()):
            names = stub_secret_map[stub]
            if names:
                handle.write(f"{stub} {' '.join(names)}\n")

    helpers_path = output_dir / "helpers.json"
    helpers_content = json.dumps(helpers, indent=2, sort_keys=True)
    helpers_path.write_text(helpers_content, encoding="utf-8")

    return servers_path, stub_secret_path, helpers_path


def render_configs(
    *,
    config_path: Optional[pathlib.Path],
    output_dir: pathlib.Path,
    session_id: str,
    network_policy: str,
    repo_name: str,
    agent_name: str,
    container_name: str,
    trusted_tree_hashes: List[str],
    git_head: Optional[str],
    secrets: Dict[str, str],
) -> Dict:
    """Render MCP configs for a session."""
    source_exists = config_path is not None and config_path.exists()
    config_sha = _sha256_file(config_path) if source_exists else None
    helpers: List[Dict] = []
    acl_policies = _load_acl_policies(DEFAULT_HELPER_ACL_CONFIG)
    port_counter = {"value": HELPER_PORT_BASE}
    warnings: List[str] = []

    config_data = _read_toml(config_path) if source_exists else {"mcp_servers": {}}
    source_servers = config_data.get("mcp_servers", {}) or {}
    generated_at = _dt.datetime.now(_dt.timezone.utc).isoformat()

    rendered_servers, stub_secret_map, stubbed_server_names = _process_source_servers(
        source_servers, secrets, warnings, helpers, port_counter
    )

    all_server_names = sorted(source_servers.keys())
    stubbed_server_names = sorted(set(stubbed_server_names))

    files = _write_agent_configs(
        output_dir, session_id, agent_name, container_name,
        network_policy, repo_name, generated_at, rendered_servers
    )

    acl_path = output_dir / "squid-acls.conf"
    _write_squid_acls(acl_path, helpers, acl_policies)

    _, stub_secret_path, helpers_path = _write_manifest_files(
        output_dir, stub_secret_map, stubbed_server_names, helpers
    )

    manifest = {
        "sessionId": session_id,
        "generatedAt": generated_at,
        "configSource": str(config_path) if config_path else None,
        "configSourceSha256": config_sha,
        "gitHead": git_head,
        "trustedTrees": trusted_tree_hashes,
        "servers": stubbed_server_names,
        "allServers": all_server_names,
        "stubSecrets": stub_secret_map,
        "files": files,
        "helpers": helpers,
        "helperAclPath": str(acl_path),
    }

    manifest_path = output_dir / "manifest.json"
    manifest_content = json.dumps(manifest, indent=2, sort_keys=True)
    manifest_path.write_text(manifest_content, encoding="utf-8")

    manifest["manifestPath"] = str(manifest_path)
    manifest["manifestSha256"] = _sha256_file(manifest_path)
    manifest["stubSecretFile"] = str(stub_secret_path)
    manifest["helpersPath"] = str(helpers_path)

    for warning in warnings:
        print(warning, file=sys.stderr)

    return manifest


def parse_args(argv: List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", dest="config", type=pathlib.Path, help="Path to config.toml")
    parser.add_argument(
        "--output",
        dest="output",
        type=pathlib.Path,
        required=True,
        help="Output directory",
    )
    parser.add_argument("--session-id", dest="session_id", required=True)
    parser.add_argument("--network-policy", dest="network_policy", required=True)
    parser.add_argument("--repo", dest="repo_name", default="")
    parser.add_argument("--agent", dest="agent", required=True)
    parser.add_argument("--container", dest="container", required=True)
    parser.add_argument(
        "--trusted-hash",
        dest="trusted_hashes",
        action="append",
        default=[],
        help="Trusted tree hash entry in the form path=hash",
    )
    parser.add_argument("--git-head", dest="git_head", default=None)
    parser.add_argument(
        "--secrets-file",
        dest="secret_files",
        action="append",
        type=pathlib.Path,
        default=[],
        help="Additional secrets env files to read",
    )
    return parser.parse_args(argv)


def main(argv: List[str]) -> int:
    args = parse_args(argv)
    output_dir = args.output
    _ensure_directory(output_dir)

    config_path = args.config if args.config and args.config.exists() else None
    secrets = _collect_secrets(args.secret_files or [])
    manifest = render_configs(
        config_path=config_path,
        output_dir=output_dir,
        session_id=args.session_id,
        network_policy=args.network_policy,
        repo_name=args.repo_name,
        agent_name=args.agent,
        container_name=args.container,
        trusted_tree_hashes=args.trusted_hashes,
        git_head=args.git_head,
        secrets=secrets,
    )

    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
