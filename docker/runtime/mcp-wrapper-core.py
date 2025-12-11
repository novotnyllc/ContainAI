#!/usr/bin/env python3
"""MCP Wrapper - Secure secret injection for local MCP servers.

Reads a wrapper spec from ~/.config/containai/wrappers/<name>.json,
loads sealed secrets from the capability store, decrypts them using
the session key, substitutes ${VAR} placeholders, and execs the real
MCP server command.

Spec format:
{
    "name": "my-tool",
    "command": "/usr/local/bin/my-tool", 
    "args": ["--mode", "mcp"],
    "env": {"API_KEY": "${MY_API_KEY}"},
    "cwd": "/workspace",
    "secrets": ["MY_API_KEY"]
}
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import sys
from typing import Dict, Iterable, List, Tuple

PLACEHOLDER_PATTERN = re.compile(r"\$\{(?P<braced>[A-Za-z_][A-Za-z0-9_]*)\}|\$(?P<bare>[A-Za-z_][A-Za-z0-9_]*)")
DEFAULT_CAP_ROOT = os.path.expanduser("~/.config/containai/capabilities")
SPEC_FILE_ENV_VAR = "CONTAINAI_WRAPPER_SPEC"
WRAPPER_NAME_ENV_VAR = "CONTAINAI_WRAPPER_NAME"
CAP_ROOT_ENV_VAR = "CONTAINAI_CAP_ROOT"


class WrapperError(RuntimeError):
    """Exception raised when wrapper execution cannot continue."""


def _die(message: str) -> None:
    print(f"mcp-wrapper: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_wrapper_spec() -> Dict:
    """Load the wrapper spec from CONTAINAI_WRAPPER_SPEC."""
    spec_path = os.environ.get(SPEC_FILE_ENV_VAR)
    if not spec_path:
        raise WrapperError(f"missing {SPEC_FILE_ENV_VAR} environment variable")
    
    spec_path = os.path.expanduser(spec_path)
    if not os.path.exists(spec_path):
        raise WrapperError(f"wrapper spec file not found: {spec_path}")
    
    try:
        with open(spec_path, "r", encoding="utf-8") as handle:
            spec = json.load(handle)
    except json.JSONDecodeError as exc:
        raise WrapperError(f"wrapper spec is not valid JSON: {exc}") from exc
    except OSError as exc:
        raise WrapperError(f"cannot read wrapper spec: {exc}") from exc
    
    if "name" not in spec:
        raise WrapperError("wrapper spec missing 'name' field")
    if "command" not in spec:
        raise WrapperError("wrapper spec missing 'command' field")
    
    spec.setdefault("args", [])
    spec.setdefault("env", {})
    spec.setdefault("secrets", [])
    return spec


def resolve_capability_dir(wrapper_name: str) -> pathlib.Path:
    """Find the capability directory for this wrapper."""
    base = os.environ.get(CAP_ROOT_ENV_VAR, DEFAULT_CAP_ROOT)
    path = pathlib.Path(base).expanduser() / wrapper_name
    if not path.exists():
        raise WrapperError(f"capability directory missing for wrapper '{wrapper_name}' at {path}")
    if not path.is_dir():
        raise WrapperError(f"{path} is not a directory")
    return path


def _load_json(path: pathlib.Path) -> Dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise WrapperError(f"cannot parse JSON from {path}: {exc}") from exc
    except OSError as exc:
        raise WrapperError(f"unable to read {path}: {exc}") from exc


def _select_capability(wrapper_dir: pathlib.Path) -> Tuple[Dict, pathlib.Path]:
    """Select the most recent valid capability token for this wrapper."""
    candidates = sorted(wrapper_dir.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not candidates:
        raise WrapperError(f"no capability tokens found under {wrapper_dir}")
    now = dt.datetime.now(dt.timezone.utc)
    wrapper_name = wrapper_dir.name
    for candidate in candidates:
        token = _load_json(candidate)
        if token.get("name") != wrapper_name:
            continue
        expires = token.get("expires_at")
        if not expires:
            continue
        try:
            expiry = dt.datetime.fromisoformat(expires)
        except ValueError:
            continue
        if expiry <= now:
            continue
        if "session_key" not in token:
            continue
        return token, candidate
    raise WrapperError(f"no valid (unexpired) capabilities available for wrapper '{wrapper_name}'")


def _xor_stream(key_hex: str, data: bytes) -> bytes:
    """Decrypt data using XOR stream cipher with session key."""
    if not key_hex:
        raise WrapperError("empty session key in capability token")
    try:
        key_bytes = bytes.fromhex(key_hex)
    except ValueError as exc:
        raise WrapperError(f"invalid session key: {exc}") from exc
    if not key_bytes:
        raise WrapperError("session key cannot decode to empty byte string")
    xor_block = hashlib.sha256(key_bytes).digest()
    key_index = 0
    output = bytearray()
    for byte in data:
        output.append(byte ^ xor_block[key_index])
        key_index += 1
        if key_index >= len(xor_block):
            xor_block = hashlib.sha256(xor_block).digest()
            key_index = 0
    return bytes(output)


import base64


def _load_sealed_secret(capability: Dict, secret_name: str, secrets_dir: pathlib.Path) -> str:
    """Load and decrypt a sealed secret using the capability's session key."""
    sealed_path = secrets_dir / f"{secret_name}.sealed"
    if not sealed_path.is_file():
        raise WrapperError(f"sealed secret '{secret_name}' missing at {sealed_path}")
    record = _load_json(sealed_path)
    if record.get("name") != capability.get("name"):
        raise WrapperError(f"sealed secret '{secret_name}' does not match wrapper '{capability.get('name')}'")
    if record.get("capability_id") != capability.get("capability_id"):
        raise WrapperError(f"sealed secret '{secret_name}' not bound to capability {capability.get('capability_id')}")
    ciphertext = record.get("ciphertext")
    if not ciphertext:
        raise WrapperError(f"sealed secret '{secret_name}' missing ciphertext")
    try:
        cipher_bytes = base64.b64decode(ciphertext)
    except Exception as exc:
        raise WrapperError(f"sealed secret '{secret_name}' ciphertext invalid: {exc}") from exc
    plain = _xor_stream(capability.get("session_key", ""), cipher_bytes)
    try:
        return plain.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise WrapperError(f"sealed secret '{secret_name}' is not valid UTF-8: {exc}") from exc


def load_secrets(capability: Dict, wrapper_dir: pathlib.Path, secret_names: Iterable[str]) -> Dict[str, str]:
    """Load and decrypt all required secrets for this wrapper."""
    if not secret_names:
        return {}
    secrets_dir = wrapper_dir / "secrets"
    if not secrets_dir.is_dir():
        raise WrapperError(f"sealed secret directory missing at {secrets_dir}")
    resolved: Dict[str, str] = {}
    for name in secret_names:
        if not name:
            continue
        resolved[name] = _load_sealed_secret(capability, name, secrets_dir)
    return resolved


def _substitute_placeholders(value, secret_map: Dict[str, str]):
    """Replace ${VAR} placeholders with actual secret values."""
    if isinstance(value, str):
        def _replace(match: re.Match[str]) -> str:
            candidate = match.group("braced") or match.group("bare")
            if candidate in secret_map:
                return secret_map[candidate]
            return match.group(0)

        return PLACEHOLDER_PATTERN.sub(_replace, value)
    if isinstance(value, list):
        return [_substitute_placeholders(item, secret_map) for item in value]
    if isinstance(value, dict):
        return {key: _substitute_placeholders(val, secret_map) for key, val in value.items()}
    return value


def prepare_command(spec: Dict, secret_map: Dict[str, str]) -> Tuple[str, List[str], Dict[str, str]]:
    """Prepare the final command, args, and env with secrets substituted."""
    command = _substitute_placeholders(spec.get("command", ""), secret_map)
    if not isinstance(command, str) or not command:
        raise WrapperError("resolved command is empty")
    raw_args = spec.get("args", [])
    if not isinstance(raw_args, list):
        raise WrapperError("wrapper spec 'args' must be a list")
    args = []
    for item in raw_args:
        substituted = _substitute_placeholders(item, secret_map)
        if not isinstance(substituted, str):
            substituted = str(substituted)
        args.append(substituted)
    raw_env = spec.get("env", {})
    if not isinstance(raw_env, dict):
        raise WrapperError("wrapper spec 'env' must be an object of string pairs")
    resolved_env: Dict[str, str] = {}
    for key, value in raw_env.items():
        if not isinstance(key, str):
            raise WrapperError("environment variable names must be strings")
        substituted = _substitute_placeholders(value, secret_map)
        if isinstance(substituted, (dict, list)):
            raise WrapperError(f"environment variable '{key}' must resolve to a string")
        resolved_env[key] = str(substituted)
    return command, args, resolved_env


def scrub_wrapper_env(env: Dict[str, str]) -> Dict[str, str]:
    """Remove wrapper-specific env vars before exec'ing the real command."""
    env = dict(env)
    env.pop(SPEC_FILE_ENV_VAR, None)
    # CONTAINAI_WRAPPER_NAME is preserved for the child process
    return env


def main() -> None:
    try:
        spec = load_wrapper_spec()
        wrapper_name = spec.get("name")
        capability_dir = resolve_capability_dir(wrapper_name)
        capability, token_path = _select_capability(capability_dir)
        if capability.get("name") != wrapper_name:
            raise WrapperError(
                f"capability token '{token_path}' targets '{capability.get('name')}', expected '{wrapper_name}'"
            )
        secret_names = spec.get("secrets", [])
        if not isinstance(secret_names, list):
            raise WrapperError("wrapper spec 'secrets' must be a list")
        secrets = load_secrets(capability, capability_dir, secret_names)
        command, args, command_env = prepare_command(spec, secrets)
        merged_env = scrub_wrapper_env(os.environ)
        merged_env.update(command_env)
        workdir = spec.get("cwd")
        if isinstance(workdir, str) and workdir.strip():
            os.chdir(workdir)
    except WrapperError as exc:
        _die(str(exc))

    os.execvpe(command, [command] + args, merged_env)


if __name__ == "__main__":
    main()
