"""Run the Carrefour Chrome scraper as a Cloud Run Job and sync its catalog."""

print("[boot] Python scraper process started", flush=True)

import json
import os
import sqlite3
import sys
import urllib.error
import urllib.request

from google.auth.transport.requests import Request
from google.oauth2 import id_token

import carrefour_api as api


def sync_batch(endpoint: str, secret: str, bearer: str, items: list[dict]) -> dict:
    request = urllib.request.Request(
        endpoint,
        data=json.dumps({"items": items}, allow_nan=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {bearer}",
            "X-Catalog-Sync-Token": secret,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Catalog sync returned HTTP {exc.code}: {body}") from exc


def main() -> None:
    endpoint = os.environ.get("CARREFOUR_SYNC_URL", "").strip()
    secret = os.environ.get("CARREFOUR_CATALOG_SYNC_TOKEN", "").strip()
    if not endpoint or not secret:
        raise SystemExit("CARREFOUR_SYNC_URL and CARREFOUR_CATALOG_SYNC_TOKEN are required")

    print("[boot] Initializing temporary product database", flush=True)
    api.init_db()
    urls = api.DEFAULT_URLS
    scrolls = int(os.environ.get("CARREFOUR_SCROLLS", "20"))
    delay = float(os.environ.get("CARREFOUR_DELAY", "1.5"))
    print(f"Starting Chrome scrape for {len(urls)} Carrefour pages", flush=True)
    print("[boot] Starting browser scrape", flush=True)
    items = api.call_scraper(urls, scrolls, delay)
    if not items:
        raise RuntimeError("Scraper found no products; refusing to publish an empty catalog")

    saved = api.save_items(items)
    print(f"Scrape collected {len(items)} rows; normalized {saved} products", flush=True)

    audience = endpoint.rstrip("/")
    bearer = id_token.fetch_id_token(Request(), audience)
    connection = sqlite3.connect(f"file:{api.DB_PATH}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    cursor = connection.execute(
        "SELECT id, store, name, brand, price, old_price, url, first_seen, last_seen "
        "FROM products ORDER BY id"
    )
    sent = 0
    while batch := cursor.fetchmany(200):
        result = sync_batch(endpoint, secret, bearer, [dict(row) for row in batch])
        sent += int(result.get("received", len(batch)))
        print(f"Synced {sent} catalog products", flush=True)
    connection.close()
    if sent == 0:
        raise RuntimeError("Scrape completed but no catalog rows were synced")
    print(f"Catalog sync complete: {sent} products", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Scraper job failed: {type(exc).__name__}: {exc}", file=sys.stderr, flush=True)
        raise
