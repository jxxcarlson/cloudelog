#!/usr/bin/env python3
"""cloudelog frontend dev server. PORT env var (default 8011)."""
import http.server
import socketserver
import os

PORT = int(os.environ.get("PORT", 8011))
os.chdir(os.path.dirname(os.path.abspath(__file__)))

Handler = http.server.SimpleHTTPRequestHandler
Handler.extensions_map['.js'] = 'application/javascript'

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

with ReusableTCPServer(("", PORT), Handler) as httpd:
    print(f"cloudelog frontend at http://localhost:{PORT}")
    httpd.serve_forever()
