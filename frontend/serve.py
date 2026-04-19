#!/usr/bin/env python3
"""cloudelog frontend dev server. PORT env var (default 8011).

SPA-aware: any GET for a path that isn't a real file and doesn't look like
an asset (no file extension) falls back to index.html so Browser.application's
client-side routing survives a reload or direct /login navigation.
"""
import http.server
import os
import socketserver

PORT = int(os.environ.get("PORT", 8011))
os.chdir(os.path.dirname(os.path.abspath(__file__)))


class SPAHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        full_path = self.translate_path(self.path)
        if os.path.isfile(full_path):
            return super().do_GET()
        # Not a real file. If the URL looks like an asset (has an extension
        # on the last segment, e.g. /favicon.ico), let it 404 normally so the
        # browser doesn't try to parse index.html as an icon.
        last = self.path.split("?", 1)[0].rsplit("/", 1)[-1]
        if "." in last:
            return super().do_GET()
        self.path = "/index.html"
        return super().do_GET()


SPAHandler.extensions_map[".js"] = "application/javascript"


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


with ReusableTCPServer(("", PORT), SPAHandler) as httpd:
    print(f"cloudelog frontend at http://localhost:{PORT}")
    httpd.serve_forever()
