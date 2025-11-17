#!/usr/bin/env python3
"""Host-side secret broker utilities for capability issuance."""

from __future__ import annotations

import argparse
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

CONFIG_ROOT = pathlib.Path(os.environ.get("CODING_AGENTS_CONFIG_DIR", pathlib.Path.home() / ".config" / "coding-agents"))
BROKER_DIR = pathlib.Path(os.environ.get("CODING_AGENTS_BROKER_DIR", CONFIG_ROOT / "broker.d"))
KEY_FILE = BROKER_DIR / "keys.json"
STATE_FILE = BROKER_DIR / "state.json"
DEFAULT_STUBS = [
    "github",
    "uno",
    "msftdocs",
    "playwright",
    "context7",
    "serena",
    "sequential-thinking",
    "fetch",
]
ISSUE_WINDOW_SECONDS = int(os.environ.get("CODING_AGENTS_BROKER_RATE_WINDOW", "60"))
ISSUE_WINDOW_LIMIT = int(os.environ.get("CODING_AGENTS_BROKER_RATE_LIMIT", "30"))
DEFAULT_TTL_MINUTES = int(os.environ.get("CODING_AGENTS_BROKER_TTL", "30"))


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
    if os.environ.get("CODING_AGENTS_BROKER_IMMUTABLE", "0") != "1":
        return
    if os.name != "posix":  # chattr only on Linux
        return
    try:
        subprocess.run(["chattr", "+i", str(path)], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass


def cmd_init(stubs: List[str]) -> None:
    _ensure_dir(BROKER_DIR)
    keys = _load_json(KEY_FILE)
    updated = False
    for stub in stubs:
        if stub not in keys:
            keys[stub] = _random_key()
            updated = True
    if updated or not KEY_FILE.exists():
        _write_json(KEY_FILE, keys)
        _maybe_lock_file(KEY_FILE)
    print(f"[broker] key store ready at {KEY_FILE}")


def _rate_limit_check(state: Dict) -> None:
    now = time.time()
    history = state.get("issue_timestamps", [])
    history = [ts for ts in history if now - ts <= ISSUE_WINDOW_SECONDS]
    if len(history) >= ISSUE_WINDOW_LIMIT:
        raise SystemExit(
            f"Rate limit exceeded: {len(history)} requests within {ISSUE_WINDOW_SECONDS}s. Wait before retrying."
        )
    history.append(now)
    state["issue_timestamps"] = history
    state["last_issue"] = now


def _load_keys() -> Dict[str, str]:
    if not KEY_FILE.exists():
        raise SystemExit("Broker key store missing. Run 'secret-broker.py init' first.")
    try:
        with KEY_FILE.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Corrupted key store: {exc}")
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
        _write_token(output, stub, token)
        summary.append(token)
    _write_json(STATE_FILE, state)
    if summary:
        print(f"[broker] issued {len(summary)} capabilities -> {output}")
    else:
        raise SystemExit("No capabilities issued (missing stub keys?)")


def cmd_health() -> None:
    if not KEY_FILE.exists():
        raise SystemExit("Broker key file missing")
    if KEY_FILE.stat().st_mode & 0o077:
        print("[broker] warning: key file is not chmod 600", file=sys.stderr)
    state = _load_json(STATE_FILE)
    last_issue = state.get("last_issue")
    if last_issue:
        delta = time.time() - last_issue
        print(f"[broker] last issuance {int(delta)}s ago")
    else:
        print("[broker] idle (no issuance history)")
    print("[broker] health OK")


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
    if args.command == "health":
        cmd_health()
        return 0
    raise SystemExit(1)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
