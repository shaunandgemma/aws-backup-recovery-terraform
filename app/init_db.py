"""Create the lab database with synthetic orders. Run once on EC2."""

import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

DB_PATH = Path("/data/orders/orders.db")


def main():
    if not os.path.ismount("/data"):
        raise SystemExit("STOP: /data is not mounted.")

    if not DB_PATH.parent.is_dir():
        raise SystemExit("STOP: /data/orders does not exist.")

    if DB_PATH.exists():
        raise SystemExit("STOP: database already exists; leaving it unchanged.")

    created_at = datetime.now(timezone.utc).isoformat(timespec="seconds")

    orders = [
        ("ORD-1001", "Notebook", 2, created_at),
        ("ORD-1002", "Keyboard", 1, created_at),
        ("ORD-1003", "USB cable", 3, created_at),
    ]

    with sqlite3.connect(DB_PATH) as connection:
        connection.execute("""
            CREATE TABLE orders (
                order_id TEXT PRIMARY KEY,
                product TEXT NOT NULL,
                quantity INTEGER NOT NULL CHECK (quantity > 0),
                created_at TEXT NOT NULL
            )
        """)

        connection.executemany(
            """
            INSERT INTO orders (order_id, product, quantity, created_at)
            VALUES (?, ?, ?, ?)
            """,
            orders,
        )

    print(f"Created database: {DB_PATH}")
    print(f"Inserted {len(orders)} synthetic orders.")


if __name__ == "__main__":
    main()