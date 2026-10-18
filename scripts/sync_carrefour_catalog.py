#!/usr/bin/env python3
"""Copy the local Carrefour SQLite catalog into the Firebase Functions API.

Set CARREFOUR_SYNC_URL and CARREFOUR_CATALOG_SYNC_TOKEN before running.
The database is opened read-only and sent in small authenticated batches.
"""

import json
import os
import sqlite3
import sys
import urllib.error
import urllib.request


def send_batch(url, token, identity_token, items):
    payload = json.dumps({"items": items}, allow_nan=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {identity_token}",
            "X-Catalog-Sync-Token": token,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Catalog sync returned HTTP {exc.code}: {detail}") from exc


def main():
    if len(sys.argv) > 2:
        raise SystemExit("Usage: python3 scripts/sync_carrefour_catalog.py [prices.db]")
    database_path = sys.argv[1] if len(sys.argv) == 2 else "prices.db"
    endpoint = os.environ.get("CARREFOUR_SYNC_URL", "").strip()
    token = os.environ.get("CARREFOUR_CATALOG_SYNC_TOKEN", "").strip()
    identity_token = os.environ.get("GOOGLE_ID_TOKEN", "").strip()
    if not endpoint or not token or not identity_token:
        raise SystemExit(
            "Set CARREFOUR_SYNC_URL, CARREFOUR_CATALOG_SYNC_TOKEN, and GOOGLE_ID_TOKEN first."
        )

    connection = sqlite3.connect(f"file:{os.path.abspath(database_path)}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    cursor = connection.execute(
        "SELECT id, store, name, brand, price, old_price, url, first_seen, last_seen "
        "FROM products ORDER BY id"
    )
    sent = 0
    while batch := cursor.fetchmany(200):
        items = [dict(row) for row in batch]
        result = send_batch(endpoint, token, identity_token, items)
        sent += result.get("received", len(items))
        print(f"Synced {sent} products")
    connection.close()
    print(f"Catalog sync complete: {sent} products")


if __name__ == "__main__":
    main()
