#!/usr/bin/env python3
"""Utility to decrypt sealed secrets from launcher-issued capability bundles."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys

from _token_utils import decrypt_sealed_ciphertext, select_latest_valid_token

DEFAULT_CAP_ROOT = pathlib.Path("~/.config/containai/capabilities").expanduser()


class CapabilityError(RuntimeError):
    """Raised when capability secrets cannot be decoded."""


def _load_json(path: pathlib.Path) -> dict:
    """Load a JSON object from disk."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:  # pragma: no cover - defensive
        raise CapabilityError(f"invalid JSON in {path}: {exc}") from exc
    except OSError as exc:  # pragma: no cover - defensive
        raise CapabilityError(f"unable to read {path}: {exc}") from exc


def _select_capability(stub_dir: pathlib.Path) -> dict:
    """Pick the newest non-expired capability token for a stub."""
    try:
        token, _path = select_latest_valid_token(
            stub_dir,
            expected_field="stub",
            expected_value=stub_dir.name,
        )
        return token
    except ValueError as exc:
        raise CapabilityError(str(exc)) from exc


def _load_sealed_secret(
    capability: dict,
    stub_dir: pathlib.Path,
    secret_name: str,
) -> str:
    """Load and decrypt a sealed secret bound to a capability token."""
    secrets_dir = stub_dir / "secrets"
    record_path = secrets_dir / f"{secret_name}.sealed"
    if not record_path.is_file():
        raise CapabilityError(f"sealed secret '{secret_name}' missing at {record_path}")
    record = _load_json(record_path)
    if record.get("stub") != capability.get("stub"):
        raise CapabilityError(
            f"sealed secret '{secret_name}' is not bound to stub '{capability.get('stub')}'"
        )
    if record.get("capability_id") != capability.get("capability_id"):
        raise CapabilityError(
            f"sealed secret '{secret_name}' not bound to capability "
            f"{capability.get('capability_id')}"
        )
    ciphertext = record.get("ciphertext")
    if not ciphertext:
        raise CapabilityError(f"sealed secret '{secret_name}' missing ciphertext body")
    session_key = capability.get("session_key") or ""
    if not session_key:
        raise CapabilityError("capability token missing session_key")
    try:
        return decrypt_sealed_ciphertext(ciphertext, session_key)
    except ValueError as exc:  # pragma: no cover - defensive
        raise CapabilityError(f"sealed secret '{secret_name}' {exc}") from exc


def _resolve_stub_dir(cap_root: pathlib.Path, stub: str) -> pathlib.Path:
    """Resolve the per-stub capability directory under the root."""
    target = cap_root / stub
    if not target.is_dir():
        raise CapabilityError(
            f"capability directory missing for stub '{stub}' at {target}"
        )
    return target


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--stub",
        required=True,
        help="Name of the stub (e.g., agent_copilot_cli)",
    )
    parser.add_argument(
        "--secret",
        action="append",
        required=True,
        help="Secret name to decode",
    )
    parser.add_argument(
        "--cap-root",
        default=str(DEFAULT_CAP_ROOT),
        help="Capability root directory",
    )
    parser.add_argument(
        "--format",
        choices=("json", "raw"),
        default="json",
        help="Output format (raw requires a single --secret)",
    )
    parser.add_argument(
        "--write",
        action="append",
        default=[],
        metavar="secret:path",
        help="Write the decrypted value of <secret> to <path> with chmod 600",
    )
    return parser.parse_args(argv)


def _write_secret(path: pathlib.Path, value: str) -> None:
    """Write a decrypted secret to disk with restrictive permissions."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")
    os.chmod(path, 0o600)


def main(argv: list[str]) -> int:
    """Decrypt secrets from a capability token and emit them."""
    args = parse_args(argv)
    cap_root = pathlib.Path(args.cap_root).expanduser()
    stub_dir = _resolve_stub_dir(cap_root, args.stub)
    capability = _select_capability(stub_dir)
    results: dict[str, str] = {}
    for secret_name in args.secret:
        results[secret_name] = _load_sealed_secret(capability, stub_dir, secret_name)

    for mapping in args.write:
        if ":" not in mapping:
            raise CapabilityError(f"write mapping '{mapping}' must be in secret:path format")
        secret_name, dest = mapping.split(":", 1)
        if secret_name not in results:
            raise CapabilityError(f"write mapping references unknown secret '{secret_name}'")
        _write_secret(pathlib.Path(dest).expanduser(), results[secret_name])

    if args.format == "raw":
        if len(args.secret) != 1:
            raise CapabilityError("--format raw requires exactly one --secret")
        sys.stdout.write(results[args.secret[0]])
        return 0

    json.dump(results, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main(sys.argv[1:]))
    except CapabilityError as exc:
        print(f"capability-unseal: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
