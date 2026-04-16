#!/usr/bin/env python3
"""
Minimal static server for the autism-search UI.
Serves index.html at https://0.0.0.0:18000/
"""
import http.server
import socketserver
import ssl
import os
from pathlib import Path

HOST     = "0.0.0.0"
PORT     = 18000
API_PORT = 3001

CERT_DIR = Path(__file__).parent.parent / "certs"
CERT     = CERT_DIR / "cert.pem"
KEY      = CERT_DIR / "key.pem"

os.chdir(os.path.dirname(os.path.abspath(__file__)))


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Prevent browsers from caching stale HTML
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, fmt, *args):
        print(f"  {self.address_string()} — {fmt % args}")


class HTTPSServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    """Multi-threaded TCPServer that wraps each accepted connection with TLS."""

    allow_reuse_address = True
    daemon_threads = True  # threads die with the main process

    def __init__(self, server_address, handler, cert, key):
        super().__init__(server_address, handler)
        self._ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self._ssl_ctx.load_cert_chain(certfile=cert, keyfile=key)

    def get_request(self):
        # Accept raw TCP only — never block the main loop with a handshake
        return self.socket.accept()

    def process_request_thread(self, request, client_address):
        # TLS handshake runs in a worker thread so the main loop stays free
        try:
            tls_sock = self._ssl_ctx.wrap_socket(request, server_side=True)
        except ssl.SSLError as e:
            print(f"  SSL error from {client_address}: {e}")
            request.close()
            return
        try:
            self.finish_request(tls_sock, client_address)
        except Exception:
            self.handle_error(tls_sock, client_address)
        finally:
            self.shutdown_request(tls_sock)


print(f"  UI  → https://{HOST}:{PORT}/")
print(f"  API → https://{HOST}:{API_PORT}/")
print("  Ctrl+C to stop\n")

with HTTPSServer((HOST, PORT), Handler, CERT, KEY) as httpd:
    httpd.serve_forever()
