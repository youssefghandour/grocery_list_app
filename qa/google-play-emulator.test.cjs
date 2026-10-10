const {after, test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID, createHash} = require('node:crypto');
if (process.env.FIRESTORE_EMULATOR_HOST && process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080') {
  throw new Error('Google Play tests refuse a non-local Firestore host.');
}
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
const admin = require('../functions/node_modules/firebase-admin');
const functionsRequire = require('node:module').createRequire(require('node:path').resolve(__dirname, '../functions/package.json'));
const {HttpsError} = functionsRequire('firebase-functions/v2/https');
const {createGooglePlayVerifier} = require('../functions/google_play');
const app = admin.initializeApp({projectId: 'demo-na2slna-qa'}, 'play-qa');
const db = app.firestore();
const refs = [];
const firestore = () => db;
firestore.FieldValue = admin.firestore.FieldValue;
const gold = 'na2slna_gold_lifetime', pro = 'na2slna_pro_lifetime';

async function fixture() {
  const uid = `play-${randomUUID()}`, other = `play-${randomUUID()}`, token = randomUUID();
  const user = db.collection('users').doc(uid), otherUser = db.collection('users').doc(other);
  refs.push(user, otherUser);
  await user.create({isGold: false, isPro: false}); await otherUser.create({isGold: false, isPro: false});
  const purchase = {purchaseStateContext: {purchaseState: 'PURCHASED'},
    acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED', productLineItem: [{productId: gold}]};
  const verifier = createGooglePlayVerifier({admin: {firestore}, HttpsError,
    client: {request: async () => ({data: structuredClone(purchase)})},
  });
  const receipt = db.collection('storePurchases').doc(createHash('sha256')
      .update(`google_play:com.ghandour.na2slna:${token}`).digest('hex'));
  refs.push(receipt);
  return {user, otherUser, receipt, purchase,
    verify: (who = uid, productId = gold) => verifier({auth: {uid: who},
      data: {source: 'google_play', productId, verificationData: token}}), uid, other};
}

after(async () => {
  const batch = db.batch(); for (const ref of refs) batch.delete(ref);
  await batch.commit(); await db.terminate(); await app.delete();
});

test('Emulator: concurrent claims of one legacy purchase grant exactly one account', async () => {
  const f = await fixture();
  const results = await Promise.allSettled([f.verify(), f.verify(f.other)]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.find(r => r.status === 'rejected').reason.code, 'permission-denied');
  const users = await Promise.all([f.user.get(), f.otherUser.get()]);
  assert.equal(users.filter(u => u.data().isGold).length, 1);
  assert.equal((await f.receipt.get()).data().uid, users.find(u => u.data().isGold).id);
});
test('Emulator: simultaneous duplicate restores succeed with one durable ownership record', async () => {
  const f = await fixture();
  const results = await Promise.all([f.verify(), f.verify(), f.verify()]);
  assert.ok(results.every(r => r.verified && r.acknowledged));
  assert.equal((await f.receipt.get()).data().uid, f.uid);
  assert.equal((await f.user.get()).data().isGold, true);
});
test('Emulator: Pro restore preserves Gold and private receipt cannot move accounts', async () => {
  const f = await fixture(); await f.user.update({isGold: true});
  f.purchase.productLineItem[0].productId = pro;
  await f.verify(f.uid, pro);
  assert.equal((await f.user.get()).data().isGold, true);
  await assert.rejects(f.verify(f.other, pro), e => e.code === 'permission-denied');
  assert.equal((await f.otherUser.get()).data().isPro, false);
});
test('Emulator: incomplete Google payment makes no entitlement or receipt writes', async () => {
  const f = await fixture(); f.purchase.purchaseStateContext.purchaseState = 'PENDING';
  await assert.rejects(f.verify(), e => e.code === 'failed-precondition');
  assert.equal((await f.receipt.get()).exists, false);
  assert.equal((await f.user.get()).data().isPro, false);
});
