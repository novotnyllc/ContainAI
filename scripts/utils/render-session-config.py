#!/usr/bin/env python3
"""Render host-side session MCP configs with runtime metadata."""

from __future__ import annotations

import argparse
import ast
import datetime as _dt
import hashlib
import json
import os
import pathlib
import sys
from typing import Dict, List, Optional

AGENT_CONFIG_TARGETS: Dict[str, str] = {
    "github-copilot": "/home/agentuser/.config/github-copilot/mcp/config.json",
    "codex": "/home/agentuser/.config/codex/mcp/config.json",
    "claude": "/home/agentuser/.config/claude/mcp/config.json",
}


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
    except Exception:
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
) -> Dict:
    config_data: Dict = {}
    source_exists = config_path is not None and config_path.exists()
    config_sha = _sha256_file(config_path) if source_exists else None

    if source_exists:
        config_data = _read_toml(config_path)
    else:
        config_data = {"mcp_servers": {}}

    mcp_servers = config_data.get("mcp_servers", {}) or {}
    generated_at = _dt.datetime.now(_dt.timezone.utc).isoformat()

    files: List[Dict] = []
    server_names = sorted(mcp_servers.keys())
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
            "mcpServers": mcp_servers,
        }
        content = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
        agent_dir = output_dir / agent_key
        _ensure_directory(agent_dir)
        dest = agent_dir / "config.json"
        dest.write_bytes(content)
        files.append(
            {
                "agent": agent_key,
                "path": str(dest),
                "sha256": _sha256_bytes(content),
                "target": target_path,
            }
        )

    manifest = {
        "sessionId": session_id,
        "generatedAt": generated_at,
        "configSource": str(config_path) if config_path else None,
        "configSourceSha256": config_sha,
        "gitHead": git_head,
        "trustedTrees": trusted_tree_hashes,
        "servers": server_names,
        "files": files,
    }

    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
    servers_path = output_dir / "servers.txt"
    if server_names:
        servers_path.write_text("\n".join(server_names) + "\n", encoding="utf-8")
    else:
        servers_path.write_text("", encoding="utf-8")
    manifest["manifestPath"] = str(manifest_path)
    manifest["manifestSha256"] = _sha256_file(manifest_path)
    return manifest


def parse_args(argv: List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", dest="config", type=pathlib.Path, help="Path to config.toml")
    parser.add_argument("--output", dest="output", type=pathlib.Path, required=True, help="Output directory")
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
    return parser.parse_args(argv)


def main(argv: List[str]) -> int:
    args = parse_args(argv)
    output_dir = args.output
    _ensure_directory(output_dir)

    config_path = args.config if args.config and args.config.exists() else None
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
    )

    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
