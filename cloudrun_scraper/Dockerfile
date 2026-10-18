FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    CARREFOUR_HEADED=1 \
    PRICES_DB=/tmp/prices.db

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg xvfb \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
       | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
       > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
RUN python -m playwright install-deps chrome

COPY carrefour_api.py carrefour_scraper.py runner.py ./

CMD ["sh", "-c", "set -eu; echo '[boot] Starting Xvfb'; Xvfb :99 -screen 0 1366x900x24 -nolisten tcp -ac >/tmp/xvfb.log 2>&1 & XVFB_PID=$!; sleep 2; if ! kill -0 \"$XVFB_PID\" 2>/dev/null; then cat /tmp/xvfb.log; exit 1; fi; export DISPLAY=:99; echo '[boot] Xvfb ready; starting Python'; exec python -u runner.py"]
