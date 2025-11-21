#!/usr/bin/env python3
"""Broker-enforced MCP stub wrapper.

Decodes a launcher-provided stub specification, decrypts sealed secrets
using the session key embedded in the capability token, and then `exec`s
the real MCP server command with placeholders substituted.
"""

from __future__ import annotations

import base64
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
SPEC_ENV_VAR = "CONTAINAI_STUB_SPEC"
CAP_ROOT_ENV_VAR = "CONTAINAI_CAP_ROOT"


class StubError(RuntimeError):
    """Exception raised when stub execution cannot continue."""


def _die(message: str) -> None:
    print(f"mcp-stub: {message}", file=sys.stderr)
    raise SystemExit(1)


def _decode_spec(raw: str) -> Dict:
    try:
        decoded = base64.b64decode(raw)
    except Exception as exc:  # pragma: no cover - defensive
        raise StubError(f"invalid base64 stub spec: {exc}") from exc
    try:
        return json.loads(decoded)
    except json.JSONDecodeError as exc:  # pragma: no cover - defensive
        raise StubError(f"stub spec is not valid JSON: {exc}") from exc


def load_stub_spec() -> Dict:
    raw = os.environ.get(SPEC_ENV_VAR)
    if not raw:
        raise StubError(f"missing {SPEC_ENV_VAR} environment variable")
    spec = _decode_spec(raw)
    if "stub" not in spec:
        raise StubError("stub spec missing 'stub' field")
    if "command" not in spec:
        raise StubError("stub spec missing 'command' field")
    spec.setdefault("args", [])
    spec.setdefault("env", {})
    spec.setdefault("secrets", [])
    return spec


def resolve_capability_dir(stub: str) -> pathlib.Path:
    base = os.environ.get(CAP_ROOT_ENV_VAR, DEFAULT_CAP_ROOT)
    path = pathlib.Path(base).expanduser() / stub
    if not path.exists():
        raise StubError(f"capability directory missing for stub '{stub}' at {path}")
    if not path.is_dir():
        raise StubError(f"{path} is not a directory")
    return path


def _load_json(path: pathlib.Path) -> Dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise StubError(f"cannot parse JSON from {path}: {exc}") from exc
    except OSError as exc:
        raise StubError(f"unable to read {path}: {exc}") from exc


def _select_capability(stub_dir: pathlib.Path) -> Tuple[Dict, pathlib.Path]:
    candidates = sorted(stub_dir.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not candidates:
        raise StubError(f"no capability tokens found under {stub_dir}")
    now = dt.datetime.now(dt.timezone.utc)
    for candidate in candidates:
        token = _load_json(candidate)
        if token.get("stub") != stub_dir.name:
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
    raise StubError(f"no valid (unexpired) capabilities available for stub '{stub_dir.name}'")


def _xor_stream(key_hex: str, data: bytes) -> bytes:
    if not key_hex:
        raise StubError("empty session key in capability token")
    try:
        key_bytes = bytes.fromhex(key_hex)
    except ValueError as exc:
        raise StubError(f"invalid session key: {exc}") from exc
    if not key_bytes:
        raise StubError("session key cannot decode to empty byte string")
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


def _load_sealed_secret(capability: Dict, secret_name: str, secrets_dir: pathlib.Path) -> str:
    sealed_path = secrets_dir / f"{secret_name}.sealed"
    if not sealed_path.is_file():
        raise StubError(f"sealed secret '{secret_name}' missing at {sealed_path}")
    record = _load_json(sealed_path)
    if record.get("stub") != capability.get("stub"):
        raise StubError(f"sealed secret '{secret_name}' does not match stub '{capability.get('stub')}'")
    if record.get("capability_id") != capability.get("capability_id"):
        raise StubError(f"sealed secret '{secret_name}' not bound to capability {capability.get('capability_id')}")
    ciphertext = record.get("ciphertext")
    if not ciphertext:
        raise StubError(f"sealed secret '{secret_name}' missing ciphertext")
    try:
        cipher_bytes = base64.b64decode(ciphertext)
    except Exception as exc:
        raise StubError(f"sealed secret '{secret_name}' ciphertext invalid: {exc}") from exc
    plain = _xor_stream(capability.get("session_key", ""), cipher_bytes)
    try:
        return plain.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise StubError(f"sealed secret '{secret_name}' is not valid UTF-8: {exc}") from exc


def load_secrets(capability: Dict, stub_dir: pathlib.Path, secret_names: Iterable[str]) -> Dict[str, str]:
    secrets_dir = stub_dir / "secrets"
    if not secrets_dir.is_dir():
        raise StubError(f"sealed secret directory missing at {secrets_dir}")
    resolved: Dict[str, str] = {}
    for name in secret_names:
        if not name:
            continue
        resolved[name] = _load_sealed_secret(capability, name, secrets_dir)
    return resolved


def _substitute_placeholders(value, secret_map: Dict[str, str]):
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
    command = _substitute_placeholders(spec.get("command", ""), secret_map)
    if not isinstance(command, str) or not command:
        raise StubError("resolved command is empty")
    raw_args = spec.get("args", [])
    if not isinstance(raw_args, list):
        raise StubError("stub spec 'args' must be a list")
    args = []
    for item in raw_args:
        substituted = _substitute_placeholders(item, secret_map)
        if not isinstance(substituted, str):
            substituted = str(substituted)
        args.append(substituted)
    raw_env = spec.get("env", {})
    if not isinstance(raw_env, dict):
        raise StubError("stub spec 'env' must be an object of string pairs")
    resolved_env: Dict[str, str] = {}
    for key, value in raw_env.items():
        if not isinstance(key, str):
            raise StubError("environment variable names must be strings")
        substituted = _substitute_placeholders(value, secret_map)
        if isinstance(substituted, (dict, list)):
            raise StubError(f"environment variable '{key}' must resolve to a string")
        resolved_env[key] = str(substituted)
    return command, args, resolved_env


def scrub_stub_env(env: Dict[str, str]) -> Dict[str, str]:
    env = dict(env)
    env.pop(SPEC_ENV_VAR, None)
    return env


def main() -> None:
    try:
        spec = load_stub_spec()
        stub_name = spec.get("stub")
        capability_dir = resolve_capability_dir(stub_name)
        capability, token_path = _select_capability(capability_dir)
        if capability.get("stub") != stub_name:
            raise StubError(
                f"capability token '{token_path}' targets '{capability.get('stub')}', expected '{stub_name}'"
            )
        secret_names = spec.get("secrets", [])
        if not isinstance(secret_names, list):
            raise StubError("stub spec 'secrets' must be a list")
        secrets = load_secrets(capability, capability_dir, secret_names)
        command, args, command_env = prepare_command(spec, secrets)
        merged_env = scrub_stub_env(os.environ)
        merged_env.update(command_env)
        workdir = spec.get("cwd")
        if isinstance(workdir, str) and workdir.strip():
            os.chdir(workdir)
    except StubError as exc:
        _die(str(exc))

    os.execvpe(command, [command] + args, merged_env)


if __name__ == "__main__":
    main()
