const {test} = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {createPaymentHandlers} = require('../functions/payments');
const {PACKAGE_NAME, PRODUCTS} = require('../functions/google_play');
const pro = 'na2slna_pro_lifetime', gold = 'na2slna_gold_lifetime';
const hashed = value => crypto.createHash('sha256').update(value).digest('hex');
const request = (productId = gold, uid = 'buyer', verificationData = 'isolated-purchase-token') => ({
  auth: {uid}, data: {source: 'google_play', productId, verificationData},
});
const purchased = (productId = gold, extra = {}) => ({
  productLineItem: [{productId, productOfferDetails: {
    quantity: 1, refundableQuantity: 1, consumptionState: 'CONSUMPTION_STATE_YET_TO_BE_CONSUMED',
  }}],
  purchaseStateContext: {purchaseState: 'PURCHASED'},
  acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
  obfuscatedExternalAccountId: hashed('buyer'), orderId: 'QA-order', ...extra,
});

// Both network and database are isolated. The actual payment callable, verifier,
// Google REST request paths, and transaction logic execute unchanged.
function fixture({purchase = purchased(), getError, ackError, enabled = true} = {}) {
  const docs = new Map([['users/buyer', {isPro: false, isGold: false}], ['users/other', {isPro: false, isGold: false}]]);
  const calls = [], writes = [];
  let queue = Promise.resolve();
  const write = (key, data) => {writes.push({key, data}); docs.set(key, {...docs.get(key), ...data});};
  const ref = key => ({key,
    get: async () => ({exists: docs.has(key), data: () => structuredClone(docs.get(key))}),
    update: async data => {assert.ok(docs.has(key)); write(key, data);},
  });
  const db = {collection: name => ({doc: id => ref(`${name}/${id}`)}),
    runTransaction: action => {
      const result = queue.then(async () => {
        const pending = [];
        const result = await action({get: r => r.get(),
          update: (r, data) => {assert.ok(docs.has(r.key)); pending.push([r.key, data]);},
          create: (r, data) => {assert.ok(!docs.has(r.key)); pending.push([r.key, data]);},
        });
        for (const [key, data] of pending) write(key, data);
        return result;
      });
      queue = result.catch(() => {});
      return result;
    },
  };
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => 'QA-time'};
  class HttpsError extends Error {constructor(code, message) {super(message); this.code = code;}}
  const googlePlayClient = {request: async options => {
    calls.push(structuredClone(options));
    if (options.method === 'GET') {
      if (getError) throw getError;
      return {data: structuredClone(purchase)};
    }
    // Entitlements must already be durable when acknowledging a purchase.
    assert.ok([...docs.keys()].some(key => key.startsWith('storePurchases/')));
    if (ackError) throw ackError;
    purchase.acknowledgementState = 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED';
    return {data: {}};
  }};
  const onCall = (...args) => args.at(-1);
  const api = createPaymentHandlers({onCall, onRequest: onCall, HttpsError,
    admin: {firestore}, axios: {post() {throw new Error('No Paymob request allowed');}},
    env: {GOOGLE_PLAY_ENABLED: String(enabled)}, googlePlayClient,
  });
  return {api, docs, writes, calls, purchase,
    recoverAck: () => {ackError = undefined;},
    receipt: () => [...docs.entries()].find(([key]) => key.startsWith('storePurchases/')),
  };
}

for (const productId of Object.keys(PRODUCTS)) {
  test(`Google Play: verified ${productId} grants the correct plan and acknowledges on server`, async () => {
    const f = fixture({purchase: purchased(productId)});
    assert.deepEqual(await f.api.verifyStorePurchase(request(productId)), {verified: true, acknowledged: true});
    assert.equal(f.docs.get('users/buyer').isPro, true);
    assert.equal(f.docs.get('users/buyer').isGold, productId === gold);
    assert.equal(f.receipt()[1].acknowledged, true);
    assert.match(f.calls[0].url, new RegExp(`/applications/${PACKAGE_NAME}/purchases/productsv2/tokens/`));
    assert.match(f.calls[1].url, new RegExp(`/purchases/products/${productId}/tokens/.*:acknowledge$`));
    assert.equal(JSON.stringify(f.receipt()).includes('isolated-purchase-token'), false);
  });
}
test('Google Play: capability enables Android while Apple remains unavailable', async () => {
  const f = fixture();
  assert.equal((await f.api.getPaymentCapabilities(request())).nativeStore, true);
  assert.equal((await f.api.getPaymentCapabilities({auth: {uid: 'buyer'}})).nativeStore, true);
  assert.equal((await f.api.getPaymentCapabilities({auth: {uid: 'buyer'}, data: null})).nativeStore, true);
  assert.equal((await f.api.getPaymentCapabilities({auth: {uid: 'buyer'}, data: {source: 'app_store'}})).nativeStore, false);
  assert.equal((await fixture({enabled: false}).api.getPaymentCapabilities(request())).nativeStore, false);
});
for (const [label, edit, code] of [
  ['unauthenticated', r => {r.auth = null;}, 'unauthenticated'],
  ['wrong user', r => {r.data.userId = 'other';}, 'permission-denied'],
  ['empty data', r => {r.data = {};}, 'failed-precondition'],
  ['Apple source', r => {r.data.source = 'app_store';}, 'failed-precondition'],
  ['missing token', r => {delete r.data.verificationData;}, 'invalid-argument'],
  ['non-string token', r => {r.data.verificationData = {};}, 'invalid-argument'],
  ['oversize token', r => {r.data.verificationData = 'x'.repeat(8193);}, 'invalid-argument'],
  ['unknown product', r => {r.data.productId = 'fake_gold';}, 'invalid-argument'],
  ['prototype product', r => {r.data.productId = '__proto__';}, 'invalid-argument'],
]) test(`Google Play: ${label} is rejected before any Google or database operation`, async () => {
  const f = fixture(), r = request(); edit(r);
  await assert.rejects(f.api.verifyStorePurchase(r), e => e.code === code);
  assert.equal(f.calls.length, 0); assert.equal(f.writes.length, 0);
});
for (const state of ['PENDING', 'CANCELLED', 'PURCHASE_STATE_UNSPECIFIED']) {
  test(`Google Play: ${state} cannot grant a plan or acknowledge`, async () => {
    const f = fixture({purchase: purchased(gold, {purchaseStateContext: {purchaseState: state}})});
    await assert.rejects(f.api.verifyStorePurchase(request()), e => e.code === 'failed-precondition');
    assert.equal(f.calls.length, 1); assert.equal(f.writes.length, 0);
  });
}
for (const [label, modify] of [
  ['different product', p => {p.productLineItem[0].productId = pro;}],
  ['another account', p => {p.obfuscatedExternalAccountId = hashed('other');}],
  ['consumed product', p => {p.productLineItem[0].productOfferDetails.consumptionState = 'CONSUMPTION_STATE_CONSUMED';}],
  ['full refund', p => {p.productLineItem[0].productOfferDetails.refundableQuantity = 0;}],
  ['rental', p => {p.productLineItem[0].productOfferDetails.rentOfferDetails = {};}],
  ['missing state', p => {delete p.purchaseStateContext;}],
  ['missing acknowledgement state', p => {delete p.acknowledgementState;}],
]) test(`Google Play: ${label} cannot grant access`, async () => {
  const purchase = purchased(); modify(purchase); const f = fixture({purchase});
  await assert.rejects(f.api.verifyStorePurchase(request()));
  assert.equal(f.writes.length, 0); assert.equal(f.calls.length, 1);
});
for (const [status, code] of [[400, 'invalid-argument'], [404, 'invalid-argument'], [410, 'invalid-argument'],
  [401, 'failed-precondition'], [403, 'failed-precondition'], [429, 'unavailable'], [503, 'unavailable']]) {
  test(`Google Play: provider HTTP ${status} grants nothing and returns ${code}`, async () => {
    const f = fixture({getError: {response: {status}}});
    await assert.rejects(f.api.verifyStorePurchase(request()), e => e.code === code);
    assert.equal(f.writes.length, 0);
  });
}
test('Google Play: repeat restore rechecks Google and keeps one receipt', async () => {
  const f = fixture();
  await f.api.verifyStorePurchase(request()); await f.api.verifyStorePurchase(request());
  assert.equal(f.calls.filter(c => c.method === 'GET').length, 2);
  assert.equal(f.calls.filter(c => c.method === 'POST').length, 1);
  assert.equal([...f.docs.keys()].filter(k => k.startsWith('storePurchases/')).length, 1);
});
test('Google Play: a previously recorded token is not trusted after cancellation', async () => {
  const f = fixture(); await f.api.verifyStorePurchase(request());
  f.purchase.purchaseStateContext.purchaseState = 'CANCELLED';
  f.writes.length = 0;
  await assert.rejects(f.api.verifyStorePurchase(request()), e => e.code === 'failed-precondition');
  assert.equal(f.writes.length, 0);
});
test('Google Play: Pro restore preserves existing Gold from either payment provider', async () => {
  const f = fixture({purchase: purchased(pro)}); f.docs.get('users/buyer').isGold = true;
  await f.api.verifyStorePurchase(request(pro));
  assert.equal(f.docs.get('users/buyer').isGold, true);
});
test('Google Play: legacy raw UID and already acknowledged purchases restore correctly', async () => {
  const f = fixture({purchase: purchased(gold, {obfuscatedExternalAccountId: 'buyer',
    acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'})});
  await f.api.verifyStorePurchase(request()); assert.equal(f.calls.length, 1);
});
test('Google Play: legacy token without account binding cannot be claimed by two accounts', async () => {
  const f = fixture({purchase: purchased(gold, {obfuscatedExternalAccountId: undefined})});
  const results = await Promise.allSettled([f.api.verifyStorePurchase(request()), f.api.verifyStorePurchase(request(gold, 'other'))]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.find(r => r.status === 'rejected').reason.code, 'permission-denied');
  assert.equal([...f.docs.values()].filter(d => d.isGold === true).length, 1);
});
test('Google Play: temporary acknowledgement failure can safely resume on restore', async () => {
  const f = fixture({ackError: {response: {status: 503}}});
  await assert.rejects(f.api.verifyStorePurchase(request()), e => e.code === 'unavailable');
  assert.equal(f.receipt()[1].acknowledged, false);
  f.recoverAck();
  assert.deepEqual(await f.api.verifyStorePurchase(request()), {verified: true, acknowledged: true});
  assert.equal(f.receipt()[1].acknowledged, true);
});
test('Google Play: a missing profile is not acknowledged or given an orphan receipt', async () => {
  const f = fixture(); f.docs.delete('users/buyer');
  await assert.rejects(f.api.verifyStorePurchase(request()), e => e.code === 'failed-precondition');
  assert.equal(f.writes.length, 0); assert.equal(f.calls.length, 1);
});
test('Google Play: test-card purchase without orderId is verified normally', async () => {
  const f = fixture({purchase: purchased(gold, {orderId: undefined, testPurchaseContext: {fopType: 'TEST'}})});
  await f.api.verifyStorePurchase(request());
  assert.equal(f.receipt()[1].testPurchase, true); assert.equal(f.receipt()[1].orderId, null);
});
