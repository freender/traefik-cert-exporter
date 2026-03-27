#!/usr/bin/env python3

import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


SERVE_PATH = os.environ.get("SERVE_PATH", "/source")
LISTEN_HOST = os.environ.get("LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8080"))
API_TOKEN = os.environ.get("API_TOKEN") or os.environ.get("HTTP_AUTH_TOKEN", "")

FILES = {
    "/acme.json": ("acme.json", "application/json"),
    "/fileConfig.yml": ("fileConfig.yml", "text/yaml; charset=utf-8"),
}


class Handler(BaseHTTPRequestHandler):
    server_version = "traefik-sync-source/1.0"

    def do_HEAD(self):
        self._handle(send_body=False)

    def do_GET(self):
        self._handle(send_body=True)

    def _handle(self, send_body: bool):
        if self.path == "/healthz":
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            if send_body:
                self.wfile.write(b"ok\n")
            return

        if self.path not in FILES:
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        if API_TOKEN:
            header = self.headers.get("Authorization", "")
            expected = f"Bearer {API_TOKEN}"
            if header != expected:
                self.send_response(HTTPStatus.UNAUTHORIZED)
                self.send_header("WWW-Authenticate", "Bearer")
                self.end_headers()
                return

        file_name, content_type = FILES[self.path]
        file_path = os.path.join(SERVE_PATH, file_name)
        if not os.path.isfile(file_path):
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        file_size = os.path.getsize(file_path)
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(file_size))
        self.end_headers()

        if not send_body:
            return

        with open(file_path, "rb") as handle:
            while True:
                chunk = handle.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def log_message(self, format, *args):
        print(f"[{self.log_date_time_string()}] {self.address_string()} {format % args}")


def main():
    print(f"Serving Traefik sync files from {SERVE_PATH} on {LISTEN_HOST}:{LISTEN_PORT}")
    if API_TOKEN:
        print("HTTP bearer token auth enabled")
    else:
        print("WARNING: HTTP bearer token auth disabled")

    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
