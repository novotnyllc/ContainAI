#!/usr/bin/env python3
"""
Lightweight HTTPS/SSE proxy helper for MCP servers.

Listens on a localhost port, forwards requests to a single upstream HTTPS
endpoint, streams responses (including SSE), and enforces a fixed allowlist
(only the configured upstream host is permitted).
"""

from __future__ import annotations

import argparse
import dataclasses
import http.client
import http.server
import json
import os
import socket
import ssl
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Mapping
from typing import Callable


HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}
DEFAULT_TIMEOUT = 60


@dataclasses.dataclass(frozen=True, slots=True)
class ProxyState:
    """Configuration and derived state for the proxy handler."""

    name: str
    target: str
    bearer: str | None
    timeout: int
    parsed_target: urllib.parse.ParseResult = dataclasses.field(init=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "parsed_target", urllib.parse.urlparse(self.target))

    def merge_url(self, path: str) -> str:
        """Merge an inbound request path onto the configured target URL."""
        merged = urllib.parse.urljoin(self.parsed_target.geturl(), path.lstrip("/"))
        parsed = urllib.parse.urlparse(merged)
        normalized = parsed._replace(
            scheme=self.parsed_target.scheme,
            netloc=self.parsed_target.netloc,
        )
        return urllib.parse.urlunparse(normalized)

    def is_destination_allowed(self, url: str) -> bool:
        """Return True if the merged destination remains on the allowlisted host."""
        return urllib.parse.urlparse(url).netloc == self.parsed_target.netloc

    def maybe_add_auth(self, headers: dict[str, str]) -> None:
        """Inject a bearer token if configured and no Authorization header exists."""
        if not self.bearer:
            return
        if "authorization" in {k.lower() for k in headers}:
            return
        headers["Authorization"] = f"Bearer {self.bearer}"


def _filter_headers(headers: Mapping[str, str]) -> dict[str, str]:
    """Strip hop-by-hop headers that must not be forwarded by proxies."""
    return {k: v for k, v in headers.items() if k.lower() not in HOP_BY_HOP}


def _require_proxy(parser: argparse.ArgumentParser) -> None:
    """Enforce proxy presence when CONTAINAI_REQUIRE_PROXY is enabled."""
    require_proxy = os.environ.get("CONTAINAI_REQUIRE_PROXY", "0") not in (
        "0",
        "",
        "false",
        "False",
    )
    if not require_proxy:
        return
    if any(os.environ.get(v) for v in ("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy")):
        return
    parser.error("proxy required but HTTP(S)_PROXY not set")


def _parse_listen_value(listen: str) -> tuple[str, int]:
    """Parse a host:port string into its components."""
    try:
        listen_host, listen_port_str = listen.split(":", 1)
        return listen_host, int(listen_port_str)
    except ValueError as exc:  # pragma: no cover - user input validation
        raise ValueError(f"invalid --listen value: {exc}") from exc


def _read_request_body(handler: http.server.BaseHTTPRequestHandler) -> bytes | None:
    """Read request body with a fixed maximum size."""
    content_length = int(handler.headers.get("Content-Length", "0") or 0)
    if content_length > 10 * 1024 * 1024:
        handler.send_error(413, "Request Entity Too Large")
        return None
    return handler.rfile.read(content_length) if content_length > 0 else b""


def _write_health(handler: http.server.BaseHTTPRequestHandler, name: str) -> None:
    """Write a small JSON health payload."""
    payload = json.dumps({"status": "ok", "name": name}).encode("utf-8")
    handler.send_response(200)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(payload)))
    handler.end_headers()
    handler.wfile.write(payload)


def _forward_upstream_response(
    handler: http.server.BaseHTTPRequestHandler,
    upstream: urllib.response.addinfourl,
) -> None:
    """Forward status/headers/body from an upstream response."""
    handler.send_response(upstream.getcode())
    for key, value in _filter_headers(upstream.headers).items():
        handler.send_header(key, value)
    handler.end_headers()

    content_type = upstream.headers.get("Content-Type", "") or ""
    is_sse = "text/event-stream" in content_type.lower()
    chunk_size = 16 * 1024 if is_sse else 64 * 1024

    while True:
        chunk = upstream.read(chunk_size)
        if not chunk:
            break
        handler.wfile.write(chunk)
        if is_sse:
            handler.wfile.flush()


def _make_handler(state: ProxyState) -> type[http.server.BaseHTTPRequestHandler]:
    class ProxyHandler(http.server.BaseHTTPRequestHandler):
        """HTTP handler that forwards requests to a single allowlisted upstream."""

        server_version = "mcp-http-helper/1.0"
        protocol_version = "HTTP/1.1"

        def address_string(self) -> str:  # pragma: no cover
            """Return the client address used by BaseHTTPRequestHandler logging."""
            client_host = self.client_address[0] if self.client_address else "-"
            return f"[{state.name}] {client_host}"

        def __getattr__(self, name: str) -> Callable[[], None]:
            """Dynamically implement do_* methods without defining them.

            BaseHTTPRequestHandler dispatches to a do_<METHOD> attribute.
            Using __getattr__ avoids Pylint naming warnings for do_GET, etc.
            """
            if name.startswith("do_"):
                return self._handle_proxy_request
            raise AttributeError(name)

        def _handle_proxy_request(self) -> None:
            """Handle a single inbound HTTP request."""
            if self.path == "/health":
                _write_health(self, state.name)
                return

            target_url = state.merge_url(self.path)
            if not state.is_destination_allowed(target_url):
                self.send_error(403, "destination not permitted")
                return

            body = _read_request_body(self)
            if body is None:
                return

            headers = _filter_headers(self.headers)
            headers["X-CA-Helper"] = state.name
            agent = os.environ.get("CONTAINAI_AGENT_ID")
            session = os.environ.get("CONTAINAI_SESSION_ID")
            if agent:
                headers["X-CA-Agent"] = agent
            if session:
                headers["X-CA-Session"] = session
            state.maybe_add_auth(headers)

            req = urllib.request.Request(
                target_url,
                data=body or None,
                method=self.command,
                headers=headers,
            )

            try:
                with urllib.request.urlopen(req, timeout=state.timeout) as upstream:
                    _forward_upstream_response(self, upstream)
            except socket.timeout:
                self.send_error(504, "upstream timeout")
            except urllib.error.HTTPError as exc:
                # Forward upstream status code but hide body to avoid leaking details
                self.send_error(exc.code, exc.reason)
            except urllib.error.URLError as exc:
                self.send_error(502, f"upstream connection failed: {exc.reason}")
            except (http.client.HTTPException, ssl.SSLError, OSError) as exc:  # pragma: no cover
                self.send_error(502, f"upstream error: {exc}")

    return ProxyHandler


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="Helper name for logging")
    parser.add_argument("--listen", required=True, help="Listen address (host:port)")
    parser.add_argument("--target", required=True, help="Upstream HTTPS endpoint")
    parser.add_argument(
        "--bearer-token",
        dest="bearer_token",
        default=None,
        help="Bearer token to inject",
    )
    parser.add_argument(
        "--timeout",
        dest="timeout",
        type=int,
        default=DEFAULT_TIMEOUT,
        help="Upstream timeout seconds",
    )
    args = parser.parse_args(argv)

    _require_proxy(parser)
    try:
        listen_host, listen_port = _parse_listen_value(args.listen)
    except ValueError as exc:  # pragma: no cover
        parser.error(str(exc))

    state = ProxyState(args.name, args.target, args.bearer_token, args.timeout)
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
