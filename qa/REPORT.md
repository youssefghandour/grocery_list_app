# Na2slna repair verification — 14 September 2026

**Deployment update, 15 September:** The tested changes are now live on [na2slna.web.app](https://na2slna.web.app), including Cloud Functions and Firestore rules/index configuration. Two additional payment rollout tests pass (31 backend checks total), and 17 non-destructive public deployment checks pass. The 186-check table below records the original 14 September verification. See [DEPLOYMENT.md](DEPLOYMENT.md) for the current release and remaining platform limits.

**Result: 186 automated checks passed, 0 failed. Android debug and web builds passed; Flutter analysis and Functions lint passed.** The original run had 28 failing checks; its evidence and coverage matrix are preserved in [BASELINE.md](BASELINE.md). Several checks cover the same underlying defect, so these were not 28 separate bugs.

All account creation, membership changes, item writes/deletions and payment simulations used isolated local data. No real purchase, message, invitation delivery or push was sent. No production rules or functions were deployed. The repaired APK was not installed on the user's phone.

## Evidence

| Check | Result | Local evidence |
| --- | --- | --- |
| Flutter service/controller/widget tests | 96/96 passed | `qa/flutter-fixes.jsonl`, `test/` |
| Local Auth and Firestore rules | 43/43 passed | `qa/emulator-fixes.log`, `qa/emulator-tests.mjs` |
| Real household callable with local Firestore transactions | 18/18 passed | `qa/household-fixes.log`, `qa/household-tests.cjs` |
| Notification/barcode/payment handlers with fake network/Admin adapters | 29/29 passed | `qa/function-fixes.log`, `qa/functions.test.cjs` |
| Flutter analysis | No issues | `qa/analyze-fixes.log` |
| Functions lint | Passed | `qa/functions-lint-fixes.log` |
| Android debug build | Passed | `qa/android-build-fixes.log` |
| Web build | Passed | `qa/web-build-fixes.log` |

No tests were skipped or marked as expected failures. Household business-rule tests now run against the actual server transaction, replacing Dart fake-client join checks; Dart retains transport/error tests. This changes the suite composition as well as expanding coverage. Runtime: Flutter 3.44.8 / Dart 3.12.2; Firebase CLI 15.30.0; local Standard-edition Firestore and Auth under `demo-na2slna-qa`.

The emulator and repository rules match SHA-256 `3B06EE974EBC2B545BA4AAC682208553E1CBAF9C254C0546D45279C36D43F437`. Results establish local behavior, not the state of deployed production rules.

## What was fixed

| Original IDs | Repair and verification |
| --- | --- |
| SEC-01–SEC-07 | Membership/ownership rules replace unrestricted signed-in access. Cross-household reads/writes, client paid upgrades, role escalation and malformed fields are denied; allowed collaboration, queries, atomic household creation, profile edits, leaving/removal and invitation refresh also pass. |
| PAY-01–PAY-04 | Authenticated order creation uses trusted plan prices and UID. Paymob callbacks require a valid signature and matching server order. Unsigned/tampered/mismatched/replayed callbacks cannot grant access; valid signed sales and duplicate delivery are tested. |
| PAY-05–PAY-07 | Missing products, store lookup failures and restore failures produce recoverable screen states instead of unhandled errors. Native purchases are disabled until server receipt verification exists. |
| QA-01 | Item edits persist replacement photo paths. Shared photo upload remains separate work. |
| QA-02, QA-15 | Server invitation acceptance preserves owner roles, enforces 48-hour expiry and active-code matching. Refresh creates a new code and invalidates the old one; administrators have a refresh action with retry handling. |
| QA-04, QA-07 | Decimal duplicate quantities merge correctly and existing decimal quantities survive editing. Quantity controls preserve decimals. |
| QA-05 | A selected list is checked against the current household's available lists; stale selections fall back safely. |
| QA-08, QA-12 | Negative/invalid prices and blank list names are rejected. Names are trimmed. |
| QA-09, QA-10 | Failed detailed and quick adds retain typed input and expose retryable errors; duplicate submissions are prevented. |
| QA-11, QA-13 | Unknown existing categories and blank profile/member names no longer crash the tested UI. |
| QA-14 | Current household members inherit the current owner's Gold benefits across photo, theme, export and ad gates. A departed owner or unrelated Gold member cannot supply household benefits. |
| BAR-01 | Barcode enrichment recognizes the provider's numeric success status. |

Additional checks verify concurrent fifth/sixth joins cannot exceed a free household's five-member limit, paid users cannot be selected by forged payment metadata, and new invalid data remains blocked while bounded legacy labels/blank names can be retained during unrelated edits.

Deployment configuration now consistently uses Node 22 and no longer calls a nonexistent Functions build script. The existing Android plugin compatibility warning remains; the current build succeeds.

## What remains outside the result

Passing the retained tests does not establish that every app feature is complete or ready for a store release.

- **Payments:** native receipt verification is not implemented, so native checkout/restore are unavailable. Paymob needs merchant configuration and real test-mode checkout. Refunds do not revoke already-granted access. No real charge was attempted.
- **Security privacy:** same-household profile reads still include email, preferences and device messaging tokens. The updated local audit scores this 3/5 and recommends separating private account data. See [security-assessment.json](security-assessment.json).
- **Devices and services:** real Google OAuth, reset-email completion, camera/QR decoding, two-device sync, offline reconnect, actual ads and push delivery were not verified during repairs.
- **Incomplete features/data handling:** photo upload across devices, child-item cleanup when deleting a list, inactive Language/Market Currency rows, voice input and quick-add barcode scanning remain outside repaired test coverage. Deal prices remain generated examples.
- **iOS:** project preparation is preserved, but no signed IPA or iOS runtime test is possible here without a Mac/Xcode environment and Apple signing.

The earlier Help-link failure came from website support links being treated as Flutter app routes. The preceding link-routing fix is preserved; the earlier Android manual pass confirmed Help and Privacy opened the expected web pages.

See [README.md](README.md) to rerun tests and [RELEASE_NOTES.md](RELEASE_NOTES.md) for backend/client rollout and payment setup requirements.
