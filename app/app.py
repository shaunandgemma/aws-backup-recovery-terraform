"""Small orders API for the backup and recovery lab."""

import json
import os
import sqlite3
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from uuid import uuid4

DB_URI = "file:/data/orders/orders.db?mode=rw"


def connect_database():
    if not os.path.ismount("/data"):
        raise RuntimeError("/data is not mounted.")

    # mode=rw requires an existing database; it cannot create a replacement.
    connection = sqlite3.connect(DB_URI, uri=True, timeout=5)
    connection.row_factory = sqlite3.Row
    return connection


class OrdersHandler(BaseHTTPRequestHandler):
    def send_json(self, status, payload):
        body = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path not in ("/health", "/orders"):
            self.send_json(404, {"error": "Endpoint not found."})
            return

        connection = None
        try:
            connection = connect_database()

            if self.path == "/health":
                count = connection.execute(
                    "SELECT COUNT(*) FROM orders"
                ).fetchone()[0]
                self.send_json(200, {"status": "ok", "order_count": count})
            else:
                rows = connection.execute(
                    "SELECT order_id, product, quantity, created_at "
                    "FROM orders ORDER BY created_at, order_id"
                ).fetchall()
                self.send_json(200, {"orders": [dict(row) for row in rows]})

        except (sqlite3.Error, RuntimeError):
            self.send_json(503, {"error": "Database unavailable."})
        finally:
            if connection is not None:
                connection.close()

    def do_POST(self):
        if self.path != "/orders":
            self.send_json(404, {"error": "Endpoint not found."})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 1 <= length <= 4096:
                raise ValueError("Request must contain 1–4096 bytes.")

            payload = json.loads(self.rfile.read(length))
            if not isinstance(payload, dict):
                raise ValueError("Request must be a JSON object.")

            product = payload.get("product")
            quantity = payload.get("quantity")

            if not isinstance(product, str) or not 1 <= len(product.strip()) <= 100:
                raise ValueError("Product must contain 1–100 characters.")
            if type(quantity) is not int or not 1 <= quantity <= 1000:
                raise ValueError("Quantity must be an integer from 1 to 1000.")

        except (ValueError, UnicodeDecodeError) as error:
            self.send_json(400, {"error": str(error)})
            return

        order = {
            "order_id": "ORD-" + uuid4().hex[:12].upper(),
            "product": product.strip(),
            "quantity": quantity,
            "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }

        connection = None
        try:
            connection = connect_database()
            with connection:
                connection.execute(
                    "INSERT INTO orders "
                    "(order_id, product, quantity, created_at) "
                    "VALUES (?, ?, ?, ?)",
                    (
                        order["order_id"],
                        order["product"],
                        order["quantity"],
                        order["created_at"],
                    ),
                )
            self.send_json(201, order)

        except (sqlite3.Error, RuntimeError):
            self.send_json(503, {"error": "Unable to save order."})
        finally:
            if connection is not None:
                connection.close()


if __name__ == "__main__":
    database = connect_database()
    try:
        database.execute("SELECT COUNT(*) FROM orders").fetchone()
    finally:
        database.close()

    server = HTTPServer(("127.0.0.1", 8080), OrdersHandler)
    print("Orders application listening on 127.0.0.1:8080", flush=True)
    server.serve_forever()