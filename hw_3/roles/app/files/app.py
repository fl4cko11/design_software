"""HTTP-сервис лабораторной работы №3."""

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/health":
            status, payload = 200, {"status": "ok", "app": "hw_3"}
        elif path == "/":
            status, payload = 200, {"message": os.environ["APP_MESSAGE"]}
        else:
            status, payload = 404, {"error": "Not found"}

        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    with ThreadingHTTPServer(("0.0.0.0", int(os.environ["APP_PORT"])), Handler) as server:
        server.serve_forever()
