# Applying the tested repairs

The repaired Cloud Functions, Firestore rules/index configuration and web app were deployed on 15 September 2026 to `animemusic-e8c09`, Hosting site `na2slna`. See [DEPLOYMENT.md](DEPLOYMENT.md) for release verification. Feature-test data remained isolated; no production accounts, households or items were created or changed by the deployment checks.

## Backend and client must ship together

The app now joins households through the authenticated `joinHousehold` callable in `us-central1`. The server validates the active invitation, enforces its 48-hour lifetime, preserves existing administrator roles and serializes the free five-member limit. Rules prevent a client from assigning arbitrary membership or paid flags.

Deploy and verify the join callable before activating the tightened rules and releasing the updated client. Older clients that join by directly updating their membership will be denied by the new rules; plan the client rollout accordingly. Keep the strict rules when testing compatibility, rather than reopening client membership writes.

Deployment configuration now consistently targets Node 22 and runs the existing lint script. Previously, it selected deprecated Node 18 while `package.json` requested Node 24, and referenced a nonexistent build script. Node 22 is supported in [Firebase's runtime documentation](https://firebase.google.com/docs/functions/manage-functions#set_node.js_version). This JavaScript project has no compilation step.

Before rollout, review existing documents for compatibility. Rules allow unchanged, bounded legacy quantity labels and blank display names; new or changed values must meet current validation. Legacy items without a `householdId` remain editable under their household path, but are excluded from the collection-group suggestion query until a trusted migration backfills the field. Other malformed historical records may require correction. No production migration has been attempted.

## Payments

For the subsequent Google Play backend verification work and its current rollout
status, see [GOOGLE_PLAY.md](GOOGLE_PLAY.md). The notes below describe the earlier
15 September deployment; they do not establish the current Google Play setup.

Native Android/iOS purchases are deliberately unavailable until a real server receipt verifier is implemented and tested for the actual store apps. `verifyStorePurchase` rejects unverified receipts, `getPaymentCapabilities` returns `nativeStore: false`, and the app checks that capability before initiating a purchase or restore. Do not enable purchasing merely by changing that flag. The server must validate product, app identity, transaction ownership and replay status before granting and completing a purchase.

Paymob checkout is web-only. The callable creates a server-priced order tied to the authenticated UID; the webhook verifies HMAC-SHA512, checks the matching amount/currency/integration/order and atomically records the entitlement and processed transaction. Unsigned metadata cannot select the recipient. See [Paymob's official verification reference](https://github.com/PaymobAccept/Paymob-AI-Integration-Skill/blob/main/skills/paymob-integration/references/hmac-verification.md) and [Create Intention API](https://developers.paymob.com/paymob-docs/intention-apis/create-intention).

Configure the following on the server before deploying payment functions:

| Setting | Purpose |
| --- | --- |
| `PAYMOB_SECRET_KEY` | Firebase-bound secret; merchant secret key matching the selected mode |
| `PAYMOB_HMAC_SECRET` | Firebase-bound secret; merchant callback HMAC key |
| `PAYMOB_PUBLIC_KEY` | Public checkout key matching the selected mode |
| `PAYMOB_MODE` | `test` or `live` |
| `PAYMOB_INTEGRATION_IDS` | Comma-separated positive integration IDs for that merchant/mode |
| `PAYMOB_ENABLED` | Must be exactly `true` to create orders; leave disabled until tested |

Keep secrets out of source control and client assets. Disabled payment handlers now deploy without merchant secret bindings; they cannot create orders or accept payment callbacks. When billing is ready, set `PAYMOB_ENABLED=true` and redeploy to bind the required real secrets. Those secrets must then exist before deployment. This release contains no merchant credentials and keeps both native and Paymob purchases unavailable.

Set the payment integration's processed transaction callback to the deployed `paymobWebhook` URL with the correct HMAC secret. Start with the merchant's test configuration and verify actual checkout, webhook, duplicate callback and account entitlement before selecting live mode. No live or merchant-sandbox transaction was attempted here.

Refund/void callbacks cannot grant new access, but this implementation does not revoke access already granted before a refund. Reconciliation, refund policy and operational monitoring still need implementation before a production billing launch.

## Remaining release checks

- Household profile reads include email, notification settings and device messaging tokens; split public member profiles from private account data before broad release. See the security assessment.
- Item photos still use device paths; replacement-path persistence is repaired, but shared upload/display needs separate work.
- Real Google login, reset completion, camera/QR decoding, cross-device and offline sync, advertising and push delivery require device/environment checks.
- Language and Market Currency rows, voice input and quick-add scanning are not complete active flows. Deal prices are generated examples.
- iOS project preparation is preserved in [APP_STORE.md](../ios/APP_STORE.md). Mac/Xcode and Apple Developer signing are still required; no App Store IPA has been produced.
