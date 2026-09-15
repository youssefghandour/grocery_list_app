const {after, test} = require('node:test');
const assert = require('node:assert/strict');
const {randomInt, randomUUID} = require('node:crypto');

// The real callable and real Admin SDK only connect to this isolated emulator.
const emulatorHost = '127.0.0.1:8080';
if (process.env.FIRESTORE_EMULATOR_HOST &&
    process.env.FIRESTORE_EMULATOR_HOST !== emulatorHost) {
  throw new Error('Household QA refuses a non-local Firestore host.');
}
process.env.FIRESTORE_EMULATOR_HOST = emulatorHost;
const admin = require('../functions/node_modules/firebase-admin');
const app = admin.initializeApp({projectId: 'demo-na2slna-qa'});
const db = admin.firestore();
const {joinHousehold} = require('../functions/households');
const fixtures = [];

async function fixture({count = 1, gold = false, age = 60_000} = {}) {
  const prefix = `qa-join-${randomUUID()}`;
  const householdId = `${prefix}-household`;
  const ownerId = `${prefix}-owner`;
  const callerId = `${prefix}-caller`;
  const inviteCode = `J${randomInt(36 ** 5).toString(36).padStart(5, '0')}`.toUpperCase();
  const refs = [];
  const batch = db.batch();
  function set(collection, id, data) {
    const ref = db.collection(collection).doc(id);
    refs.push(ref);
    batch.create(ref, data);
  }
  set('households', householdId, {
    name: 'Isolated QA household', createdBy: ownerId, inviteCode,
    createdAt: admin.firestore.Timestamp.now(),
  });
  set('inviteCodes', inviteCode, {
    householdId, createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - age),
  });
  set('users', ownerId, {
    displayName: 'QA Owner', householdId, role: 'familyAdmin', isGold: gold,
  });
  set('users', callerId, {displayName: 'QA Caller', role: 'familyMember'});
  for (let i = 1; i < count; i++) {
    set('users', `${prefix}-member-${i}`, {
      displayName: 'QA Member', householdId, role: 'familyMember',
    });
  }
  await batch.commit();
  fixtures.push(refs);
  return {householdId, ownerId, callerId, inviteCode, refs};
}

function join(f, {uid = f.callerId, data = {}} = {}) {
  return joinHousehold.run({auth: {uid}, data: {inviteCode: f.inviteCode, ...data}});
}

async function rejectsJoin(f, code, reason, options) {
  await assert.rejects(join(f, options), error => {
    assert.equal(error.code, code);
    assert.equal(error.details.reason, reason);
    return true;
  });
}

after(async () => {
  for (const refs of fixtures) {
    const batch = db.batch();
    for (const ref of refs) batch.delete(ref);
    await batch.commit();
  }
  await db.terminate();
  await app.delete();
});

test('Join: lowercase and padded invitation joins the authenticated profile', async () => {
  const f = await fixture();
  const result = await join(f, {data: {inviteCode: `  ${f.inviteCode.toLowerCase()}  `}});
  assert.deepEqual(result, {householdId: f.householdId});
  const user = (await db.doc(`users/${f.callerId}`).get()).data();
  assert.equal(user.householdId, f.householdId);
  assert.equal(user.role, 'familyMember');
});

test('Join: non-existent invitation is rejected', async () => {
  const f = await fixture();
  await db.doc(`inviteCodes/${f.inviteCode}`).delete();
  await rejectsJoin(f, 'not-found', 'invite-not-found');
});

test('Join: deleted household is rejected', async () => {
  const f = await fixture();
  await db.doc(`households/${f.householdId}`).delete();
  await rejectsJoin(f, 'not-found', 'household-not-found');
});

test('Join: a replaced invitation is rejected even if its old record remains', async () => {
  const f = await fixture();
  await db.doc(`households/${f.householdId}`).update({inviteCode: 'ABC234'});
  await rejectsJoin(f, 'not-found', 'invite-not-found');
  assert.equal((await db.doc(`users/${f.callerId}`).get()).data().householdId, undefined);
});

test('Join: six-character alphanumeric input is required', async () => {
  const f = await fixture();
  for (const inviteCode of [null, 123456, '', 'TOOLONG', 'ABC/12', 'AB CD1']) {
    await rejectsJoin(f, 'invalid-argument', 'invalid-invite-code', {data: {inviteCode}});
  }
});

test('QA-15 Invitations older than 48 hours are rejected', async () => {
  const f = await fixture({age: 49 * 60 * 60 * 1000});
  await rejectsJoin(f, 'failed-precondition', 'invite-expired');
});

test('Join: recent invitations within the 48-hour lifetime work', async () => {
  const f = await fixture({age: 47 * 60 * 60 * 1000});
  assert.deepEqual(await join(f), {householdId: f.householdId});
});

test('Join: future or malformed invitation timestamps are rejected', async () => {
  const f = await fixture({age: -60_000});
  await rejectsJoin(f, 'failed-precondition', 'invite-expired');
  await db.doc(`inviteCodes/${f.inviteCode}`).update({createdAt: 'yesterday'});
  await rejectsJoin(f, 'failed-precondition', 'invite-expired');
});

test('Join: a sixth member cannot join a free household', async () => {
  const f = await fixture({count: 5});
  await rejectsJoin(f, 'resource-exhausted', 'limit-reached');
  assert.equal((await db.doc(`users/${f.callerId}`).get()).data().householdId, undefined);
});

test('Join: a Gold household can admit a seventh member', async () => {
  const f = await fixture({count: 6, gold: true});
  assert.deepEqual(await join(f), {householdId: f.householdId});
  const members = await db.collection('users').where('householdId', '==', f.householdId).get();
  assert.equal(members.size, 7);
});

test('Join: a departed Gold owner does not bypass the free limit', async () => {
  const f = await fixture({count: 6, gold: true});
  await db.doc(`users/${f.ownerId}`).update({householdId: 'other-household'});
  await rejectsJoin(f, 'resource-exhausted', 'limit-reached');
});

test('Join: unauthenticated callers are rejected', async () => {
  const f = await fixture();
  await assert.rejects(joinHousehold.run({data: {inviteCode: f.inviteCode}}),
      error => error.code === 'unauthenticated');
});

test('Join: a claimed userId cannot change another account', async () => {
  const f = await fixture();
  await join(f, {data: {userId: f.ownerId, role: 'familyAdmin'}});
  const owner = (await db.doc(`users/${f.ownerId}`).get()).data();
  const caller = (await db.doc(`users/${f.callerId}`).get()).data();
  assert.equal(owner.role, 'familyAdmin');
  assert.equal(caller.householdId, f.householdId);
  assert.equal(caller.role, 'familyMember');
});

test('Join: a caller without a profile is rejected', async () => {
  const f = await fixture();
  await db.doc(`users/${f.callerId}`).delete();
  await rejectsJoin(f, 'failed-precondition', 'user-not-found');
});

test('QA-02 Reopening your own invitation preserves administrator role', async () => {
  const f = await fixture({count: 5});
  assert.deepEqual(await join(f, {uid: f.ownerId}), {householdId: f.householdId});
  assert.equal((await db.doc(`users/${f.ownerId}`).get()).data().role, 'familyAdmin');
});

test('Join: the owner can recover an accidentally demoted administrator role', async () => {
  const f = await fixture({count: 5});
  await db.doc(`users/${f.ownerId}`).update({role: 'familyMember'});
  await join(f, {uid: f.ownerId});
  assert.equal((await db.doc(`users/${f.ownerId}`).get()).data().role, 'familyAdmin');
});

test('Join: a member can reopen the invite of a full household', async () => {
  const f = await fixture({count: 4});
  await join(f);
  assert.deepEqual(await join(f), {householdId: f.householdId});
  assert.equal((await db.doc(`users/${f.callerId}`).get()).data().role, 'familyMember');
});

test('Join: concurrent fifth and sixth joins admit only one caller', async () => {
  const f = await fixture({count: 4});
  const otherId = `${f.callerId}-concurrent`;
  const otherRef = db.doc(`users/${otherId}`);
  f.refs.push(otherRef);
  await otherRef.set({displayName: 'Concurrent QA caller', role: 'familyMember'});
  const results = await Promise.allSettled([join(f), join(f, {uid: otherId})]);
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  const rejected = results.find(result => result.status === 'rejected');
  assert.equal(rejected.reason.details.reason, 'limit-reached');
  const members = await db.collection('users').where('householdId', '==', f.householdId).get();
  assert.equal(members.size, 5);
});
