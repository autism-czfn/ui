#!/usr/bin/env python3
"""
Minimal static server for the autism-search UI.
Serves index.html at http://192.168.1.9:18000/
"""
import http.server
import socketserver
import os

HOST = "192.168.1.9"
PORT = 18000
API_PORT = 3001

os.chdir(os.path.dirname(os.path.abspath(__file__)))


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"  {self.address_string()} — {fmt % args}")


socketserver.TCPServer.allow_reuse_address = True

print(f"  UI  → http://{HOST}:{PORT}/")
print(f"  API → http://{HOST}:{API_PORT}/")
print("  Ctrl+C to stop\n")

with socketserver.TCPServer((HOST, PORT), Handler) as httpd:
    httpd.serve_forever()
