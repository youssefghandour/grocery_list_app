# Na2slna production deployment — 15 September 2026

Live app: **https://na2slna.web.app**

Latest payment audit, 16 September at 01:38 Cairo (15 September 22:38 UTC): both
Google Play functions are ACTIVE with verification enabled, and reject
unauthenticated requests. Play Console permissions and both product IDs were
confirmed. An existing Pro receipt records successful server verification and
acknowledgement at 18:03 UTC. Paymob remains disabled; its local refund edits have
review findings and three failing existing tests. See
[GOOGLE_PLAY.md](GOOGLE_PLAY.md) for the current payment implementation, tests and
remaining setup. The deployment details below describe the earlier full-app release.

Target: Firebase project `animemusic-e8c09`, Hosting site `na2slna`, Standard Firestore `(default)` in `eur3`. Other Hosting sites, Storage rules and Realtime Database rules were not deployed.

## Published components

- All seven Cloud Functions are ACTIVE on Node 22: `joinHousehold`, `getPaymentCapabilities`, `verifyStorePurchase`, `createPaymobOrder`, `paymobWebhook`, `searchProductDeals`, and `onGroceryItemCreated`.
- The item-created trigger stays in its existing `europe-west1` region. Callable/payment endpoints use `us-central1`.
- Firestore's active rules were read back and match the tested local source after normalizing line endings.
- Added the production collection-group index on `items.householdId` used by shopping suggestions, preserving ordinary collection indexes. All four indexes were confirmed READY at 2026-09-15 05:13:42 UTC / 08:13:42 Cairo.
- Rebuilt and published the web app, including restored Android association data and corrected icon filenames.

The backend completed first, followed by Firestore and Hosting. No production profiles, membership, items, payments, invitations or messages were created as test data.

## Verification

- The original local suite passed 186 checks on 14 September. The backend was rerun for this release: **31/31 passed**, including two new disabled-billing deployment checks; Functions lint passed.
- Final web build succeeded. Firebase accepted both deployment previews and completed both releases.
- **17/17 non-destructive public checks passed:** protected callables reject unauthenticated requests, disabled payment callbacks cannot grant access, five important live files match the final build byte-for-byte, Help/Privacy/join routes load, and four manifest icons serve images.
- Browser verification showed the published Na2slna login screen. No login or account creation was performed.

Hosting release: `sites/na2slna/releases/1789448885941000`, version `sites/na2slna/versions/60969691b640650d`, released at 2026-09-15 05:08:05 UTC / 08:08:05 Cairo.

Firestore ruleset: `projects/animemusic-e8c09/rulesets/426dabd5-81ba-4cbd-9325-7c7bc3a62bed`.

Evidence: `qa/deploy-functions-final.log`, `qa/deploy-site-release.log`, `qa/deploy-function-tests.log`, `qa/deploy-web-build.log`, `qa/deploy-smoke.log`, and ignored `qa/deployment/after.json`. Previous Firestore rules and Hosting release metadata are retained in ignored `qa/deployment/before.rules` and `before.json`; the function snapshot there was taken after function publication, not before it. Do not restore the older unrestricted Firestore rules to address a client error.

## Limits

- Purchases remain unavailable: merchant credentials are absent and native receipt verification is not implemented. This release prevents unverified grants; it does not launch real billing.
- The browser app updates immediately. Installed Android/iOS apps need a newly distributed app build to receive UI changes. Older apps that directly write household membership will be denied by the secure rules.
- No Play Store/App Store release or phone installation was performed. iOS signing still requires a Mac/Xcode environment and an Apple Developer account.
- Same-household profiles still expose email/settings/messaging-token fields; the privacy separation work and other device-dependent checks in [RELEASE_NOTES.md](RELEASE_NOTES.md) remain outstanding.
