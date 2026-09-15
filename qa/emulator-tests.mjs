import assert from 'node:assert/strict';
import {before, test} from 'node:test';
import {randomInt} from 'node:crypto';

// No production hosts, credentials, projects or accounts are accepted here.
const project = 'demo-na2slna-qa';
const authBase = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/';
const dbBase = `http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents/`;
const run = Date.now().toString();
const household = `qa-family-${run}`;
const password = 'LocalQaPassword123!';
let owner, member, stranger;
// Emulator-only privileged seeding; subsequent test actions use actual Auth tokens.
const seedAdmin = {idToken: 'owner'};
const stamp = new Date();

async function auth(action, body) {
  const response = await fetch(`${authBase}accounts:${action}?key=${project}`, {
    method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify(body),
  });
  return {status: response.status, data: await response.json()};
}
function fields(value) {
  const encode = val => val === null ? {nullValue: null}
    : val instanceof Date ? {timestampValue: val.toISOString()}
    : Array.isArray(val) ? {arrayValue: {values: val.map(encode)}}
    : typeof val === 'boolean' ? {booleanValue: val}
    : typeof val === 'number' ? Number.isInteger(val) ? {integerValue: String(val)} : {doubleValue: val}
    : typeof val === 'object' ? {mapValue: {fields: fields(val)}} : {stringValue: val};
  return Object.fromEntries(Object.entries(value).map(([key, val]) => [key, encode(val)]));
}
async function db(method, path, user, data) {
  const response = await fetch(dbBase + path + (method === 'PATCH' ? '?' + Object.keys(data).map(key => 'updateMask.fieldPaths=' + encodeURIComponent(key)).join('&') : ''), {method,
    headers: {'content-type': 'application/json', ...(user ? {authorization: `Bearer ${user.idToken}`} : {})},
    ...(data ? {body: JSON.stringify({fields: fields(data)})} : {}),
  });
  return {status: response.status, data: await response.json()};
}
before(async () => {
  for (const role of ['owner', 'member', 'stranger']) {
    const result = await auth('signUp', {email: `${role}-${run}@example.test`, password, returnSecureToken: true});
    assert.equal(result.status, 200, 'Local account setup failed');
    if (role === 'owner') owner = result.data;
    if (role === 'member') member = result.data;
    if (role === 'stranger') stranger = result.data;
  }
  for (const [person, role, group] of [[owner, 'familyAdmin', household], [member, 'familyMember', household], [stranger, 'familyMember', 'different-family']]) {
    const result = await db('PATCH', `users/${person.localId}`, seedAdmin,
      {email: person.email, displayName: 'Local QA', role, householdId: group, isPro: false, isGold: false, createdAt: stamp});
    assert.equal(result.status, 200);
  }
  assert.equal((await db('PATCH', `households/${household}`, seedAdmin,
    {name: 'Local QA Family', createdBy: owner.localId, inviteCode: 'LOCAL1', createdAt: stamp})).status, 200);
  assert.equal((await db('PATCH', `inviteCodes/LOCAL1`, seedAdmin,
    {householdId: household, createdAt: stamp})).status, 200);
  assert.equal((await db('PATCH', `households/${household}/lists/main`, seedAdmin,
    {name: 'Main List', createdBy: owner.localId, isDefault: true, createdAt: stamp})).status, 200);
});

test('Emulator: email/password login succeeds', async () => {
  assert.equal((await auth('signInWithPassword', {email: owner.email, password, returnSecureToken: true})).status, 200);
});
test('Emulator: wrong password is rejected', async () => {
  assert.equal((await auth('signInWithPassword', {email: owner.email, password: 'Incorrect123!', returnSecureToken: true})).status, 400);
});
test('Emulator: duplicate email registration is rejected', async () => {
  const result = await auth('signUp', {email: owner.email, password, returnSecureToken: true});
  assert.equal(result.status, 400);
  assert.equal(result.data.error.message, 'EMAIL_EXISTS');
});
test('Emulator: password reset request stays inside local Auth emulator', async () => {
  assert.equal((await auth('sendOobCode', {requestType: 'PASSWORD_RESET', email: owner.email})).status, 200);
});
test('Rules: anonymous household read is denied', async () => {
  assert.equal((await db('GET', `households/${household}`)).status, 403);
});
test('Rules: owner can read own household', async () => {
  assert.equal((await db('GET', `households/${household}`, owner)).status, 200);
});
test('Rules: household member can add a shared grocery item', async () => {
  assert.equal((await db('PATCH', `households/${household}/lists/main/items/member-item`, member,
    {name: 'QA Milk', quantity: '1', householdId: household, addedBy: member.localId, isChecked: false, createdAt: stamp, updatedAt: stamp})).status, 200);
});
test('SEC-01 Rules deny reading another household', async () => {
  assert.equal((await db('GET', `households/${household}`, stranger)).status, 403);
});
test('SEC-02 Rules deny modifying another household', async () => {
  assert.equal((await db('PATCH', `households/${household}`, stranger, {name: 'Unauthorized rename'})).status, 403);
});
test('SEC-03 Rules deny changing another user membership', async () => {
  assert.equal((await db('PATCH', `users/${member.localId}`, stranger, {householdId: 'hijacked'})).status, 403);
});
test('SEC-04 Rules deny self-granting paid Gold entitlement', async () => {
  assert.equal((await db('PATCH', `users/${stranger.localId}`, stranger, {isPro: true, isGold: true})).status, 403);
});
test('SEC-05 Rules deny self-granting administrator role', async () => {
  assert.equal((await db('PATCH', `users/${stranger.localId}`, stranger, {role: 'familyAdmin'})).status, 403);
});
test('SEC-06 Rules reject malformed item types', async () => {
  assert.equal((await db('PATCH', `households/${household}/lists/main/items/bad-type`, member,
    {name: 123, quantity: false, isChecked: 'invalid'})).status, 403);
});
test('SEC-07 Rules deny deleting another family member item', async () => {
  assert.equal((await db('DELETE', `households/${household}/lists/main/items/member-item`, stranger)).status, 403);
});

const documentName = path => `projects/${project}/databases/(default)/documents/${path}`;
function write(path, data, {mask, timestamps = []} = {}) {
  return {update: {name: documentName(path), fields: fields(data)},
    ...(mask ? {updateMask: {fieldPaths: mask}} : {}),
    ...(timestamps.length ? {updateTransforms: timestamps.map(fieldPath => ({fieldPath, setToServerValue: 'REQUEST_TIME'}))} : {})};
}
async function commit(user, writes) {
  const response = await fetch(dbBase.slice(0, -1) + ':commit', {method: 'POST',
    headers: {'content-type': 'application/json', authorization: `Bearer ${user.idToken}`},
    body: JSON.stringify({writes})});
  return {status: response.status, data: await response.json()};
}
async function query(user, structuredQuery, parent = '') {
  const response = await fetch(dbBase.slice(0, -1) + (parent ? '/' + parent : '') + ':runQuery', {
    method: 'POST', headers: {'content-type': 'application/json', authorization: `Bearer ${user.idToken}`},
    body: JSON.stringify({structuredQuery})});
  return {status: response.status, data: await response.json()};
}
const householdFilter = id => ({fieldFilter: {field: {fieldPath: 'householdId'}, op: 'EQUAL', value: {stringValue: id}}});

test('Rules: member can edit a shared item and retain creator identity', async () => {
  assert.equal((await db('PATCH', `households/${household}/lists/main/items/member-item`, owner,
    {quantity: '2.5', price: 12.5, isChecked: true, imageUrl: 'https://example.test/photo.png', updatedAt: new Date()})).status, 200);
});
test('Rules: owner can rename their household', async () => {
  assert.equal((await db('PATCH', `households/${household}`, owner, {name: 'Renamed family'})).status, 200);
});
test('Rules: ordinary member cannot rename the household', async () => {
  assert.equal((await db('PATCH', `households/${household}`, member, {name: 'Unauthorized member rename'})).status, 403);
});
test('Rules: profile name and notification preference remain editable', async () => {
  assert.equal((await db('PATCH', `users/${member.localId}`, member,
    {displayName: 'New local name', notificationsEnabled: false, fcmToken: 'local-fcm', updatedAt: new Date()})).status, 200);
});
test('Rules: queries return only the member current household profiles', async () => {
  const result = await query(member, {from: [{collectionId: 'users'}], where: householdFilter(household)});
  assert.equal(result.status, 200, JSON.stringify(result.data));
  assert.ok(result.data.filter(row => row.document).length >= 2);
});
test('Rules: collection-group suggestions work with the household filter', async () => {
  const result = await query(member, {from: [{collectionId: 'items', allDescendants: true}], where: householdFilter(household), limit: 50});
  assert.equal(result.status, 200, JSON.stringify(result.data));
  assert.ok(result.data.some(row => row.document));
});
test('Rules: collection-group queries without household isolation are denied', async () => {
  assert.equal((await query(member, {from: [{collectionId: 'items', allDescendants: true}], limit: 50})).status, 403);
});
test('Rules: query for another household is denied', async () => {
  assert.equal((await query(stranger, {from: [{collectionId: 'items', allDescendants: true}], where: householdFilter(household)})).status, 403);
});
test('Rules: paid fields cannot be smuggled into a profile update', async () => {
  assert.equal((await db('PATCH', `users/${member.localId}`, member,
    {displayName: 'Looks harmless', isGold: true})).status, 403);
});
test('Rules: household owner cannot grant a member paid access', async () => {
  assert.equal((await db('PATCH', `users/${member.localId}`, owner, {isPro: true})).status, 403);
});
test('Rules: invitation codes cannot be enumerated by an unrelated account', async () => {
  assert.equal((await query(stranger, {from: [{collectionId: 'inviteCodes'}]})).status, 403);
});
test('Rules: an unrelated account cannot read another user profile', async () => {
  assert.equal((await db('GET', `users/${member.localId}`, stranger)).status, 403);
});
test('Rules: membership cannot be changed just by claiming a known household ID', async () => {
  assert.equal((await db('PATCH', `users/${stranger.localId}`, stranger,
    {householdId: household, role: 'familyMember'})).status, 403);
});
test('Rules: item creator and household scope are immutable', async () => {
  const path = `households/${household}/lists/main/items/member-item`;
  assert.equal((await db('PATCH', path, owner, {addedBy: owner.localId})).status, 403);
  assert.equal((await db('PATCH', path, member, {householdId: 'different-family'})).status, 403);
});
for (const [label, value] of [
  ['negative price', {price: -1}], ['NaN-style quantity', {quantity: 'NaN'}],
  ['zero quantity', {quantity: '0'}], ['oversize name', {name: 'a'.repeat(201)}],
  ['unexpected field', {adminOverride: true}],
]) {
  test(`Rules: item updates reject ${label}`, async () => {
    assert.equal((await db('PATCH', `households/${household}/lists/main/items/member-item`, member, value)).status, 403);
  });
}
test('Rules: a valid item cannot be written beneath another household', async () => {
  assert.equal((await db('PATCH', `households/foreign-family/lists/main/items/spoof`, member,
    {householdId: household, name: 'Spoof', quantity: '1', isChecked: false, addedBy: member.localId, createdAt: stamp, updatedAt: stamp})).status, 403);
});
for (const collection of ['paymentOrders', 'paymentTransactions']) {
  test(`Rules: ${collection} is private to the server`, async () => {
    await db('PATCH', `${collection}/qa-${run}`, seedAdmin, {uid: owner.localId});
    assert.equal((await db('GET', `${collection}/qa-${run}`, owner)).status, 403);
    assert.equal((await db('PATCH', `${collection}/qa-${run}`, owner, {status: 'paid'})).status, 403);
  });
}

test('Rules: new profile and atomic household/default-list/invitation creation work', async () => {
  const result = await auth('signUp', {email: `creator-${run}@example.test`, password, returnSecureToken: true});
  const creator = result.data;
  const profilePath = `users/${creator.localId}`;
  const profile = {email: creator.email, displayName: 'Creator', role: 'familyMember', createdAt: new Date(), isGold: false, isPro: false};
  assert.equal((await db('PATCH', profilePath, creator, {...profile, isGold: true})).status, 403);
  assert.equal((await db('PATCH', profilePath, creator, {...profile, role: 'familyAdmin'})).status, 403);
  assert.equal((await db('PATCH', profilePath, creator, profile)).status, 200);
  const newHousehold = `new-family-${run}`;
  const code = randomInt(36 ** 6).toString(36).padStart(6, '0').toUpperCase();
  let freshCode;
  do { freshCode = randomInt(36 ** 6).toString(36).padStart(6, '0').toUpperCase(); } while (freshCode === code);
  const created = await commit(creator, [
    write(`households/${newHousehold}`, {name: 'My own household', createdBy: creator.localId, inviteCode: code}, {timestamps: ['createdAt']}),
    write(`households/${newHousehold}/lists/main`, {name: 'Main List', createdBy: creator.localId, isDefault: true}, {timestamps: ['createdAt']}),
    write(`inviteCodes/${code}`, {householdId: newHousehold}, {timestamps: ['createdAt']}),
    write(profilePath, {householdId: newHousehold, role: 'familyAdmin'}, {mask: ['householdId', 'role'], timestamps: ['updatedAt']}),
  ]);
  assert.equal(created.status, 200, JSON.stringify(created.data));
  assert.equal((await db('GET', `households/${newHousehold}`, creator)).status, 200);
  const renewed = await commit(creator, [
    write(`inviteCodes/${freshCode}`, {householdId: newHousehold}, {timestamps: ['createdAt']}),
    write(`households/${newHousehold}`, {inviteCode: freshCode}, {mask: ['inviteCode'], timestamps: ['updatedAt']}),
    {delete: documentName(`inviteCodes/${code}`)},
  ]);
  assert.equal(renewed.status, 200, JSON.stringify(renewed.data));
});

test('Rules: members can leave and lose access, and owners can remove a member', async () => {
  const tempId = `temporary-${run}`;
  const temp = await auth('signUp', {email: `${tempId}@example.test`, password, returnSecureToken: true});
  const profilePath = `users/${temp.data.localId}`;
  await db('PATCH', profilePath, seedAdmin, {email: temp.data.email, displayName: 'Temporary', role: 'familyMember', createdAt: stamp, householdId: household});
  assert.equal((await commit(temp.data, [write(profilePath, {role: 'familyMember'}, {mask: ['householdId', 'role'], timestamps: ['updatedAt']})])).status, 200);
  assert.equal((await db('GET', `households/${household}`, temp.data)).status, 403);
  await db('PATCH', profilePath, seedAdmin, {householdId: household});
  assert.equal((await commit(owner, [write(profilePath, {role: 'familyMember'}, {mask: ['householdId', 'role'], timestamps: ['updatedAt']})])).status, 200);
  assert.equal((await db('GET', `households/${household}`, temp.data)).status, 403);
});

test('Rules: legacy descriptive quantities remain checkable and editable without being replaced', async () => {
  const path = `households/${household}/lists/main/items/legacy-label`;
  assert.equal((await db('PATCH', path, seedAdmin,
    {householdId: household, name: 'Legacy milk', quantity: '2 packs', isChecked: false,
      addedBy: member.localId, createdAt: stamp, updatedAt: stamp})).status, 200);
  assert.equal((await db('PATCH', path, member, {isChecked: true, updatedAt: new Date()})).status, 200);
  assert.equal((await db('PATCH', path, owner, {price: 12.5, quantity: '2 packs', updatedAt: new Date()})).status, 200);
  assert.equal((await db('GET', path, member)).data.fields.quantity.stringValue, '2 packs');
  assert.equal((await db('PATCH', path, member, {quantity: '3 packs'})).status, 403);
  assert.equal((await db('PATCH', path, member, {quantity: '2.5'})).status, 200);
  assert.equal((await db('PATCH', path, member, {quantity: '2 packs'})).status, 403);
});

test('Rules: legacy quantity allowance cannot create labels or preserve invalid types and oversized values', async () => {
  const base = {householdId: household, name: 'Quantity bounds', isChecked: false,
    addedBy: member.localId, createdAt: stamp, updatedAt: stamp};
  assert.equal((await db('PATCH', `households/${household}/lists/main/items/new-label`, member,
    {...base, quantity: '2 packs'})).status, 403);
  for (const [index, quantity] of [false, 2, '', ' ', 'p'.repeat(31)].entries()) {
    const path = `households/${household}/lists/main/items/legacy-bad-quantity-${index}`;
    assert.equal((await db('PATCH', path, seedAdmin, {...base, quantity})).status, 200);
    assert.equal((await db('PATCH', path, member, {isChecked: true})).status, 403);
  }
});

test('Rules: blank names cannot be created or replace valid profile names', async () => {
  const result = await auth('signUp', {email: `blank-create-${run}@example.test`, password, returnSecureToken: true});
  assert.equal(result.status, 200);
  const person = result.data;
  const path = `users/${person.localId}`;
  const profile = {email: person.email, role: 'familyMember', createdAt: stamp};
  for (const displayName of ['', '   ']) {
    assert.equal((await db('PATCH', path, person, {...profile, displayName})).status, 403);
  }
  assert.equal((await db('PATCH', path, person, {...profile, displayName: 'Valid name'})).status, 200);
  for (const displayName of ['', '   ']) {
    assert.equal((await db('PATCH', path, person, {displayName})).status, 403);
  }
});

test('Rules: unchanged blank legacy names allow settings, leaving and owner removal', async () => {
  const result = await auth('signUp', {email: `blank-legacy-${run}@example.test`, password, returnSecureToken: true});
  assert.equal(result.status, 200);
  const person = result.data;
  const path = `users/${person.localId}`;
  assert.equal((await db('PATCH', path, seedAdmin,
    {email: person.email, displayName: '', role: 'familyMember', createdAt: stamp, householdId: household})).status, 200);
  assert.equal((await db('PATCH', path, person, {notificationsEnabled: false, fcmToken: 'local-token'})).status, 200);
  assert.equal((await db('PATCH', path, person, {displayName: '  '})).status, 403);
  assert.equal((await commit(person, [write(path, {role: 'familyMember'},
    {mask: ['householdId', 'role'], timestamps: ['updatedAt']})])).status, 200);
  assert.equal((await db('GET', `households/${household}`, person)).status, 403);
  assert.equal((await db('PATCH', path, seedAdmin, {householdId: household, displayName: '   '})).status, 200);
  assert.equal((await commit(owner, [write(path, {role: 'familyMember'},
    {mask: ['householdId', 'role'], timestamps: ['updatedAt']})])).status, 200);
  assert.equal((await db('GET', `households/${household}`, person)).status, 403);
  assert.equal((await db('PATCH', path, person, {displayName: 'Repaired name'})).status, 200);
  assert.equal((await db('PATCH', path, person, {displayName: '   '})).status, 403);
});

test('Rules: legacy blank-name allowance retains type, size, entitlement and role protection', async () => {
  const result = await auth('signUp', {email: `blank-security-${run}@example.test`, password, returnSecureToken: true});
  assert.equal(result.status, 200);
  const person = result.data;
  const path = `users/${person.localId}`;
  const profile = {email: person.email, role: 'familyMember', createdAt: stamp};
  assert.equal((await db('PATCH', path, seedAdmin, {...profile, displayName: ''})).status, 200);
  for (const update of [{isGold: true}, {role: 'familyAdmin'}, {adminOverride: true}]) {
    assert.equal((await db('PATCH', path, person, update)).status, 403);
  }
  for (const displayName of [false, 2, ' '.repeat(121)]) {
    assert.equal((await db('PATCH', path, seedAdmin, {displayName})).status, 200);
    assert.equal((await db('PATCH', path, person, {notificationsEnabled: false})).status, 403);
  }
});
