"""
Carrefour Egypt prices API.

Wraps carrefour_scraper.py (same folder). Scraping is slow, so the API never
scrapes per request: POST /refresh runs the scraper in the background and saves
results to SQLite, and every other endpoint reads from SQLite.

Run:
    pip install fastapi uvicorn
    uvicorn carrefour_api:app --host 127.0.0.1 --port 8000
Docs UI: http://127.0.0.1:8000/docs
"""
import hashlib
import inspect
import json
import os
import re
import sqlite3
import threading
import uuid
from contextlib import asynccontextmanager, contextmanager
from datetime import datetime, timezone
from typing import Optional
from urllib.parse import urlsplit, urlunsplit

from fastapi import BackgroundTasks, FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

import carrefour_scraper as cs

DB_PATH = os.getenv("PRICES_DB", "prices.db")
STORE = "carrefour"  # a "store" column is kept so other stores can be added later
# The site blocked headless mode for you, so default to a visible browser window.
HEADED = os.getenv("CARREFOUR_HEADED", "1") == "1"
DEFAULT_URLS = [
    "https://www.carrefouregypt.com/mafegy/en/c/FEGY1700000",
    "https://www.carrefouregypt.com/mafegy/en/c/02054",
    "https://www.carrefouregypt.com/mafegy/en/search?keyword=ketchup",
    "https://www.carrefouregypt.com/mafegy/en/search?keyword=oil",
    "https://www.carrefouregypt.com/mafegy/en/search?keyword=rivoli%20hand%20soap",
    "https://www.carrefouregypt.com/mafegy/en/search?keyword=always",
    "https://www.carrefouregypt.com/mafegy/en/search?keyword=milk",
]

_scrape_lock = threading.Lock()  # one scrape at a time (shared Chrome profile)


# ---------- DB ----------
@contextmanager
def db():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    try:
        yield con
        con.commit()
    finally:
        con.close()


def init_db():
    with db() as con:
        con.executescript(
            """
            CREATE TABLE IF NOT EXISTS products (
                id TEXT PRIMARY KEY, store TEXT NOT NULL, name TEXT NOT NULL,
                brand TEXT, price REAL, old_price REAL, url TEXT,
                first_seen TEXT NOT NULL, last_seen TEXT NOT NULL, raw TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);
            CREATE TABLE IF NOT EXISTS price_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT, product_id TEXT NOT NULL,
                price REAL, seen_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_hist_product ON price_history(product_id);
            CREATE TABLE IF NOT EXISTS jobs (
                id TEXT PRIMARY KEY, status TEXT NOT NULL, urls TEXT,
                started_at TEXT, finished_at TEXT, count INTEGER DEFAULT 0, error TEXT
            );
            """
        )
        # a crash mid-scrape would leave a job stuck on "running"
        con.execute(
            "UPDATE jobs SET status='failed', error='server restarted' WHERE status='running'"
        )


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


# ---------- normalising scraper output ----------
def to_float(v) -> Optional[float]:
    if v is None or v == "":
        return None
    if isinstance(v, (int, float)):
        return float(v)
    m = re.search(r"\d[\d,]*\.?\d*", str(v))
    return float(m.group().replace(",", "")) if m else None


def pick(item: dict, *keys):
    for k in keys:
        if item.get(k) not in (None, ""):
            return item[k]
    return None


def normalise(item: dict) -> Optional[dict]:
    name = pick(item, "name", "title", "product_name")
    if not name:
        return None
    url = pick(item, "url", "link", "product_url")
    if url:
        parts = urlsplit(str(url))
        url = urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))
    key = url or f"{STORE}:{name}"
    return {
        "id": hashlib.sha1(key.encode()).hexdigest()[:16],
        "name": str(name).strip(),
        "brand": pick(item, "brand", "brand_name"),
        "price": to_float(pick(item, "price", "current_price")),
        "old_price": to_float(pick(item, "old_price", "was_price", "original_price")),
        "url": url,
        "raw": json.dumps(item, ensure_ascii=False, default=str),
    }


def save_items(items: list) -> int:
    ts, saved = now(), 0
    with db() as con:
        for item in items:
            p = normalise(item)
            if not p:
                continue
            # Collapse older query-string URL variants for the same product while
            # preserving their existing price history.
            duplicates = con.execute(
                "SELECT id FROM products WHERE store=? AND lower(name)=lower(?) AND id<>?",
                (STORE, p["name"], p["id"]),
            ).fetchall()
            for duplicate in duplicates:
                con.execute(
                    "UPDATE price_history SET product_id=? WHERE product_id=?",
                    (p["id"], duplicate["id"]),
                )
                con.execute("DELETE FROM products WHERE id=?", (duplicate["id"],))
            old = con.execute(
                "SELECT price FROM products WHERE id=?", (p["id"],)
            ).fetchone()
            if old is None:
                con.execute(
                    "INSERT INTO products (id,store,name,brand,price,old_price,url,first_seen,last_seen,raw)"
                    " VALUES (?,?,?,?,?,?,?,?,?,?)",
                    (p["id"], STORE, p["name"], p["brand"], p["price"], p["old_price"],
                     p["url"], ts, ts, p["raw"]),
                )
                con.execute(
                    "INSERT INTO price_history (product_id,price,seen_at) VALUES (?,?,?)",
                    (p["id"], p["price"], ts),
                )
            else:
                con.execute(
                    "UPDATE products SET name=?,brand=?,price=?,old_price=?,url=?,last_seen=?,raw=? WHERE id=?",
                    (p["name"], p["brand"], p["price"], p["old_price"], p["url"], ts, p["raw"], p["id"]),
                )
                if old["price"] != p["price"]:  # only log actual price changes
                    con.execute(
                        "INSERT INTO price_history (product_id,price,seen_at) VALUES (?,?,?)",
                        (p["id"], p["price"], ts),
                    )
            saved += 1
    return saved


# ---------- running the scraper ----------
def call_scraper(urls, scrolls, delay):
    # CLI call was scrape(urls, scrolls, headed, delay, dump_json); newer versions may
    # have an extra trailing "manual" arg, so match however many params it takes.
    n = len(inspect.signature(cs.scrape).parameters)
    args = [urls, scrolls, HEADED, delay, None, False][:n]
    return cs.dedupe(cs.scrape(*args))


def run_job(job_id: str, urls: list, scrolls: int, delay: float):
    with _scrape_lock:
        try:
            items = call_scraper(urls, scrolls, delay)
            count = save_items(items)
            status, error = "done", None
        except Exception as e:  # keep the real error visible via GET /jobs/{id}
            count, status, error = 0, "failed", f"{type(e).__name__}: {e}"[:2000]
    with db() as con:
        con.execute(
            "UPDATE jobs SET status=?, finished_at=?, count=?, error=? WHERE id=?",
            (status, now(), count, error, job_id),
        )


# ---------- API ----------
@asynccontextmanager
async def lifespan(_):
    init_db()
    yield


app = FastAPI(title="Carrefour Egypt Prices API", version="1.0", lifespan=lifespan)


class RefreshRequest(BaseModel):
    urls: list[str] = Field(default_factory=lambda: list(DEFAULT_URLS))
    scrolls: int = Field(20, ge=1, le=100)
    delay: float = Field(1.5, ge=0)


@app.get("/health")
def health():
    with db() as con:
        n = con.execute("SELECT COUNT(*) c FROM products").fetchone()["c"]
        last = con.execute("SELECT MAX(last_seen) m FROM products").fetchone()["m"]
    return {"ok": True, "products": n, "last_update": last}


@app.post("/refresh", status_code=202)
def refresh(req: RefreshRequest, bg: BackgroundTasks):
    with db() as con:
        if con.execute("SELECT 1 FROM jobs WHERE status='running'").fetchone():
            raise HTTPException(409, "A refresh is already running")
        job_id = uuid.uuid4().hex[:12]
        con.execute(
            "INSERT INTO jobs (id,status,urls,started_at) VALUES (?,?,?,?)",
            (job_id, "running", json.dumps(req.urls), now()),
        )
    bg.add_task(run_job, job_id, req.urls, req.scrolls, req.delay)
    return {"job_id": job_id, "status": "running"}


@app.get("/jobs/{job_id}")
def get_job(job_id: str):
    with db() as con:
        row = con.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
    if not row:
        raise HTTPException(404, "Job not found")
    return dict(row)


@app.get("/products")
def list_products(
    q: Optional[str] = Query(None, description="search words in name/brand, e.g. 'rice 5kg'"),
    store: str = STORE,
    brand: Optional[str] = None,
    min_price: Optional[float] = None,
    max_price: Optional[float] = None,
    on_sale: bool = False,
    sort: str = Query("name", pattern="^(name|price_asc|price_desc|recent)$"),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    where, params = ["store=?"], [store]
    for word in (q or "").split():
        where.append("(name LIKE ? OR brand LIKE ?)")
        params += [f"%{word}%", f"%{word}%"]
    if brand:
        where.append("brand LIKE ?")
        params.append(f"%{brand}%")
    if min_price is not None:
        where.append("price >= ?")
        params.append(min_price)
    if max_price is not None:
        where.append("price <= ?")
        params.append(max_price)
    if on_sale:
        where.append("old_price IS NOT NULL AND old_price > price")
    order = {
        "name": "name COLLATE NOCASE",
        "price_asc": "price IS NULL, price ASC",
        "price_desc": "price DESC",
        "recent": "last_seen DESC",
    }[sort]
    sql = f"FROM products WHERE {' AND '.join(where)}"
    with db() as con:
        total = con.execute(f"SELECT COUNT(*) c {sql}", params).fetchone()["c"]
        rows = con.execute(
            f"SELECT id,store,name,brand,price,old_price,url,last_seen {sql}"
            f" ORDER BY {order} LIMIT ? OFFSET ?",
            params + [limit, offset],
        ).fetchall()
    return {"total": total, "limit": limit, "offset": offset, "items": [dict(r) for r in rows]}


@app.get("/products/{product_id}")
def get_product(product_id: str):
    with db() as con:
        row = con.execute(
            "SELECT id,store,name,brand,price,old_price,url,first_seen,last_seen FROM products WHERE id=?",
            (product_id,),
        ).fetchone()
    if not row:
        raise HTTPException(404, "Product not found")
    return dict(row)


@app.get("/products/{product_id}/history")
def price_history(product_id: str):
    with db() as con:
        rows = con.execute(
            "SELECT price, seen_at FROM price_history WHERE product_id=? ORDER BY seen_at",
            (product_id,),
        ).fetchall()
    if not rows:
        raise HTTPException(404, "No history for this product")
    return {"product_id": product_id, "history": [dict(r) for r in rows]}
