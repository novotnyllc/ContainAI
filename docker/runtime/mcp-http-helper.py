#!/usr/bin/env python3
"""
Lightweight HTTPS/SSE proxy helper for MCP servers.

Listens on a localhost port, forwards requests to a single upstream HTTPS
endpoint, streams responses (including SSE), and enforces a fixed allowlist
(only the configured upstream host is permitted).
"""

from __future__ import annotations

import argparse
import http.server
import json
import socket
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, Optional


HOP_BY_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade"}
DEFAULT_TIMEOUT = 60


class _ProxyState:
    def __init__(self, name: str, target: str, bearer: Optional[str], timeout: int) -> None:
        self.name = name
        self.target = target
        self.parsed_target = urllib.parse.urlparse(target)
        self.bearer = bearer
        self.timeout = timeout


def _merge_urls(base: urllib.parse.ParseResult, path: str) -> str:
    # Preserve query and path while keeping scheme/host from the base URL
    merged = urllib.parse.urljoin(base.geturl(), path.lstrip("/"))
    parsed = urllib.parse.urlparse(merged)
    normalized = parsed._replace(scheme=base.scheme, netloc=base.netloc)
    return urllib.parse.urlunparse(normalized)


def _filter_headers(headers) -> Dict[str, str]:
    filtered: Dict[str, str] = {}
    for key, value in headers.items():
        if key.lower() in HOP_BY_HOP:
            continue
        filtered[key] = value
    return filtered


def _make_handler(state: _ProxyState):
    class ProxyHandler(http.server.BaseHTTPRequestHandler):
        server_version = "mcp-http-helper/1.0"
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt: str, *args) -> None:  # pragma: no cover - reduce noise in tests
            sys.stderr.write(f"[{state.name}] " + (fmt % args) + "\n")

        def _send_health(self) -> None:
            payload = json.dumps({"status": "ok", "name": state.name}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def _proxy(self) -> None:
            if self.path == "/health":
                self._send_health()
                return

            target_url = _merge_urls(state.parsed_target, self.path)
            parsed_target = urllib.parse.urlparse(target_url)
            if parsed_target.netloc != state.parsed_target.netloc:
                self.send_error(403, "destination not permitted")
                return

            content_length = int(self.headers.get("Content-Length", "0") or 0)
            if content_length > 10 * 1024 * 1024:  # 10MB limit
                self.send_error(413, "Request Entity Too Large")
                return
            body = self.rfile.read(content_length) if content_length > 0 else None
            headers = _filter_headers(self.headers)
            headers["X-CA-Helper"] = state.name
            agent = os.environ.get("CONTAINAI_AGENT_ID")
            session = os.environ.get("CONTAINAI_SESSION_ID")
            if agent:
                headers["X-CA-Agent"] = agent
            if session:
                headers["X-CA-Session"] = session
            if state.bearer and "authorization" not in {k.lower() for k in headers}:
                headers["Authorization"] = f"Bearer {state.bearer}"

            req = urllib.request.Request(
                target_url,
                data=body,
                method=self.command,
                headers=headers,
            )

            try:
                with urllib.request.urlopen(req, timeout=state.timeout) as upstream:
                    status = upstream.getcode()
                    resp_headers = _filter_headers(upstream.headers)
                    self.send_response(status)
                    for key, value in resp_headers.items():
                        self.send_header(key, value)
                    self.end_headers()

                    content_type = upstream.headers.get("Content-Type", "") or ""
                    stream = "text/event-stream" in content_type.lower()
                    chunk_size = 16 * 1024 if stream else 64 * 1024
                    while True:
                        chunk = upstream.read(chunk_size)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        if stream:
                            self.wfile.flush()
            except socket.timeout:
                self.send_error(504, "upstream timeout")
            except urllib.error.HTTPError as exc:  # type: ignore[attr-defined]
                # Forward upstream status code but hide body to avoid leaking details
                self.send_error(exc.code, exc.reason)
            except Exception as exc:  # pragma: no cover - defensive
                self.send_error(502, f"upstream error: {exc}")

        def do_GET(self) -> None:  # noqa: N802
            self._proxy()

        def do_POST(self) -> None:  # noqa: N802
            self._proxy()

        def do_PUT(self) -> None:  # noqa: N802
            self._proxy()

        def do_DELETE(self) -> None:  # noqa: N802
            self._proxy()

    return ProxyHandler


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="Helper name for logging")
    parser.add_argument("--listen", required=True, help="Listen address (host:port)")
    parser.add_argument("--target", required=True, help="Upstream HTTPS endpoint")
    parser.add_argument("--bearer-token", dest="bearer_token", default=None, help="Bearer token to inject")
    parser.add_argument("--timeout", dest="timeout", type=int, default=DEFAULT_TIMEOUT, help="Upstream timeout seconds")
    args = parser.parse_args(argv)

    require_proxy = os.environ.get("CONTAINAI_REQUIRE_PROXY", "0") not in ("0", "", "false", "False")
    if require_proxy and not any(os.environ.get(v) for v in ("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy")):
        parser.error("proxy required but HTTP(S)_PROXY not set")

    try:
        listen_host, listen_port = args.listen.split(":", 1)
        listen_port = int(listen_port)
    except ValueError as exc:  # pragma: no cover - user input validation
        parser.error(f"invalid --listen value: {exc}")

    state = _ProxyState(args.name, args.target, args.bearer_token, args.timeout)
    handler = _make_handler(state)
    server = http.server.ThreadingHTTPServer((listen_host, listen_port), handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:  # pragma: no cover - manual shutdown
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
