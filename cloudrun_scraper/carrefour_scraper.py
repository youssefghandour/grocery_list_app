"""
Carrefour Egypt price scraper (Playwright).

Setup:
    pip install playwright
    playwright install chromium

Usage:
    python carrefour_scraper.py "https://www.carrefouregypt.com/mafegy/en/c/FEGY1700000" -o prices.csv
    python carrefour_scraper.py URL1 URL2 --scrolls 25 --headed --dump-json debug.json

How it works:
    1. Opens the category/search page in a real browser.
    2. Listens to every JSON response and pulls out anything that looks like a
       product (name + price). This is the cleanest data when the site uses an API.
    3. If nothing is found that way, falls back to reading product cards from the DOM.
    4. Saves everything to CSV (deduped).

Note: respect the site's Terms of Service / robots.txt and keep the delays polite.
"""
import argparse
import csv
import datetime as dt
import json
import re
import time
from urllib.parse import urlsplit, urlunsplit

from playwright.sync_api import sync_playwright

PROFILE_DIR = "./.chrome_profile"
NAME_KEYS = ("name", "title", "productName")
# Do not use the generic "value" key: Carrefour includes unrelated numeric
# values under it (for example 2.0), which can be mistaken for a product price.
PRICE_KEYS = ("price", "sellingPrice", "offerPrice", "discountedPrice", "finalPrice")
OLD_PRICE_KEYS = ("originalPrice", "wasPrice", "oldPrice", "strikePrice", "listPrice")
PRICE_RE = re.compile(r"(\d[\d,]*\.?\d*)\s*(?:EGP|E£|LE|جنيه|ج\.م)|(?:EGP|E£|LE)\s*(\d[\d,]*\.?\d*)", re.I)


def to_num(v):
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        m = re.search(r"\d[\d,]*\.?\d*", v)
        if m:
            return float(m.group().replace(",", ""))
    return None


def pick_price(d, keys):
    for k in keys:
        if k in d:
            v = d[k]
            if isinstance(v, dict):
                for kk in PRICE_KEYS:
                    if kk in v and to_num(v[kk]) is not None:
                        return to_num(v[kk])
            elif to_num(v) is not None:
                return to_num(v)
    return None


def walk(obj, out, source):
    """Recursively find dicts that look like products."""
    if isinstance(obj, dict):
        name = next((obj[k] for k in NAME_KEYS if isinstance(obj.get(k), str)), None)
        price = pick_price(obj, PRICE_KEYS)
        if name and price is not None and len(name) > 2:
            url = obj.get("url") or obj.get("link") or obj.get("productUrl") or ""
            brand = obj.get("brand")
            if isinstance(brand, dict):
                brand = brand.get("name")
            out.append({
                "name": name.strip(),
                "price": price,
                "old_price": pick_price(obj, OLD_PRICE_KEYS),
                "brand": brand or "",
                "url": url,
                "source": source,
            })
        for v in obj.values():
            walk(v, out, source)
    elif isinstance(obj, list):
        for v in obj:
            walk(v, out, source)


DOM_JS = """
() => {
  const seen = new Set(), rows = [];
  document.querySelectorAll('a[href*="/p/"]').forEach(a => {
    if (seen.has(a.href)) return;
    seen.add(a.href);
    let el = a;
    for (let i = 0; i < 5 && el.parentElement; i++) {
      el = el.parentElement;
      if (/EGP|E£|جنيه/i.test(el.innerText || '')) break;
    }
    rows.push({url: a.href, text: (el.innerText || '').trim()});
  });
  return rows;
}
"""


def parse_dom_rows(rows):
    out = []
    for r in rows:
        lines = [l.strip() for l in r["text"].split("\n") if l.strip()]
        # Carrefour renders some card prices as separate text nodes, e.g.
        # "EGP", "79", ". 99". Parse the full card text after joining lines so
        # those become a currency-labelled 79.99 instead of being dropped.
        raw_text = r["text"]
        stock_counts = {
            float(m.group(1))
            for m in re.finditer(r"\bOnly\s+(\d+)\s+left\b", raw_text, re.I)
        }
        # The cards also include inventory labels such as "Only 4 left". Strip
        # them before parsing, and remove any matching number if the site's DOM
        # has placed it next to a currency label.
        text = re.sub(r"\bOnly\s+\d+\s+left\b", " ", raw_text, flags=re.I)
        text = re.sub(r"\s+", " ", text).strip()
        prices = []
        for m in re.finditer(
            r"(?:EGP|E£|LE|جنيه|ج\.م)\s*(\d[\d,]*)(?:\s*\.\s*(\d{1,2}))?|"
            r"(\d[\d,]*)(?:\s*\.\s*(\d{1,2}))?\s*(?:EGP|E£|LE|جنيه|ج\.م)",
            text,
            re.I,
        ):
            whole = m.group(1) or m.group(3)
            cents = m.group(2) or m.group(4) or ""
            prices.append(float(whole.replace(",", "") + ("." + cents if cents else "")))
        prices = [price for price in prices if price not in stock_counts] or prices
        name_lines = [
            l for l in lines
            if not PRICE_RE.search(l) and not re.fullmatch(r"[\d.,%\s\-]+", l)
        ]
        if not prices or not name_lines:
            continue
        out.append({
            "name": max(name_lines, key=len),
            "price": min(prices),
            "old_price": max(prices) if len(prices) > 1 else None,
            "brand": "",
            "url": r["url"],
            "source": "dom",
        })
    return out


def scrape(urls, scrolls, headed, delay, dump_json, manual=False):
    products, raw_json = [], []

    with sync_playwright() as p:
        # Persistent profile: cookies/challenge results survive between runs
        ctx = p.chromium.launch_persistent_context(
            user_data_dir=PROFILE_DIR,
            channel="chrome",  # real installed Google Chrome
            headless=not headed,
            args=[
                "--disable-http2",
                "--disable-blink-features=AutomationControlled",
            ],
            locale="en-US",
            viewport={"width": 1366, "height": 900},
        )
        page = ctx.pages[0] if ctx.pages else ctx.new_page()

        def on_response(resp):
            try:
                if "json" not in (resp.headers.get("content-type") or ""):
                    return
                data = resp.json()
                found = []
                walk(data, found, "api")
                if found:
                    products.extend(found)
                    raw_json.append({"url": resp.url, "count": len(found)})
            except Exception:
                pass

        page.on("response", on_response)

        for url in urls:
            print(f"[+] Opening {url}")
            try:
                # "commit" = server answered; don't wait for the whole page
                page.goto(url, wait_until="commit", timeout=120000)
                page.wait_for_load_state("domcontentloaded", timeout=60000)
            except Exception as e:
                print(f"[!] Slow/blocked navigation ({type(e).__name__}), continuing anyway")
            page.wait_for_timeout(5000)
            if manual:
                input("[?] Solve any challenge/popup in the browser, wait for products to show, then press Enter... ")

            # dismiss cookie/location popups if present (best effort)
            for label in ("Accept", "Accept All", "Got it", "Close"):
                try:
                    page.get_by_role("button", name=label).first.click(timeout=1500)
                except Exception:
                    pass

            last_h = 0
            for i in range(scrolls):
                page.mouse.wheel(0, 3000)
                page.wait_for_timeout(int(delay * 1000))
                for label in ("Load more", "Show more", "View more"):
                    try:
                        page.get_by_role("button", name=label).first.click(timeout=500)
                    except Exception:
                        pass
                h = page.evaluate("document.body.scrollHeight")
                if h == last_h and i > 2:
                    break
                last_h = h

            # Read visible product cards too: some API responses include non-price
            # numeric values in generic "value" fields. Currency-labelled DOM prices
            # provide a reliable fallback and can replace those API values.
            products.extend(parse_dom_rows(page.evaluate(DOM_JS)))

        ctx.close()

    if dump_json:
        with open(dump_json, "w", encoding="utf-8") as f:
            json.dump(raw_json, f, ensure_ascii=False, indent=2)
    return products


def canonical_url(url):
    if not url:
        return ""
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


def dedupe(items):
    selected = {}
    for it in items:
        url = canonical_url(it.get("url", ""))
        key = ("url", url) if url else ("name", it["name"].strip().lower())
        previous = selected.get(key)
        if previous is None or (it.get("source") == "dom" and previous.get("source") != "dom"):
            selected[key] = it
    return list(selected.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("urls", nargs="+", help="Category or search page URL(s)")
    ap.add_argument("-o", "--output", default="carrefour_prices.csv")
    ap.add_argument("--scrolls", type=int, default=15)
    ap.add_argument("--delay", type=float, default=1.5, help="seconds between scrolls")
    ap.add_argument("--headed", action="store_true", help="show the browser window")
    ap.add_argument("--manual", action="store_true", help="pause so you can solve a challenge manually (use with --headed)")
    ap.add_argument("--dump-json", help="save which API endpoints returned products (debug)")
    args = ap.parse_args()

    items = dedupe(scrape(args.urls, args.scrolls, args.headed, args.delay, args.dump_json, args.manual))
    ts = dt.datetime.now().isoformat(timespec="seconds")
    with open(args.output, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=["name", "brand", "price", "old_price", "url", "source", "scraped_at"])
        w.writeheader()
        for it in items:
            w.writerow({**it, "scraped_at": ts})
    print(f"[✓] Saved {len(items)} products -> {args.output}")


if __name__ == "__main__":
    main()
