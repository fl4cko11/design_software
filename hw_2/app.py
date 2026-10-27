"""Учебный HTTP API: healthcheck и заметки в PostgreSQL."""

import json
import os
import signal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

import psycopg2


DB_ENABLED = bool(os.environ.get("DB_HOST"))


def connect():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=3,
        options="-c statement_timeout=3000",
    )


def query(statement, parameters=()):
    # Контекст транзакции делает commit/rollback; соединение закрываем явно.
    connection = connect()
    try:
        with connection:
            with connection.cursor() as cursor:
                cursor.execute(statement, parameters)
                return cursor.fetchall() if cursor.description else []
    finally:
        connection.close()


class Handler(BaseHTTPRequestHandler):
    server_version = "HomeworkAPI"
    sys_version = ""

    def respond(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlsplit(self.path).path
        try:
            if path == "/health":
                if DB_ENABLED:
                    query("SELECT 1")
                self.respond(200, {
                    "status": "ok",
                    "database": "ok" if DB_ENABLED else "disabled",
                })
            elif path == "/":
                self.respond(200, {
                    "message": os.environ.get("APP_MESSAGE", "Hello from hw_2!"),
                    "endpoints": ["/health", "/notes"],
                })
            elif path == "/notes" and DB_ENABLED:
                rows = query("SELECT id, text FROM notes ORDER BY id DESC LIMIT 100")
                self.respond(200, [{"id": row[0], "text": row[1]} for row in rows])
            elif path == "/notes":
                self.respond(503, {"error": "Database is not configured"})
            else:
                self.respond(404, {"error": "Not found"})
        except psycopg2.Error:
            self.respond(503, {"error": "Database unavailable"})

    def do_POST(self):
        if urlsplit(self.path).path != "/notes":
            self.respond(404, {"error": "Not found"})
            return
        if not DB_ENABLED:
            self.respond(503, {"error": "Database is not configured"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 8192:
                self.respond(413, {"error": "Body must be 1..8192 bytes"})
                return
            payload = json.loads(self.rfile.read(length))
            text = payload.get("text") if isinstance(payload, dict) else None
            if not isinstance(text, str) or not 1 <= len(text.strip()) <= 1000:
                self.respond(400, {"error": "text must contain 1..1000 characters"})
                return
            rows = query("INSERT INTO notes (text) VALUES (%s) RETURNING id", (text.strip(),))
            self.respond(201, {"id": rows[0][0], "text": text.strip()})
        except (ValueError, UnicodeError):
            self.respond(400, {"error": "Invalid JSON or Content-Length"})
        except psycopg2.Error:
            self.respond(503, {"error": "Database unavailable"})

    def setup(self):
        super().setup()
        self.connection.settimeout(10)


def stop(_signum, _frame):
    raise SystemExit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop)
    if DB_ENABLED:
        query("CREATE TABLE IF NOT EXISTS notes ("
              "id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "
              "text VARCHAR(1000) NOT NULL)")
    port = int(os.environ.get("APP_PORT", "8080"))
    with ThreadingHTTPServer(("0.0.0.0", port), Handler) as server:
        print(f"Listening on port {port}; database enabled: {DB_ENABLED}", flush=True)
        server.serve_forever()
