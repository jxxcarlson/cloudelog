#!/usr/bin/env python3
"""cloudelog frontend dev server. PORT env var (default 8011).

Serves static assets from this directory, falls back to index.html for SPA
client-side routes, and proxies /api/* to the backend (BACKEND env var,
default http://localhost:8081) so the browser sees a single same-origin
surface. That way session cookies aren't cross-origin.
"""
import http.server
import os
import socketserver
import urllib.error
import urllib.request

PORT = int(os.environ.get("PORT", 8011))
BACKEND = os.environ.get("BACKEND", "http://localhost:8081").rstrip("/")
os.chdir(os.path.dirname(os.path.abspath(__file__)))

HOP_BY_HOP = {
    "transfer-encoding", "connection", "keep-alive", "proxy-authenticate",
    "proxy-authorization", "te", "trailers", "upgrade", "content-length",
}
FORWARD_REQ_HEADERS = ("Content-Type", "Accept", "Cookie", "Authorization")


class SPAHandler(http.server.SimpleHTTPRequestHandler):
    def _proxy(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None

        fwd = {}
        for name in FORWARD_REQ_HEADERS:
            value = self.headers.get(name)
            if value is not None:
                fwd[name] = value

        req = urllib.request.Request(
            BACKEND + self.path, data=body, method=self.command, headers=fwd
        )
        try:
            resp = urllib.request.urlopen(req)
            status, out_headers, payload = resp.status, resp.headers, resp.read()
        except urllib.error.HTTPError as e:
            status, out_headers, payload = e.code, e.headers, e.read()
        except urllib.error.URLError as e:
            self.send_error(502, f"backend unreachable: {e.reason}")
            return

        self.send_response(status)
        for key, value in out_headers.items():
            if key.lower() in HOP_BY_HOP:
                continue
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if payload:
            self.wfile.write(payload)

    def _serve_static_or_spa(self):
        full_path = self.translate_path(self.path)
        if os.path.isfile(full_path):
            return super().do_GET()
        last = self.path.split("?", 1)[0].rsplit("/", 1)[-1]
        if "." in last:
            return super().do_GET()
        self.path = "/index.html"
        return super().do_GET()

    def do_GET(self):
        if self.path.startswith("/api/"):
            return self._proxy()
        return self._serve_static_or_spa()

    def do_POST(self):
        if self.path.startswith("/api/"):
            return self._proxy()
        self.send_error(404)

    def do_PUT(self):
        if self.path.startswith("/api/"):
            return self._proxy()
        self.send_error(404)

    def do_DELETE(self):
        if self.path.startswith("/api/"):
            return self._proxy()
        self.send_error(404)

    def do_OPTIONS(self):
        if self.path.startswith("/api/"):
            return self._proxy()
        self.send_error(404)


SPAHandler.extensions_map[".js"] = "application/javascript"


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


with ReusableTCPServer(("", PORT), SPAHandler) as httpd:
    print(f"cloudelog frontend at http://localhost:{PORT} (proxying /api -> {BACKEND})")
    httpd.serve_forever()
