// Public, non-destructive checks. Never authenticates or creates app data.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const site = 'https://na2slna.web.app';
const cloud = 'https://us-central1-animemusic-e8c09.cloudfunctions.net';
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const request = (url, options = {}) => fetch(url, {...options, signal: AbortSignal.timeout(30000)});

(async () => {
  const results = [];
  for (const name of ['joinHousehold', 'createPaymobOrder', 'getPaymentCapabilities', 'verifyStorePurchase']) {
    const response = await request(`${cloud}/${name}`, {method: 'POST',
      headers: {'Content-Type': 'application/json'}, body: JSON.stringify({data: {}})});
    assert.equal(response.status, 401, `${name} must require authentication`);
    assert.equal((await response.json()).error.status, 'UNAUTHENTICATED');
    results.push({check: `${name} rejects unauthenticated requests`, status: response.status});
  }
  const webhook = await request(`${cloud}/paymobWebhook`, {method: 'POST',
    headers: {'Content-Type': 'application/json'}, body: JSON.stringify({obj: {}})});
  assert.equal(webhook.status, 503, 'Unconfigured payment webhook must be disabled');
  assert.equal(await webhook.text(), 'Payments unavailable');
  results.push({check: 'Unconfigured payment webhook cannot grant access', status: webhook.status});
  for (const file of ['index.html', 'main.dart.js', 'flutter_bootstrap.js', 'manifest.json', '.well-known/assetlinks.json']) {
    const response = await request(`${site}/${file}`, {headers: {'Cache-Control': 'no-cache'}});
    assert.equal(response.status, 200, file);
    const bytes = Buffer.from(await response.arrayBuffer());
    const expected = fs.readFileSync(path.join(__dirname, '../build/web', file));
    assert.equal(hash(bytes), hash(expected), `${file} does not match this release`);
    results.push({check: `${file} matches built release`, sha256: hash(bytes)});
  }
  for (const route of ['/help', '/privacy', '/join/ABC234']) {
    const response = await request(`${site}${route}`);
    assert.equal(response.status, 200, route);
    assert.match(response.headers.get('content-type'), /text\/html/);
    const html = await response.text();
    if (route === '/help') assert.match(html, /Help|Support/i);
    if (route === '/privacy') assert.match(html, /Privacy/i);
    if (route.startsWith('/join/')) assert.match(html, /flutter_bootstrap\.js/);
    results.push({check: `${route} serves expected page`, status: response.status});
  }
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../build/web/manifest.json')));
  for (const icon of manifest.icons) {
    const response = await request(`${site}/${icon.src}`);
    assert.equal(response.status, 200, icon.src);
    assert.match(response.headers.get('content-type'), /^image\//, icon.src);
    results.push({check: `${icon.src} serves an image`, status: response.status});
  }
  console.log(JSON.stringify({checkedAt: new Date().toISOString(), site, passed: results.length, results}, null, 2));
})().catch(error => {console.error(error.message); process.exitCode = 1;});
