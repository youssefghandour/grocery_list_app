// Inspect Google Play integration with the deployed function's actual identity.
// Uses existing Firebase CLI login; tokens stay in memory and never enter logs.
const path = require('node:path');
const cliRoot = process.env.FIREBASE_CLI_ROOT || 'C:/Users/youss/AppData/Roaming/npm/node_modules/firebase-tools';
const cli = name => require(path.join(cliRoot, 'lib', name));
const project = 'animemusic-e8c09';
const packageName = 'com.ghandour.na2slna';
const action = process.argv[2] || 'inspect';
if (!['inspect', 'enable-api', 'check-access'].includes(action)) throw new Error('Unknown action');
(async () => {
  const options = {project, nonInteractive: true};
  const auth = cli('auth');
  const account = auth.getProjectDefaultAccount(path.resolve(__dirname, '..'));
  if (!account) throw new Error('An existing Firebase CLI sign-in is required.');
  auth.setActiveAccount(options, account);
  await cli('requireAuth').requireAuth(options);
  const {Client} = cli('apiv2');
  const skipLog = {reqBody: true, resBody: true};
  const functions = new Client({urlPrefix: 'https://cloudfunctions.googleapis.com', apiVersion: 'v2'});
  const fn = (await functions.get(`/projects/${project}/locations/us-central1/functions/verifyStorePurchase`, {skipLog})).body;
  const serviceAccount = fn.serviceConfig.serviceAccountEmail;
  console.log(JSON.stringify({checkedAt: new Date().toISOString(), serviceAccount,
    functionUpdate: fn.updateTime, enabled: fn.serviceConfig.environmentVariables?.GOOGLE_PLAY_ENABLED === 'true'}));
  const usage = new Client({urlPrefix: 'https://serviceusage.googleapis.com', apiVersion: 'v1'});
  const service = `/projects/${project}/services/androidpublisher.googleapis.com`;
  if (action === 'enable-api') {
    const result = await usage.post(`${service}:enable`, {}, {skipLog});
    console.log(JSON.stringify({operation: result.body.name, done: Boolean(result.body.done)}));
    return;
  }
  console.log(JSON.stringify({api: 'androidpublisher', state: (await usage.get(service, {skipLog})).body.state}));
  if (action !== 'check-access') return;
  const iam = new Client({urlPrefix: 'https://iamcredentials.googleapis.com', apiVersion: 'v1'});
  const result = await iam.post(`/projects/-/serviceAccounts/${serviceAccount}:generateAccessToken`, {
    scope: ['https://www.googleapis.com/auth/androidpublisher'], lifetime: '600s',
  }, {skipLog});
  const headers = {Authorization: `Bearer ${result.body.accessToken}`};
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}`;
  for (const id of ['na2slna_pro_lifetime', 'na2slna_gold_lifetime']) {
    const response = await fetch(`${base}/inappproducts/${id}`, {headers});
    const body = await response.json();
    console.log(JSON.stringify({productId: id, status: response.status,
      productStatus: body.status, purchaseType: body.purchaseType,
      reason: body.error?.errors?.[0]?.reason}));
  }
  // An intentionally invalid token checks API access without fetching a customer's
  // purchase or writing anything. It is NOT evidence of a successful paid checkout.
  const response = await fetch(`${base}/purchases/productsv2/tokens/isolated-permission-check-invalid-token`, {headers});
  const body = await response.json();
  console.log(JSON.stringify({purchaseProbeStatus: response.status, reason: body.error?.errors?.[0]?.reason,
    message: body.error?.message}));
})().catch(error => {
  console.error(JSON.stringify({action, status: error.status || error.code || 'setup-check-failed',
    message: error.context?.body?.error?.message || 'Check the existing account permissions.'}));
  process.exitCode = 1;
});
