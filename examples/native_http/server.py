"""Loopback-only TLS fixture. Keys are generated per run outside the repository.
No public network dependency and no application/device trust-store mutation.
"""
import http.server
import pathlib
import signal
import ssl
import sys
import threading

stop = threading.Event()
certs = pathlib.Path(sys.argv[1])


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def handle(self):
        try:
            super().handle()
        except (ConnectionResetError, BrokenPipeError, ssl.SSLError):
            # Expected when clients cancel reads or enforce a response limit.
            pass

    def do_HEAD(self):
        self.handle_contract()

    def do_GET(self):
        self.handle_contract()

    def do_POST(self):
        self.handle_contract()

    def do_PATCH(self):
        self.handle_contract()

    def handle_contract(self):
        print(f"REQUEST {self.server.role} {self.command} {self.path}", flush=True)
        self.connection.settimeout(10)
        body = self.rfile.read(min(int(self.headers.get("Content-Length", "0")), 921601))
        try:
            if self.path == "/echo":
                assert self.command in ("POST", "PATCH")
                assert self.headers.get("Authorization") == "Bearer contract-only"
                payload, code = body, 200
            elif self.path == "/error":
                payload, code = bytes([0, 255, 13, 10, 42]), 422
            elif self.path == "/redirect":
                payload, code = b"redirect", 302
            elif self.path in ("/slow", "/cancel", "/cancel-close"):
                self.send_response(200)
                self.send_header("Content-Length", "6")
                self.end_headers()
                self.wfile.write(b"s"); self.wfile.flush()
                stop.wait(20)
                self.wfile.write(b"lowly")
                return
            elif self.path == "/large":
                self.send_response(200)
                self.send_header("Content-Length", "921601")
                self.end_headers()
                self.wfile.write(b"x" * 921601)
                return
            elif self.path == "/chunk-large":
                self.send_response(200)
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                for _ in range(113):
                    self.wfile.write(b"2000\r\n" + b"x" * 8192 + b"\r\n")
                self.wfile.write(b"0\r\n\r\n")
                return
            else:
                payload, code = "TLS OK 雪 😀\x00".encode(), 200
            self.send_response(code)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Set-Cookie", "a=1")
            self.send_header("Set-Cookie", "b=2")
            if code == 302:
                self.send_header("Location", "https://localhost:18443/must-not-follow")
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass


servers = []
for role in ("trusted", "wronghost", "untrusted", "cleartext"):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.role = role
    if role != "cleartext":
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certs / f"{role}.pem", certs / f"{role}.key")
        server.socket = context.wrap_socket(server.socket, server_side=True)
    servers.append(server)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"PORT {role} {server.server_port}", flush=True)
print("READY", flush=True)
signal.signal(signal.SIGTERM, lambda *_: stop.set())
signal.signal(signal.SIGINT, lambda *_: stop.set())
stop.wait()
for server in servers:
    server.shutdown()
    server.server_close()
