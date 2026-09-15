// Read-only deployment inspection using the Firebase CLI's signed-in transport.
// No document values, authentication tokens or secret values are printed.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cliRoot = process.env.FIREBASE_CLI_ROOT ||
  'C:/Users/youss/AppData/Roaming/npm/node_modules/firebase-tools';
const cli = name => require(path.join(cliRoot, 'lib', name));
const project = 'animemusic-e8c09';
const output = path.join(__dirname, 'deployment');
const phase = process.argv[2];
if (!['before', 'after'].includes(phase)) throw new Error('Use before or after.');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');

(async () => {
  const auth = cli('auth');
  const options = {project, nonInteractive: true};
  const account = auth.getProjectDefaultAccount(path.resolve(__dirname, '..'));
  if (!account) throw new Error('Firebase CLI must already be signed in.');
  auth.setActiveAccount(options, account);
  await cli('requireAuth').requireAuth(options);
  const rules = cli('gcp/rules');
  const {Client} = cli('apiv2');
  const releases = await rules.listAllReleases(project);
  const release = releases.find(item => item.name === `projects/${project}/releases/cloud.firestore`);
  if (!release) throw new Error('Default Firestore rules release not found.');
  const files = await rules.getRulesetContent(release.rulesetName);
  const activeRules = files.find(file => file.name === 'firestore.rules') || files[0];
  if (!activeRules) throw new Error('No active Firestore rule source.');
  const localRules = fs.readFileSync(path.join(__dirname, '../firestore.rules'), 'utf8');
  const normalize = value => value.replace(/\r\n/g, '\n').trim();
  const db = new Client({urlPrefix: 'https://firestore.googleapis.com', apiVersion: 'v1'});
  const collections = [];
  let pageToken;
  do {
    const response = await db.post(`/projects/${project}/databases/(default)/documents:listCollectionIds`,
      {pageSize: 1000, ...(pageToken ? {pageToken} : {})}, {skipLog: {resBody: true}});
    collections.push(...(response.body.collectionIds || []));
    pageToken = response.body.nextPageToken;
  } while (pageToken);
  const functions = new Client({urlPrefix: 'https://cloudfunctions.googleapis.com', apiVersion: 'v2'});
  const fnResult = await functions.get(`/projects/${project}/locations/-/functions`, {skipLog: {resBody: true}});
  const hosting = new Client({urlPrefix: 'https://firebasehosting.googleapis.com', apiVersion: 'v1beta1'});
  const hostingResult = await hosting.get('/sites/na2slna/releases', {queryParams: {pageSize: 1}, skipLog: {resBody: true}});
  const index = await db.get(`/projects/${project}/databases/(default)/collectionGroups/items/fields/householdId`,
    {skipLog: {resBody: true}});
  const result = {
    checkedAt: new Date().toISOString(), project, phase,
    rules: {release: release.name, ruleset: release.rulesetName,
      hash: hash(normalize(activeRules.content)), matchesLocal: normalize(activeRules.content) === normalize(localRules)},
    topLevelCollections: collections.sort(),
    functions: (fnResult.body.functions || []).map(fn => ({name: fn.name, state: fn.state,
      updateTime: fn.updateTime, runtime: fn.buildConfig?.runtime, uri: fn.serviceConfig?.uri,
      sourceHash: fn.labels?.['firebase-functions-hash']})),
    hostingRelease: hostingResult.body.releases?.[0],
    suggestionIndex: index.body.indexConfig,
  };
  fs.mkdirSync(output, {recursive: true});
  const rulesBackup = path.join(output, `${phase}.rules`);
  const stateFile = path.join(output, `${phase}.json`);
  if (phase === 'before' && (fs.existsSync(rulesBackup) || fs.existsSync(stateFile))) {
    throw new Error('Refusing to overwrite original before-deployment backup.');
  }
  fs.writeFileSync(rulesBackup, activeRules.content);
  fs.writeFileSync(stateFile, JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({...result, hostingRelease: {
    name: result.hostingRelease?.name, releaseTime: result.hostingRelease?.releaseTime,
    version: result.hostingRelease?.version?.name,
  }}, null, 2));
})().catch(error => {console.error(error.message); process.exitCode = 1;});
