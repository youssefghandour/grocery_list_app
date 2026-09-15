const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const crypto = require('node:crypto');

const paymentEnv = {
  PAYMOB_ENABLED: 'true', PAYMOB_MODE: 'test',
  PAYMOB_SECRET_KEY: 'sk_test_local_only', PAYMOB_PUBLIC_KEY: 'pk_test_local_only',
  PAYMOB_HMAC_SECRET: 'local-hmac-test-secret', PAYMOB_INTEGRATION_IDS: '456',
};

// Execute the actual function handlers with in-memory admin and network adapters.
// No Firebase admin credentials, payment requests or push messages leave this process.
function harness({members = [], productStatus = 1, env = paymentEnv} = {}) {
  const writes = [], messages = [], requests = [];
  const documents = new Map([
    ['households/family', {name: 'QA Family'}],
    ['users/sender', {displayName: 'QA Sender'}],
    ['users/owner', {displayName: 'QA Owner', isPro: false, isGold: false}],
  ]);
  const write = (key, data) => {
    writes.push({key, data}); documents.set(key, {...documents.get(key), ...data});
  };
  const ref = (key) => ({
    key,
    get: async () => ({exists: documents.has(key), data: () => documents.get(key)}),
    update: async (data) => write(key, data),
    create: async data => {assert.equal(documents.has(key), false); write(key, data);},
  });
  const firestore = () => ({runTransaction: async action => {
    const pending = [];
    const result = await action({get: r => r.get(),
      update: (r, data) => pending.push([r.key, data]),
      create: (r, data) => {assert.equal(documents.has(r.key), false); pending.push([r.key, data]);}});
    pending.forEach(([key, data]) => write(key, data));
    return result;
  }, collection: (collection) => ({
    doc: (id) => ref(`${collection}/${id}`),
    where: (field, op, value) => ({get: async () => ({
      forEach: (fn) => members.filter(m => m[field] === value).forEach(m => fn({id: m.id, data: () => m})),
    })}),
  })});
  firestore.FieldValue = {serverTimestamp: () => 'local-timestamp'};
  class HttpsError extends Error { constructor(code, message) {super(message); this.code = code;} }
  const passthrough = (...args) => {
    const handler = args.at(-1);
    handler.deploymentOptions = args.length > 1 ? args[0] : {};
    return handler;
  };
  const deps = {
    './households': {joinHousehold() {throw new Error('Use the household emulator suite');}},
    'firebase-functions/v2/https': {onCall: passthrough, onRequest: passthrough, HttpsError},
    'firebase-functions/v2/firestore': {onDocumentCreated: passthrough},
    'firebase-admin': {initializeApp() {}, firestore,
      messaging: () => ({sendEachForMulticast: async message => {messages.push(message); return {successCount: message.tokens.length};}})},
    axios: {
      get: async (...args) => {requests.push({method: 'get', args}); return {data: {
        status: productStatus, product: {product_name: 'QA Milk', brands: 'QA Brand', categories_tags: ['en:dairies']}, products: [],
      }};},
      post: async (...args) => {requests.push({method: 'post', args}); return {data: {intention_order_id: 123, client_secret: 'local-secret'}};},
    },
    './payments': {createPaymentHandlers: args => require('../functions/payments').createPaymentHandlers({...args, env})},
  };
  const context = {exports: {}, console: {log() {}, error() {}},
    require: name => {assert.ok(Object.hasOwn(deps, name), `Unexpected dependency: ${name}`); return deps[name];}};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../functions/index.js'), 'utf8'), context);
  return {api: context.exports, writes, messages, requests, documents,
    event: (name = 'Milk') => ({params: {householdId: 'family', listId: 'main', itemId: 'item'},
      data: {data: () => ({name, addedBy: 'sender'}), ref: ref('items/item')}})};
}
function response() {
  return {code: 200, body: '', status(code) {this.code = code; return this;}, send(body) {this.body = body; return this;}};
}
test('Notification: missing document event is ignored', async () => {
  const h = harness(); await h.api.onGroceryItemCreated({}); assert.equal(h.messages.length, 0);
});
test('Notification: only other opted-in household members receive messages', async () => {
  const h = harness({members: [
    {id: 'sender', householdId: 'family', fcmToken: 'sender-token'},
    {id: 'enabled', householdId: 'family', fcmToken: 'enabled-token'},
    {id: 'disabled', householdId: 'family', fcmToken: 'disabled-token', notificationsEnabled: false},
    {id: 'no-token', householdId: 'family'},
    {id: 'outsider', householdId: 'other', fcmToken: 'outsider-token'},
  ]});
  await h.api.onGroceryItemCreated(h.event());
  assert.equal(h.messages.length, 1);
  assert.deepEqual(Array.from(h.messages[0].tokens), ['enabled-token']);
  assert.match(h.messages[0].notification.body, /QA Sender added "Milk"/);
});
test('Notification: no recipients means no push request', async () => {
  const h = harness(); await h.api.onGroceryItemCreated(h.event()); assert.equal(h.messages.length, 0);
});
test('Deal search: missing query is rejected', async () => {
  const h = harness(); await assert.rejects(h.api.searchProductDeals({data: {}}), e => e.code === 'invalid-argument');
});
test('Webhook: missing transaction object is rejected', async () => {
  const h = harness(), res = response(); await h.api.paymobWebhook({method: 'POST', body: {}}, res); assert.equal(res.code, 400);
});
test('Webhook: failed payment does not upgrade account', async () => {
  const h = harness(), res = response();
  await h.api.paymobWebhook({body: {obj: {success: false}}}, res); assert.equal(h.writes.length, 0);
});
test('Paymob order: missing required fields are rejected', async () => {
  const h = harness(); await assert.rejects(h.api.createPaymobOrder({auth: {uid: 'owner'}, data: {}}), e => e.code === 'invalid-argument');
});
test('PAY-01 Unsigned successful webhook cannot grant Gold', async () => {
  const h = harness(), res = response();
  await h.api.paymobWebhook({method: 'POST', headers: {}, query: {}, body: {obj: {
    success: true, payment_intent: {extras: {userId: 'victim', plan: 'gold'}},
  }}}, res);
  assert.equal(h.writes.length, 0, 'Unsigned webhook granted a paid entitlement');
});
test('PAY-02 Unauthenticated caller cannot create a payment order', async () => {
  const h = harness();
  await assert.rejects(h.api.createPaymobOrder({data: {planType: 'gold', userId: 'victim'}, auth: null}), e => e.code === 'unauthenticated');
});
test('PAY-03 Order identity must match authenticated user', async () => {
  const h = harness();
  await assert.rejects(h.api.createPaymobOrder({data: {planType: 'gold', userId: 'victim'}, auth: {uid: 'attacker'}}), e => ['permission-denied', 'invalid-argument'].includes(e.code));
});
test('PAY-04 Unknown paid plan is rejected', async () => {
  const h = harness();
  await assert.rejects(h.api.createPaymobOrder({data: {planType: 'unknown', userId: 'owner'}, auth: {uid: 'owner'}}), e => e.code === 'invalid-argument');
});
test('BAR-01 Barcode lookup accepts successful numeric API status', async () => {
  const h = harness({productStatus: 1});
  await h.api.onGroceryItemCreated(h.event('3017620422003'));
  assert.equal(h.writes.length, 1, 'A successful product response was ignored');
  assert.match(h.writes[0].data.name, /QA Milk/);
});

const checkout = (planType = 'gold') => ({
  auth: {uid: 'owner', token: {email: 'owner@example.test'}},
  data: {planType, userId: 'owner', userEmail: 'forged@example.test'},
});
const sale = (changes = {}) => ({
  amount_cents: 15000, created_at: '2026-09-14T00:00:00', currency: 'EGP',
  error_occured: false, has_parent_transaction: false, id: 789,
  integration_id: 456, is_3d_secure: true, is_auth: false, is_capture: false,
  is_refunded: false, is_standalone_payment: true, is_voided: false,
  order: {id: 123}, owner: 42, pending: false,
  source_data: {pan: '2346', sub_type: 'MasterCard', type: 'card'}, success: true,
  ...changes,
});
// Independent fixture follows Paymob's documented 20-field signature order.
function signedRequest(obj) {
  const fields = [obj.amount_cents, obj.created_at, obj.currency, obj.error_occured,
    obj.has_parent_transaction, obj.id, obj.integration_id, obj.is_3d_secure,
    obj.is_auth, obj.is_capture, obj.is_refunded, obj.is_standalone_payment,
    obj.is_voided, obj.order.id, obj.owner, obj.pending, obj.source_data.pan,
    obj.source_data.sub_type, obj.source_data.type, obj.success];
  const hmac = crypto.createHmac('sha512', paymentEnv.PAYMOB_HMAC_SECRET).update(fields.map(String).join('')).digest('hex');
  return {method: 'POST', query: {hmac}, body: {type: 'TRANSACTION', obj}};
}

test('Payment order uses server price and authenticated email and stores its owner', async () => {
  const h = harness();
  const result = await h.api.createPaymobOrder(checkout());
  assert.equal(result.clientSecret, 'local-secret');
  assert.equal(h.requests[0].args[0], 'https://accept.paymob.com/v1/intention/');
  assert.equal(h.requests[0].args[1].amount, 15000);
  assert.equal(h.requests[0].args[1].billing_data.email, 'owner@example.test');
  assert.deepEqual(h.documents.get('paymentOrders/123').integrationIds, [456]);
  assert.equal(h.documents.get('paymentOrders/123').uid, 'owner');
});

test('Payments fail closed without configuration and cannot verify arbitrary store receipts', async () => {
  const h = harness({env: {}});
  const caps = await h.api.getPaymentCapabilities(checkout());
  assert.deepEqual(caps, {paymob: false, nativeStore: false});
  await assert.rejects(h.api.createPaymobOrder(checkout()), e => e.code === 'failed-precondition');
  await assert.rejects(h.api.verifyStorePurchase({...checkout(), data: {verificationData: 'forged-receipt'}}), e => e.code === 'failed-precondition');
  assert.equal(h.requests.length, 0); assert.equal(h.writes.length, 0);
});

test('Disabled payment endpoints deploy without merchant secrets and reject even signed sales', async () => {
  const h = harness({env: {...paymentEnv, PAYMOB_ENABLED: 'false'}});
  assert.deepEqual(h.api.getPaymentCapabilities.deploymentOptions.secrets, []);
  assert.deepEqual(h.api.createPaymobOrder.deploymentOptions.secrets, []);
  assert.deepEqual(h.api.paymobWebhook.deploymentOptions.secrets, []);
  assert.deepEqual(await h.api.getPaymentCapabilities(checkout()), {paymob: false, nativeStore: false});
  const res = response();
  await h.api.paymobWebhook(signedRequest(sale()), res);
  assert.equal(res.code, 503);
  assert.equal(h.writes.length, 0);
});

test('Enabling Paymob binds the real merchant secrets in the deployment manifest', () => {
  const h = harness();
  assert.deepEqual(h.api.getPaymentCapabilities.deploymentOptions.secrets, ['PAYMOB_SECRET_KEY', 'PAYMOB_HMAC_SECRET']);
  assert.deepEqual(h.api.createPaymobOrder.deploymentOptions.secrets, ['PAYMOB_SECRET_KEY', 'PAYMOB_HMAC_SECRET']);
  assert.deepEqual(h.api.paymobWebhook.deploymentOptions.secrets, ['PAYMOB_HMAC_SECRET']);
});

test('Signed successful payment grants only the server-bound user; duplicate delivery is idempotent', async () => {
  const h = harness(); await h.api.createPaymobOrder(checkout()); h.writes.length = 0;
  const request = signedRequest(sale({payment_intent: {extras: {userId: 'victim', plan: 'pro'}}}));
  const res = response(); await h.api.paymobWebhook(request, res);
  assert.equal(res.code, 200);
  assert.equal(h.documents.get('users/owner').isGold, true);
  assert.equal(h.documents.has('users/victim'), false);
  assert.equal(h.documents.get('paymentOrders/123').status, 'paid');
  assert.equal(h.writes.length, 3);
  await h.api.paymobWebhook(request, response()); assert.equal(h.writes.length, 3);
});

test('A later Pro purchase does not remove an existing Gold entitlement', async () => {
  const h = harness(); h.documents.get('users/owner').isGold = true;
  await h.api.createPaymobOrder(checkout('pro'));
  await h.api.paymobWebhook(signedRequest(sale({amount_cents: 7500})), response());
  assert.equal(h.documents.get('users/owner').isGold, true);
});

for (const [label, changes] of [
  ['wrong amount', {amount_cents: 7500}], ['wrong currency', {currency: 'USD'}],
  ['wrong integration', {integration_id: 999}], ['unknown order', {order: {id: 999}}],
]) {
  test(`A valid signature with ${label} is rejected without any writes`, async () => {
    const h = harness(); await h.api.createPaymobOrder(checkout()); h.writes.length = 0;
    const res = response(); await h.api.paymobWebhook(signedRequest(sale(changes)), res);
    assert.equal(res.code, 403); assert.equal(h.writes.length, 0);
  });
}

test('Changing signed transaction data invalidates the signature', async () => {
  const h = harness(); await h.api.createPaymobOrder(checkout()); h.writes.length = 0;
  const request = signedRequest(sale()); request.body.obj.amount_cents = 7500;
  const res = response(); await h.api.paymobWebhook(request, res);
  assert.equal(res.code, 401); assert.equal(h.writes.length, 0);
});

test('A processed transaction cannot be moved to another user or order', async () => {
  const h = harness(); await h.api.createPaymobOrder(checkout());
  await h.api.paymobWebhook(signedRequest(sale()), response());
  h.documents.set('paymentOrders/124', {...h.documents.get('paymentOrders/123'), uid: 'victim', status: 'pending'});
  h.writes.length = 0;
  const res = response(); await h.api.paymobWebhook(signedRequest(sale({order: {id: 124}})), res);
  assert.equal(res.code, 403); assert.equal(h.writes.length, 0);
});

for (const [flag, value] of [['success', false], ['pending', true], ['is_refunded', true],
  ['is_voided', true], ['is_auth', true], ['is_standalone_payment', false], ['error_occured', true]]) {
  test(`Signed callback with ${flag}=${value} never grants an entitlement`, async () => {
    const h = harness(); await h.api.createPaymobOrder(checkout()); h.writes.length = 0;
    await h.api.paymobWebhook(signedRequest(sale({[flag]: value})), response());
    assert.equal(h.writes.length, 0);
  });
}
