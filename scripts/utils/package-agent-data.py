#!/usr/bin/env python3
"""Package or merge agent data payloads for Coding Agents."""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import shutil
import sys
import tarfile
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, List, Optional


@dataclass(frozen=True)
class DataSpec:
    path: str
    strategy: str  # merge rule hint (replace, append, etc.)


AGENT_DATA_SPECS: dict[str, List[DataSpec]] = {
    "copilot": [
        DataSpec(path=".copilot/sessions", strategy="replace"),
        DataSpec(path=".copilot/logs", strategy="append"),
        DataSpec(path=".copilot/telemetry", strategy="append"),
    ],
    "codex": [
        DataSpec(path=".codex/sessions", strategy="replace"),
        DataSpec(path=".codex/logs", strategy="append"),
        DataSpec(path=".codex/history.jsonl", strategy="append"),
    ],
    "claude": [
        DataSpec(path=".claude/sessions", strategy="replace"),
        DataSpec(path=".claude/logs", strategy="append"),
        DataSpec(path=".claude/attachments", strategy="replace"),
        DataSpec(path=".claude.json", strategy="replace"),
    ],
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def iter_spec_files(source: Path) -> Iterable[Path]:
    if source.is_file():
        yield source
        return
    if not source.is_dir():
        return
    for child in sorted(source.rglob("*")):
        if child.is_file():
            yield child


def write_manifest(manifest_path: Path, agent: str, session_id: str, entries: List[dict]) -> None:
    payload = {
        "agent": agent,
        "session": session_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "entries": entries,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    try:
        manifest_path.chmod(0o600)
    except PermissionError:
        pass


def _compute_entry_hmac(key: bytes, *, path: str, sha256_value: str, size: int, mtime: int, strategy: str) -> str:
    payload = "|".join([path, sha256_value, str(size), str(mtime), strategy])
    return hmac.new(key, payload.encode("utf-8"), hashlib.sha256).hexdigest()


def package_agent_data(
    *,
    agent: str,
    session_id: str,
    tar_path: Path,
    manifest_path: Path,
    home_path: Path,
    hmac_key: Optional[bytes] = None,
) -> bool:
    specs = AGENT_DATA_SPECS.get(agent)
    if not specs:
        print(f"[data] no packaging rules for agent '{agent}'", file=sys.stderr)
        return False

    home_path = home_path.expanduser().resolve()
    entries: List[dict] = []
    tar_inputs: List[tuple[Path, str]] = []

    for spec in specs:
        raw = os.path.expanduser(spec.path)
        spec_path = Path(raw)
        if spec_path.is_absolute():
            source = spec_path
            arcname = spec_path.as_posix().lstrip("/")
            if not arcname:
                continue
        else:
            source = (home_path / spec_path).resolve()
            arcname = spec_path.as_posix()
        if not source.exists():
            continue
        if source.is_symlink():
            continue
        tar_inputs.append((source, arcname))
        for file_path in iter_spec_files(source):
            if file_path.is_symlink():
                continue
            rel = Path(arcname)
            if source.is_dir():
                rel = rel / file_path.relative_to(source)
            entry_stat = file_path.stat()
            entry_record = {
                "path": rel.as_posix(),
                "sha256": sha256_file(file_path),
                "size": entry_stat.st_size,
                "mtime": int(entry_stat.st_mtime),
                "strategy": spec.strategy,
            }
            if hmac_key:
                entry_record["hmac"] = _compute_entry_hmac(
                    hmac_key,
                    path=entry_record["path"],
                    sha256_value=entry_record["sha256"],
                    size=entry_record["size"],
                    mtime=entry_record["mtime"],
                    strategy=entry_record["strategy"],
                )
            entries.append(entry_record)

    entries.sort(key=lambda item: item["path"])
    write_manifest(manifest_path, agent, session_id, entries)

    if not tar_inputs:
        if tar_path.exists():
            tar_path.unlink()
        return True

    tar_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(tar_path, "w") as archive:
        for source, arcname in tar_inputs:
            archive.add(source, arcname=arcname)
    try:
        tar_path.chmod(0o600)
    except PermissionError:
        pass
    print(f"[data] packaged {len(entries)} entries for agent '{agent}' -> {tar_path}")
    return True


def _ensure_relative_path(path_str: str) -> Path:
    candidate = Path(path_str)
    if candidate.is_absolute():
        raise ValueError(f"Entry path '{path_str}' must be relative")
    for part in candidate.parts:
        if part in ("..", ""):
            raise ValueError(f"Entry path '{path_str}' contains unsafe segment '{part}'")
    return candidate


def _write_temp_copy(fileobj, dest_dir: Path, chunk_size: int = 1024 * 1024) -> tuple[Path, str]:
    dest_dir.mkdir(parents=True, exist_ok=True)
    tmp_handle = tempfile.NamedTemporaryFile(delete=False, dir=dest_dir)
    tmp_path = Path(tmp_handle.name)
    hasher = hashlib.sha256()
    try:
        while True:
            chunk = fileobj.read(chunk_size)
            if not chunk:
                break
            tmp_handle.write(chunk)
            hasher.update(chunk)
    finally:
        tmp_handle.close()
    return tmp_path, hasher.hexdigest()


def merge_agent_data(
    *,
    agent: str,
    tar_path: Path,
    manifest_path: Path,
    target_home: Path,
    session_id: str | None = None,
    hmac_key: Optional[bytes] = None,
    require_hmac: bool = False,
) -> bool:
    if not tar_path.is_file() or not manifest_path.is_file():
        print(f"[data] export assets missing for agent '{agent}'", file=sys.stderr)
        return False

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("agent") != agent:
        print(f"[data] manifest agent mismatch: expected '{agent}' got '{manifest.get('agent')}'", file=sys.stderr)
        return False
    if session_id and manifest.get("session") != session_id:
        print(
            f"[data] manifest session mismatch: expected '{session_id}' got '{manifest.get('session')}'",
            file=sys.stderr,
        )
        return False
    if require_hmac and not hmac_key:
        print("[data] HMAC key required but not provided", file=sys.stderr)
        return False

    target_home = target_home.expanduser().resolve()
    processed = 0

    with tarfile.open(tar_path, "r") as archive:
        for entry in manifest.get("entries", []):
            rel_path = _ensure_relative_path(entry["path"])
            strategy = entry.get("strategy", "replace")
            digest_expected = entry.get("sha256")
            entry_hmac = entry.get("hmac")
            if hmac_key:
                if not entry_hmac:
                    print(f"[data] missing HMAC for '{rel_path}'", file=sys.stderr)
                    return False
                expected_hmac = _compute_entry_hmac(
                    hmac_key,
                    path=rel_path.as_posix(),
                    sha256_value=digest_expected or "",
                    size=int(entry.get("size", 0)),
                    mtime=int(entry.get("mtime", 0)),
                    strategy=strategy,
                )
                if not hmac.compare_digest(expected_hmac, entry_hmac):
                    print(f"[data] HMAC mismatch for '{rel_path}'", file=sys.stderr)
                    return False

            try:
                member = archive.getmember(rel_path.as_posix())
            except KeyError:
                print(f"[data] missing member '{rel_path}' in tar", file=sys.stderr)
                return False
            if not member.isfile():
                print(f"[data] member '{rel_path}' is not a regular file", file=sys.stderr)
                return False

            fileobj = archive.extractfile(member)
            if fileobj is None:
                print(f"[data] unable to extract '{rel_path}'", file=sys.stderr)
                return False

            tmp_root = target_home / ".coding-agents-tmp"
            tmp_path, digest_actual = _write_temp_copy(fileobj, tmp_root)
            if digest_expected and digest_actual != digest_expected:
                tmp_path.unlink(missing_ok=True)
                print(f"[data] digest mismatch for '{rel_path}'", file=sys.stderr)
                return False

            target_path = (target_home / rel_path).resolve()
            if target_home not in target_path.parents and target_path != target_home:
                tmp_path.unlink(missing_ok=True)
                print(f"[data] target '{target_path}' escapes home root", file=sys.stderr)
                return False

            target_path.parent.mkdir(parents=True, exist_ok=True)

            if strategy == "replace":
                if target_path.exists():
                    if target_path.is_dir():
                        shutil.rmtree(target_path)
                    else:
                        target_path.unlink()
                shutil.move(str(tmp_path), target_path)
                target_path.chmod(0o600)
            elif strategy == "append":
                with target_path.open("ab") as dest, tmp_path.open("rb") as src:
                    shutil.copyfileobj(src, dest)
                target_path.chmod(0o600)
                tmp_path.unlink(missing_ok=True)
            else:
                tmp_path.unlink(missing_ok=True)
                print(f"[data] unknown merge strategy '{strategy}'", file=sys.stderr)
                return False

            processed += 1

    tmp_root = target_home / ".coding-agents-tmp"
    if tmp_root.exists():
        shutil.rmtree(tmp_root, ignore_errors=True)

    if processed == 0:
        print(f"[data] manifest contained no mergeable entries for '{agent}'")
    else:
        print(f"[data] merged {processed} entries for agent '{agent}'")
    return True


def parse_args(argv: List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("package", "merge"), default="package")
    parser.add_argument("--agent", required=True, choices=sorted(AGENT_DATA_SPECS.keys()))
    parser.add_argument("--session-id", help="Session identifier for correlation")
    parser.add_argument("--tar", required=True, type=Path, help="Tarball path (output for package, input for merge)")
    parser.add_argument("--manifest", required=True, type=Path, help="Manifest path (output for package, input for merge)")
    parser.add_argument("--hmac-key-file", type=Path, help="Path to hex-encoded HMAC key")
    parser.add_argument("--hmac-key-env", help="Environment variable containing hex-encoded HMAC key")
    parser.add_argument("--require-hmac", action="store_true", help="Fail if HMAC metadata is missing")
    parser.add_argument(
        "--home-path",
        type=Path,
        default=Path.home(),
        help="Home directory to source agent data when packaging",
    )
    parser.add_argument(
        "--target-home",
        type=Path,
        default=Path.home(),
        help="Home directory to merge agent data into when running in merge mode",
    )
    return parser.parse_args(argv)


def _load_hmac_key(args: argparse.Namespace) -> Optional[bytes]:
    key_hex: Optional[str] = None
    if args.hmac_key_file:
        if not args.hmac_key_file.exists():
            raise SystemExit(f"HMAC key file not found: {args.hmac_key_file}")
        key_hex = args.hmac_key_file.read_text(encoding="utf-8").strip()
    elif args.hmac_key_env:
        env_value = os.environ.get(args.hmac_key_env)
        if env_value:
            key_hex = env_value.strip()
    if key_hex:
        key_hex = key_hex.lower()
        try:
            return bytes.fromhex(key_hex)
        except ValueError as exc:
            raise SystemExit(f"Invalid HMAC key format: {exc}")
    if args.require_hmac:
        raise SystemExit("HMAC key required but not provided")
    return None


def main(argv: List[str]) -> int:
    args = parse_args(argv)
    hmac_key = _load_hmac_key(args)
    if args.mode == "package":
        if not args.session_id:
            print("[data] --session-id is required for package mode", file=sys.stderr)
            return 1
        success = package_agent_data(
            agent=args.agent,
            session_id=args.session_id,
            tar_path=args.tar,
            manifest_path=args.manifest,
            home_path=args.home_path,
            hmac_key=hmac_key,
        )
    else:
        success = merge_agent_data(
            agent=args.agent,
            tar_path=args.tar,
            manifest_path=args.manifest,
            target_home=args.target_home,
            session_id=args.session_id,
            hmac_key=hmac_key,
            require_hmac=args.require_hmac,
        )
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
