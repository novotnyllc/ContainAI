#!/usr/bin/env python3
"""Shared helpers for runtime scripts.

This module is used by multiple runtime scripts to avoid copy/paste logic that
otherwise triggers Pylint's duplicate-code checks.
"""

from __future__ import annotations

import datetime as dt
import base64
import binascii
import json
import pathlib
import hashlib


def load_json(path: pathlib.Path) -> dict:
    """Load a JSON object from disk."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"cannot parse JSON from {path}: {exc}") from exc
    except OSError as exc:
        raise ValueError(f"unable to read {path}: {exc}") from exc


def parse_expires_at(value: object) -> dt.datetime | None:
    """Parse an expires_at field into a timezone-aware datetime."""
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed


def select_latest_valid_token(
    token_dir: pathlib.Path,
    *,
    expected_field: str,
    expected_value: str,
) -> tuple[dict, pathlib.Path]:
    """Return the newest unexpired token in token_dir matching expected_field."""
    candidates = sorted(token_dir.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not candidates:
        raise ValueError(f"no capability tokens found under {token_dir}")

    now = dt.datetime.now(dt.timezone.utc)

    for candidate in candidates:
        token = load_json(candidate)
        if token.get(expected_field) != expected_value:
            continue

        expiry = parse_expires_at(token.get("expires_at"))
        if expiry is None or expiry <= now:
            continue

        if "session_key" not in token:
            continue

        return token, candidate

    raise ValueError(f"no valid (unexpired) capabilities available under {token_dir}")


def decode_base64(value: str) -> bytes:
    """Decode a base64-encoded string into bytes."""
    try:
        return base64.b64decode(value)
    except (binascii.Error, ValueError) as exc:
        raise ValueError(f"invalid base64: {exc}") from exc


def decode_utf8(data: bytes) -> str:
    """Decode UTF-8 bytes into a string."""
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"not valid UTF-8: {exc}") from exc


def xor_sha256_stream(key_hex: str, data: bytes) -> bytes:
    """XOR a byte stream with a SHA-256 expanded key derived from key_hex."""
    key_bytes = bytes.fromhex(key_hex)
    if not key_bytes:
        raise ValueError("invalid session key")

    output = bytearray()
    key_index = 0
    xor_block = hashlib.sha256(key_bytes).digest()
    for byte in data:
        output.append(byte ^ xor_block[key_index])
        key_index += 1
        if key_index >= len(xor_block):
            xor_block = hashlib.sha256(xor_block).digest()
            key_index = 0
    return bytes(output)


def decrypt_sealed_ciphertext(ciphertext_b64: str, session_key_hex: str) -> str:
    """Decode base64 ciphertext, decrypt via XOR-SHA256 stream, then UTF-8 decode."""
    cipher_bytes = decode_base64(ciphertext_b64)
    plain_bytes = xor_sha256_stream(session_key_hex, cipher_bytes)
    return decode_utf8(plain_bytes)
