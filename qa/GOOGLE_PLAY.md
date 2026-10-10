# Google Play backend verification

The Android app starts Google Play Billing and sends its purchase token to
`verifyStorePurchase` in `us-central1`. The backend now checks that token using
Google Play's `purchases.productsv2.getproductpurchasev2` API for the fixed package
`com.ghandour.na2slna` before updating any paid entitlement.

Supported non-consumable products:

- `na2slna_pro_lifetime`
- `na2slna_gold_lifetime`

The server requires a completed purchase for the matching product, rejects another
account's purchase, and records token ownership atomically in `storePurchases`.
Only a token hash is stored; the raw purchase token is not logged or persisted.
Firestore rules do not permit client access to this collection. Pro restoration
preserves existing Gold. Each restore checks Google again. The server acknowledges
new purchases after persisting access; duplicate requests resume safely if a
previous acknowledgement or final database write failed.

New Android purchases use a SHA-256 hash of the Firebase UID as the account ID.
Existing purchases with a raw UID continue to work. Older purchases without an
account ID can be claimed once using their Google-verified token; all subsequent
claims are bound to that first account. This legacy path cannot identify the
original app account before its first server claim.

## Deployment configuration

The Google Play Developer API has been enabled in `animemusic-e8c09`.
The deployed function currently uses the existing service account:

`207784872626-compute@developer.gserviceaccount.com`

Play Console was inspected after the user granted access. This service account is
Active, with the following **app permissions for Na2slna only** and no
developer-account-wide permissions:

- View app information (read-only)
- View financial data
- Manage orders and subscriptions

The dependent read-only app-quality permission is also selected. Both lifetime
product IDs match the backend allowlist and each has one active purchase option.

Google's order-management permission also permits refunds and cancellations. The
verifier implements purchase reads and acknowledgements; it does not issue refunds.
No service-account private key needs to be generated or copied into the app.

`GOOGLE_PLAY_ENABLED=true` is now set in `functions/.env.animemusic-e8c09` and in
both live Google Play functions. For future changes, deploy
`getPaymentCapabilities` and `verifyStorePurchase` together. Apple verification is
not implemented: new clients identify their store and keep Apple checkout disabled.
The no-source capability request is retained for existing Android builds, including
the `data: null` request produced by calling the Firebase SDK without arguments.

## Checks completed

An initial Google-only deployment completed on 15 September 2026 at approximately
16:00 UTC with the feature disabled. A subsequent deployment at 17:26–17:27 UTC
enabled Google Play. The latest read-only audit at 22:38:50 UTC (16 September,
01:38:50 Cairo) confirmed both Google functions ACTIVE on Node 22, with
`GOOGLE_PLAY_ENABLED=true`, the expected service account, and 401 responses to
unauthenticated calls. The Google Play Developer API is ENABLED.

The audit also found one existing server receipt for `na2slna_pro_lifetime`,
verified at 18:03:22 UTC on 15 September, with `acknowledged=true` and
`testPurchase=false`. This is evidence that a Pro purchase completed server
verification and acknowledgement after activation. No Gold receipt was found in
the recent receipt check. The audit did not initiate a purchase or alter a user.

`paymobWebhook` was also updated by the later deployment, but Paymob remains
disabled and returns 503 without processing callbacks. No further deployment was
needed during this audit. Evidence: ignored `qa/deployment/google-play.json`;
`qa/deploy-google-play.log` refers to the earlier 16:00 deployment.

- 37 Google Play handler tests passed with isolated Google/database adapters.
- Four real Firestore emulator tests passed, covering concurrent ownership claims,
  duplicate restores, Gold preservation and pending purchases.
- 17 Flutter payment service/widget tests passed.
- Flutter analysis and Functions lint passed.

The local Firestore emulator was stopped after the tests.

The latest combined handler run passed 65/68 checks: all 37 Google Play tests and
28/31 existing handler tests. Three Paymob tests fail after the refund edits:
transaction reassignment, refund callback writes and void callback writes. The
refund branch unconditionally clears both premium flags, including access from
other purchases. Its transaction-ID deduplication also ignores a later refund
callback reusing an already-recorded sale ID. These edits were preserved for
review; Paymob must remain disabled until its refund handling is corrected and
covered by lifecycle tests. The two old refund tests assume callbacks make no
writes, so they also need revised expectations for a safe refund implementation.

The earlier local read-only impersonation probe was denied
`iam.serviceAccounts.getAccessToken`; this is a diagnostic permission, separate from
the runtime's Google Play access. No IAM role was broadened to bypass that denial.
The later successful Pro receipt provides runtime evidence independently of that
local diagnostic limitation.

## Repeating isolated checks

From the repository root:

```powershell
node --test qa/google-play.test.cjs
flutter test --no-pub test/payment_service_test.dart test/payment_widgets_test.dart
flutter analyze --no-pub
npm --prefix functions run lint
```

With the local Firestore emulator running as described in `qa/README.md`:

```powershell
node --test qa/google-play-emulator.test.cjs
```

`node qa/google-play-access.cjs inspect` reads deployment/API metadata. The
`check-access` action additionally requests a short-lived token for the existing
runtime service account, reads product metadata, and probes Google with a deliberately
invalid purchase token. It needs the caller's impersonation permission; it never
creates a purchase or updates a user's entitlement. Tokens remain in memory.

Before broader rollout, finish a Gold license-tester purchase and restore through
an internal Google Play build, confirm its server receipt and acknowledgement,
and test a pending/declined payment. Pro has a successful live server receipt;
the remaining scenarios have automated coverage but lack live verification here.

## Remaining lifecycle work

Google Play real-time developer notifications and refund reconciliation are not
implemented here. A canceled/refunded token cannot grant or restore new access, but
an entitlement granted earlier is not automatically revoked. A failed server
acknowledgement retries when the client resubmits/restores; there is no independent
background acknowledgement worker yet. These limits must be addressed for unattended
refund handling and retry processing.

References:

- https://developer.android.com/google/play/billing/security
- https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2/getproductpurchasev2
- https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2
- https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products/acknowledge
- https://developers.google.com/android-publisher/getting_started
