# Na2slna feature QA — 14 September 2026

**Result: 103 automated checks, 75 passed and 28 failed. Android debug and web builds both passed.** The failures include several checks of the same underlying defect; they are not 28 independent bugs. The app needs fixes before this can be considered a passing feature test run.

All account creation, membership changes, item writes/deletions and payment simulations used isolated local data. No real purchase, message, invitation delivery or push notification was sent. No production rules or functions were deployed.

## Evidence and environment

| Check | Result | Evidence |
| --- | --- | --- |
| Flutter service, controller and widget tests | 61 passed / 16 failed / 77 total | `qa/flutter-tests.jsonl`, `test/` |
| Local Firebase Auth and Firestore rules | 7 passed / 7 failed / 14 total | `qa/emulator-tests.log`, `qa/emulator-tests.mjs` |
| Actual Cloud Function handlers with fake network/Admin adapters | 7 passed / 5 failed / 12 total | `qa/function-tests.log`, `qa/functions.test.cjs` |
| Android debug build | Passed | `qa/android-build.log` |
| Web build | Passed | `qa/web-build.log` |
| Functions lint | Passed | `qa/functions-lint.log` |
| Flutter analysis | No errors or warnings; one existing informational `avoid_print` finding at `lib/screens/auth/login_screen.dart:55` | `qa/analyze-final.log` |

Flutter 3.44.8 / Dart 3.12.2 were used. Firebase Auth and Firestore emulators ran under `demo-na2slna-qa`, bound to localhost. The tested rules copy exactly matched the repository rules (SHA-256 `3B5960A1F6950A43819BD691235CF67E2ADFE43308B37320E4B95DC3BB4B8DEC`). This establishes defects in the local rules, not the state of deployed production rules.

Manual Android checks used the installed app version **1.0.0+9** on the connected M2102J20SG. Automated tests and builds used the current working source; the newly built APK was not installed during this QA pass. The Android build also reports a future Kotlin Gradle compatibility warning for some plugins.

## Feature coverage

| Feature | Verified | Remaining limitation or failure |
| --- | --- | --- |
| Registration and login | Required fields, password visibility, registration navigation, service profile creation, trimmed sign-in, local Auth correct/incorrect password and duplicate email | Live Google OAuth and email delivery were not exercised |
| Password reset and sign-out | Reset request accepted by local Auth; Firebase/Google sign-out adapters called | Reset completion and a visible Forgot Password flow were not tested |
| Household onboarding | Create admin/profile/invitation/default-list records, normalized join codes, invalid/deleted invitations, leave, rename, free five-member limit, Gold larger household | Rejoining as admin loses role; 48-hour expiry is not enforced. Transaction rollback/concurrent joins were not exercised |
| Shopping lists | New list creation, selecting a target list, isolated contents, legacy first-list creation, parent-list deletion | Stale selected list is retained; whitespace-only names accepted. Real Firestore child-document cleanup is not established |
| Grocery items | Quick add, detailed add/edit fields, units/categories/prices, cancel, purchase checkbox, quantity controls, delete confirmation, individual deletion, clear purchased | Decimal quantity corruption, replacement photo not saved, negative prices accepted, unsupported category assertion |
| Suggestions and collaboration | Matching suggestions, case-insensitive integer duplicate merge, deduplication across lists, two local subscriptions receive updates | Decimal duplicate merge fails. Physical cross-device sync, concurrent writes and offline reconnection remain unverified |
| Budget | Total multiplies quantity by unit price | Negative prices are accepted by the item editor |
| Profile and preferences | Name editing, notification preference, token persistence, light/dark, Gold theme selection | Blank member names cause exceptions. Preference persistence across restart was not exercised |
| Invitations | Code input formatting, QR dialog open/close; QR also displayed on Android | Physical camera scanning and complete deep-link join were not exercised in this pass |
| Help and privacy | Both opened the expected web content from the installed Android app | Other platforms were not exercised |
| Sharing and export | Android app-sharing chooser opens and cancels; Gold export action is present and gated | No message sent; export text and destination delivery were not tested |
| Paid plans | Returned product prices displayed, buy action invokes fake adapter, empty-store message, restore adapter invocation | Missing one product, store lookup errors and restore errors fail; no real purchase or receipt verification tested |
| Family Gold | Individual Gold photo/theme/export access and increased household member limit | Other household members do not receive the tested photo benefit despite the entire-household promise |
| Photos | Gold action gating, add/edit data fields | Replacement photo persistence fails. Camera capture, upload and cross-device display were not verified |
| Notifications | Handler excludes sender, disabled users, users without tokens and other households; no recipients means no push call | Actual delivery, OS permission prompts and background receipt unverified; only the item-created trigger was found |
| Barcode/deal backend | Missing search input rejected; barcode response contract tested | Numeric successful barcode status is ignored; current deal prices are generated examples, not verified market prices |
| Error handling | Error-screen retry invokes recovery | Failed add discards the form; failed quick add clears typed text; upgrade errors escape handling |
| Access control | Anonymous read denied, owner/member positive cases | Seven authenticated access-control checks failed locally |

Language and Market Currency settings currently have no action wired to their rows. Voice input and quick-add barcode scanning are not active UI flows in the inspected source. Clear-purchased and list deletion were covered at service level. iOS build/runtime, physical camera/microphone behavior, ad lifecycle, real billing, and end-to-end push delivery remain unverified.

## Reproduced failures, ordered by impact

### Critical: household isolation and paid access

**SEC-01 through SEC-07 — unrestricted authenticated Firestore access.** With the repository rules loaded locally, an unrelated signed-in account can read/rename another household, change another user's membership, grant itself Gold/Pro or administrator status, and delete another household's item. Malformed item field types are also accepted. All seven expected denials returned HTTP 200. Both broad allow rules must be addressed: tightening only one match leaves the other applicable allow effective. Source: [firestore.rules](C:/Users/youss/StudioProjects/grocery_list_app/firestore.rules:12). See also `qa/security-assessment.json`.

**PAY-01 — unsigned successful webhook grants paid features.** Invoking the actual handler with a fabricated successful transaction and no signature records a Gold entitlement update through the fake Admin adapter. The handler trusts body-provided identity and plan. It needs authenticated provider verification and validation against a trusted order record before granting access. This was a local handler test, not a request to a deployed endpoint. Source: [functions/index.js](C:/Users/youss/StudioProjects/grocery_list_app/functions/index.js:228).

### High: payment and data correctness

| IDs | Reproduction and observed behavior | Source |
| --- | --- | --- |
| PAY-02, PAY-03, PAY-04 | Create-order requests accept no authenticated caller, a different claimed user ID, or an unknown plan. Fake provider calls proceed instead of validation rejecting them | [functions/index.js](C:/Users/youss/StudioProjects/grocery_list_app/functions/index.js:175) |
| QA-04 | Add quantity `1.0` to an existing duplicate with quantity `2.0`: result is `2` instead of `3` because integer parsing falls back to 1 | [grocery_list_provider.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/providers/grocery_list_provider.dart:162) |
| QA-07 | Open an item containing quantity `3.0`, make no quantity change, save: quantity becomes 1 | [add_item_dialog.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/widgets/add_item_dialog.dart:47) |
| QA-02 | Join the owner's own invitation again: the existing administrator becomes a family member | [firestore_service.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/services/firestore_service.dart:210) |
| QA-05 | Supply a selected list ID that no longer belongs to the available lists: it is returned without validating membership/existence or falling back | [grocery_list_provider.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/providers/grocery_list_provider.dart:30) |
| QA-09, QA-10 | Simulate a permission-denied write: detailed add closes and quick add clears its input, losing text needed for retry | [add_item_dialog.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/widgets/add_item_dialog.dart:141), [quick_add_bar.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/widgets/quick_add_bar.dart:52) |
| PAY-05 | Store returns only one of the two configured products: the upgrade screen throws when looking up the missing one | [upgrade_screen.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/screens/settings/upgrade_screen.dart:140) |
| PAY-06, PAY-07 | Store lookup or restore throws: exception escapes and the loading state is not cleared reliably | [upgrade_screen.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/screens/settings/upgrade_screen.dart:24) |

### Other reproduced defects

| ID | Reproduction and observed behavior | Source |
| --- | --- | --- |
| QA-01 | Update an item's image URL: the previously stored photo remains because the update map omits `imageUrl` | [firestore_service.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/services/firestore_service.dart:320) |
| QA-08 | Enter price `-5`: item is saved with a negative price | [add_item_dialog.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/widgets/add_item_dialog.dart:115) |
| QA-11 | Open an item with an externally assigned category absent from the current choices: dropdown assertion in a debug/widget test | [add_item_dialog.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/widgets/add_item_dialog.dart:333) |
| QA-12 | Create a list whose name is only spaces: an empty name is stored | [list_tab_view.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/screens/home/views/list_tab_view.dart:196) |
| QA-13 | Render a household member with an empty display name: indexing its first character throws a RangeError | [household_widgets.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/screens/home/widgets/household_widgets.dart:378) |
| QA-14 | Give the admin Gold, then open another household member's item editor: photo access remains unavailable despite Family Gold being advertised for the entire household | [add_item_dialog.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/widgets/add_item_dialog.dart:191) |
| QA-15 | Join using a three-day-old invitation: accepted despite the interface saying Valid 48h | [firestore_service.dart](C:/Users/youss/StudioProjects/grocery_list_app/lib/services/firestore_service.dart:166) |
| BAR-01 | Return a successful Open Food Facts response with numeric `status: 1`: item enrichment is ignored because the handler expects the string `success` | [functions/index.js](C:/Users/youss/StudioProjects/grocery_list_app/functions/index.js:34) |

The barcode response fixture follows the provider's documented numeric status convention. Reference: [Open Food Facts API tutorial](https://openfoodfacts.github.io/openfoodfacts-server/api/tutorial-off-api/).

## Source-review findings beyond the automated totals

- Paymob credentials/integration IDs in `functions/index.js:185` are placeholders. The native mobile checkout block in `lib/services/payment_service.dart` is commented out. A passing fake-provider test would not establish working checkout.
- `PaymentService._verifyAndEnablePro` directly updates entitlement fields from the client without server receipt verification. The broad rules make those fields writable independently of a purchase.
- Item photos store a local device path; no shared image upload was found in the inspected flow. Cross-device image sharing needs a separately verified upload/display path.
- The settings description mentions notifications when items are checked off, but the backend inspected here only registers an item-created trigger.

## Original Help-link problem

The earlier `/help` failure was caused by website support links being delivered to Flutter as application routes. The app had no `/help` route to handle that launch. The earlier fix narrowed Android app links to join paths and disabled Flutter's automatic deep-link routing so the application's join-link handler can own that flow. In this QA pass, Help and Privacy opened their expected browser pages on Android.

## Changes and follow-up

This QA pass replaced the obsolete starter counter test, added feature/security/payment tests, added test-only fake Firebase dependencies, and bundled a licensed test font to avoid artificial Ahem-font layout failures. Production bugs were left reproducible; there are no skipped or expected-failure annotations hiding them. Existing worktree changes were preserved.

Fix access control and payment verification first, then quantity/state handling and save recovery, then the remaining UI/data defects. Re-run the retained tests after each relevant fix. Real store sandbox transactions, two isolated device accounts, offline reconnect, camera scanning, and iOS testing are still required for complete end-to-end coverage. See `qa/README.md` for local reproduction commands.
