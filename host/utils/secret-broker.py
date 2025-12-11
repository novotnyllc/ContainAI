#!/usr/bin/env python3
"""Host-side secret broker utilities for capability issuance and redemption."""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import pathlib
import secrets
import subprocess
import sys
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Dict, List

CONFIG_ROOT = pathlib.Path(
    os.environ.get(
        "CONTAINAI_CONFIG_DIR", pathlib.Path.home() / ".config" / "containai"
    )
)
BROKER_DIR = pathlib.Path(os.environ.get("CONTAINAI_BROKER_DIR", CONFIG_ROOT / "broker.d"))
KEY_FILE = BROKER_DIR / "keys.json"
STATE_FILE = BROKER_DIR / "state.json"
SECRETS_FILE = BROKER_DIR / "secrets.json"
DEFAULT_STUBS = [
    "github",
    "uno",
    "msftdocs",
    "playwright",
    "context7",
    "serena",
    "sequential-thinking",
    "fetch",
    "agent_copilot_cli",
    "agent_codex_cli",
    "agent_claude_cli",
]
ISSUE_WINDOW_SECONDS = int(os.environ.get("CONTAINAI_BROKER_RATE_WINDOW", "60"))
ISSUE_WINDOW_LIMIT = int(os.environ.get("CONTAINAI_BROKER_RATE_LIMIT", "30"))
DEFAULT_TTL_MINUTES = int(os.environ.get("CONTAINAI_BROKER_TTL", "30"))


def _ensure_dir(path: pathlib.Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def _random_key() -> str:
    return secrets.token_hex(32)


def _load_json(path: pathlib.Path) -> Dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def _write_json(path: pathlib.Path, data: Dict) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(path)
    try:
        os.chmod(path, 0o600)
    except PermissionError:
        pass


def _maybe_lock_file(path: pathlib.Path) -> None:
    if os.environ.get("CONTAINAI_BROKER_IMMUTABLE", "1") != "1":
        return
    if os.name != "posix":  # chattr only on Linux
        return
    try:
        subprocess.run(
            ["chattr", "+i", str(path)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        pass


def _ensure_broker_files(
    stubs: List[str] | None = None, *, create_missing_keys: bool = False
) -> None:
    _ensure_dir(BROKER_DIR)
    desired_stubs = stubs or DEFAULT_STUBS

    keys = {}
    if KEY_FILE.exists():
        keys = _load_json(KEY_FILE)
        if not isinstance(keys, dict):
            keys = {}
    need_keys = not KEY_FILE.exists()
    updated = False
    if need_keys or create_missing_keys:
        for stub in desired_stubs:
            if not stub:
                continue
            if stub not in keys:
                keys[stub] = _random_key()
                updated = True
        if need_keys or updated:
            _write_json(KEY_FILE, keys)
            _maybe_lock_file(KEY_FILE)

    if not STATE_FILE.exists():
        _write_json(STATE_FILE, {"issue_timestamps": [], "used_capabilities": {}})
        _maybe_lock_file(STATE_FILE)

    if not SECRETS_FILE.exists():
        _write_secrets({})
        _maybe_lock_file(SECRETS_FILE)


def _load_secrets() -> Dict[str, Dict[str, str]]:
    data = _load_json(SECRETS_FILE)
    result: Dict[str, Dict[str, str]] = {}
    if not isinstance(data, dict):
        return result
    for stub, value in data.items():
        if isinstance(value, dict):
            result[stub] = {
                name: str(secret)
                for name, secret in value.items()
                if isinstance(name, str)
            }
    return result


def _write_secrets(data: Dict[str, Dict[str, str]]) -> None:
    _write_json(SECRETS_FILE, data)


def _derive_session_key_hex(
    key_hex: str, nonce: str, session_id: str, stub: str, capability_id: str
) -> str:
    seed = f"{nonce}|{session_id}|{stub}|{capability_id}|seal"
    return hmac.new(
        bytes.fromhex(key_hex), seed.encode("utf-8"), hashlib.sha256
    ).hexdigest()


def _seal_secret(session_key_hex: str, secret_value: str) -> str:
    secret_bytes = secret_value.encode("utf-8")
    key_bytes = bytes.fromhex(session_key_hex)
    if not key_bytes:
        raise SystemExit("Invalid session key")
    stream = bytearray()
    key_index = 0
    xor_block = hashlib.sha256(key_bytes).digest()
    for byte in secret_bytes:
        stream.append(byte ^ xor_block[key_index])
        key_index += 1
        if key_index >= len(xor_block):
            xor_block = hashlib.sha256(xor_block).digest()
            key_index = 0
    return base64.b64encode(bytes(stream)).decode("ascii")


def _load_token(path: pathlib.Path) -> Dict:
    if not path.exists():
        raise SystemExit(f"Capability file missing: {path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid capability JSON: {exc}") from exc
    for field in ("stub", "session", "capability_id", "nonce", "expires_at", "hmac"):
        if field not in data:
            raise SystemExit(f"Capability missing field '{field}'")
    return data


def cmd_init(stubs: List[str]) -> None:
    _ensure_broker_files(stubs, create_missing_keys=True)
    print(f"[broker] key store ready at {KEY_FILE}")


def _rate_limit_check(state: Dict) -> None:
    now = time.time()
    history = state.get("issue_timestamps", [])
    history = [ts for ts in history if now - ts <= ISSUE_WINDOW_SECONDS]
    if len(history) >= ISSUE_WINDOW_LIMIT:
        msg = f"Rate limit exceeded: {len(history)} requests within {ISSUE_WINDOW_SECONDS}s."
        raise SystemExit(f"{msg} Wait before retrying.")
    history.append(now)
    state["issue_timestamps"] = history
    state["last_issue"] = now


def _mark_capability_used(state: Dict, capability_id: str) -> None:
    used = state.setdefault("used_capabilities", {})
    used[capability_id] = datetime.now(timezone.utc).isoformat()
    # Drop entries older than 24 hours to prevent unbounded growth
    cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
    used = {cap: ts for cap, ts in used.items() if _parse_iso(ts) >= cutoff}
    state["used_capabilities"] = used
    _write_json(STATE_FILE, state)


def _parse_iso(value: str) -> datetime:
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return datetime.now(timezone.utc)


def _load_keys() -> Dict[str, str]:
    if not KEY_FILE.exists():
        raise SystemExit("Broker key store missing. Run 'secret-broker.py init' first.")
    try:
        with KEY_FILE.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Corrupted key store: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit("Invalid key store format")
    return data


def _hmac_for(key_hex: str, payload: str) -> str:
    return hmac.new(bytes.fromhex(key_hex), payload.encode("utf-8"), hashlib.sha256).hexdigest()


def _write_token(output_dir: pathlib.Path, stub: str, token: Dict) -> None:
    stub_dir = output_dir / stub
    _ensure_dir(stub_dir)
    token_path = stub_dir / f"{token['capability_id']}.json"
    token_path.write_text(json.dumps(token, indent=2, sort_keys=True), encoding="utf-8")
    os.chmod(token_path, 0o600)


def cmd_issue(session_id: str, stubs: List[str], output: pathlib.Path, ttl_minutes: int) -> None:
    _ensure_broker_files(stubs)
    keys = _load_keys()
    state = _load_json(STATE_FILE)
    _rate_limit_check(state)
    summary = []
    expires_at = (datetime.now(timezone.utc) + timedelta(minutes=ttl_minutes)).isoformat()
    for stub in stubs:
        key_hex = keys.get(stub)
        if not key_hex:
            print(f"[broker] warning: no key for stub '{stub}', skipping", file=sys.stderr)
            continue
        capability_id = str(uuid.uuid4())
        nonce = secrets.token_hex(16)
        payload = f"{nonce}|{session_id}|{stub}|{capability_id}"
        digest = _hmac_for(key_hex, payload)
        token = {
            "stub": stub,
            "session": session_id,
            "capability_id": capability_id,
            "nonce": nonce,
            "expires_at": expires_at,
            "hmac": digest,
        }
        token["session_key"] = _derive_session_key_hex(
            key_hex, nonce, session_id, stub, capability_id
        )
        _write_token(output, stub, token)
        summary.append(token)
    _write_json(STATE_FILE, state)
    if summary:
        print(f"[broker] issued {len(summary)} capabilities -> {output}")
    else:
        raise SystemExit("No capabilities issued (missing stub keys?)")


def cmd_store_secret(
    stub: str, name: str, value: str, from_env: str | None, from_file: pathlib.Path | None
) -> None:
    _ensure_broker_files([stub])
    secret_value: str | None = value
    if from_env:
        secret_value = os.environ.get(from_env)
        if secret_value is None:
            raise SystemExit(f"Environment variable '{from_env}' is not set")
    if from_file:
        if not from_file.exists():
            raise SystemExit(f"Secret file not found: {from_file}")
        secret_value = from_file.read_text(encoding="utf-8").rstrip("\n")
    if not secret_value:
        raise SystemExit("Secret value cannot be empty")
    stored_secrets = _load_secrets()
    stored_secrets.setdefault(stub, {})[name] = secret_value
    _write_secrets(stored_secrets)
    _maybe_lock_file(SECRETS_FILE)
    print(f"[broker] secret '{name}' stored for stub '{stub}'")


def cmd_health() -> None:
    _ensure_broker_files()
    if not KEY_FILE.exists():
        raise SystemExit("Broker key file missing")
    if KEY_FILE.stat().st_mode & 0o077:
        print(
            "[broker] warning: key file is not chmod 600", file=sys.stderr
        )
    state = _load_json(STATE_FILE)
    last_issue = state.get("last_issue")
    if last_issue:
        delta = time.time() - last_issue
        print(f"[broker] last issuance {int(delta)}s ago")
    else:
        print("[broker] idle (no issuance history)")
    if not SECRETS_FILE.exists():
        print("[broker] warning: secrets file missing", file=sys.stderr)
    else:
        print("[broker] secrets store ready")
    print("[broker] health OK")


def cmd_redeem(
    capability_path: pathlib.Path,
    secret_names: List[str],
    output_dir: pathlib.Path | None,
    allow_reuse: bool,
) -> None:
    _ensure_broker_files()
    token = _load_token(capability_path)
    keys = _load_keys()
    key_hex = keys.get(token["stub"])
    if not key_hex:
        raise SystemExit(f"No broker key for stub '{token['stub']}'")
    payload = f"{token['nonce']}|{token['session']}|{token['stub']}|{token['capability_id']}"
    expected = _hmac_for(key_hex, payload)
    if not hmac.compare_digest(expected, token["hmac"]):
        raise SystemExit("Capability HMAC mismatch; refusing redemption")
    expected_session_key = _derive_session_key_hex(
        key_hex, token["nonce"], token["session"], token["stub"], token["capability_id"]
    )
    if token.get("session_key") != expected_session_key:
        raise SystemExit("Capability session key mismatch")
    try:
        expires_at = _parse_iso(token["expires_at"])
    except ValueError as exc:
        raise SystemExit(f"Invalid expiry timestamp: {exc}") from exc
    if datetime.now(timezone.utc) >= expires_at:
        raise SystemExit("Capability expired")
    state = _load_json(STATE_FILE)
    used = state.get("used_capabilities", {})
    if token["capability_id"] in used and not allow_reuse:
        raise SystemExit("Capability already redeemed; refuse replay")
    secrets_store = _load_secrets()
    secrets_for_stub = secrets_store.get(token["stub"], {})
    if not secret_names:
        raise SystemExit("At least one --secret must be provided")
    destination = output_dir or capability_path.parent / "secrets"
    destination.mkdir(parents=True, exist_ok=True)
    for secret_name in secret_names:
        secret_value = secrets_for_stub.get(secret_name)
        if secret_value is None:
            msg = f"Secret '{secret_name}' not defined for stub '{token['stub']}'"
            raise SystemExit(msg)
        ciphertext = _seal_secret(token["session_key"], secret_value)
        sealed = {
            "stub": token["stub"],
            "secret": secret_name,
            "capability_id": token["capability_id"],
            "issued_at": datetime.now(timezone.utc).isoformat(),
            "algorithm": "xor-sha256",
            "ciphertext": ciphertext,
        }
        sealed_path = destination / f"{secret_name}.sealed"
        sealed_path.write_text(json.dumps(sealed, indent=2), encoding="utf-8")
        try:
            os.chmod(sealed_path, 0o600)
        except PermissionError:
            pass
        print(f"[broker] sealed secret '{secret_name}' -> {sealed_path}")
    _mark_capability_used(state, token["capability_id"])


def parse_args(argv: List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_init = sub.add_parser("init", help="Generate broker key sets")
    p_init.add_argument("--stubs", nargs="*", default=DEFAULT_STUBS)

    p_issue = sub.add_parser("issue", help="Issue capability tokens")
    p_issue.add_argument("--session-id", required=True)
    p_issue.add_argument("--output", required=True, type=pathlib.Path)
    p_issue.add_argument("--stubs", nargs="+", default=DEFAULT_STUBS)
    p_issue.add_argument("--ttl", type=int, default=DEFAULT_TTL_MINUTES)

    p_store = sub.add_parser("store", help="Store or update stub secrets")
    p_store.add_argument("--stub", required=True)
    p_store.add_argument("--name", required=True)
    value_group = p_store.add_mutually_exclusive_group(required=True)
    value_group.add_argument("--value")
    value_group.add_argument("--from-env")
    value_group.add_argument("--from-file", type=pathlib.Path)

    p_redeem = sub.add_parser("redeem", help="Redeem a capability and seal secrets")
    p_redeem.add_argument("--capability", required=True, type=pathlib.Path)
    p_redeem.add_argument("--secret", dest="secrets", action="append", required=True)
    p_redeem.add_argument("--output-dir", type=pathlib.Path)
    p_redeem.add_argument("--allow-reuse", action="store_true")

    sub.add_parser("health", help="Check broker state")

    return parser.parse_args(argv)


def main(argv: List[str]) -> int:
    args = parse_args(argv)
    if args.command == "init":
        cmd_init(args.stubs)
        return 0
    if args.command == "issue":
        _ensure_dir(args.output)
        cmd_issue(args.session_id, args.stubs, args.output, args.ttl)
        return 0
    if args.command == "store":
        cmd_store_secret(args.stub, args.name, args.value, args.from_env, args.from_file)
        return 0
    if args.command == "health":
        cmd_health()
        return 0
    if args.command == "redeem":
        cmd_redeem(args.capability, args.secrets, args.output_dir, args.allow_reuse)
        return 0
    raise SystemExit(1)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
