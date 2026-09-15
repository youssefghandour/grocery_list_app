# Local feature QA

Read [REPORT.md](REPORT.md) for repair results and limits. [BASELINE.md](BASELINE.md) preserves the original 28 failing checks. Tests assert intended behavior without expected-failure annotations.

## Prerequisites

- Flutter SDK with cache write access; this run used Flutter 3.44.8 / Dart 3.12.2.
- Node.js and installed functions dependencies. Deployment targets Node 22.
- Java and Firebase CLI; this run used CLI 15.30.0.
- Run commands from the repository root in PowerShell. Inspect each exit code before continuing.

## App tests and builds

```powershell
flutter pub get
flutter test --no-pub --reporter json *> qa/flutter-fixes.jsonl
flutter analyze --no-pub *> qa/analyze-fixes.log
flutter build apk --debug --no-pub *> qa/android-build-fixes.log
flutter build web --no-pub *> qa/web-build-fixes.log
```

Tests under `test/` use fake Firebase adapters and local fixtures. They do not initialize a live project. Purchase operations use test adapters. `test/flutter_test_config.dart` loads a real font for representative text measurements.

## Backend handler tests

```powershell
node --test qa/functions.test.cjs *> qa/function-fixes.log
npm --prefix functions run lint *> qa/functions-lint-fixes.log
```

Actual notification, barcode, deal and payment handlers execute with fake Admin/network adapters. Payment tests exercise signatures, trusted order matching, replay rejection and successful grants using locally generated signatures. No payment or push request leaves the process. These tests do not establish live provider configuration or concurrent webhook behavior in production.

## Local Firebase rules, Auth and household callable

Copy current rules before starting the emulators. In one terminal:

```powershell
Copy-Item -LiteralPath firestore.rules -Destination qa/firestore.rules
npx --yes firebase-tools@15.30.0 emulators:start --only auth,firestore --project demo-na2slna-qa --config qa/firebase.json
```

Wait for both emulators to be ready. In a second terminal at the repository root:

```powershell
node --test qa/emulator-tests.mjs *> qa/emulator-fixes.log
node --test qa/household-tests.cjs *> qa/household-fixes.log
```

The rules suite fixes hosts to `127.0.0.1:9099` and `127.0.0.1:8080`, uses the demo project and unique example.test accounts. An emulator-only privileged context seeds fixtures; asserted actions use each test user's Auth token. Denial tests preserve valid document shapes and use field update masks to test authorization rather than accidental missing fields.

The household suite runs the actual callable's `.run()` handler with the real Admin SDK against local Firestore. This tests transactions, invitation expiry, current-code validation, administrator preservation and competing fifth/sixth joins. Callable Auth transport is represented by explicit request objects; deployed HTTP middleware is outside this test. Business-rule tests moved here from fake-Firestore Dart tests when joining moved to the server. Dart still tests normalization, dispatch and error propagation.

Stop the emulator terminal with Ctrl+C when finished. Do not retarget either suite to production. Reset emails stay in the Auth emulator.

After all four suites finish:

```powershell
node qa/summarize-tests.cjs
```

This reads the four `*-fixes` logs and writes `qa/test-summary.json`. Logs and generated summaries are ignored by Git.

## Manual and external checks

The earlier device pass covered navigation, themes, Help, Privacy, QR display and opening/cancelling sharing. The repaired APK was built but not installed on the user's phone. No real-device writes were performed during repairs. Camera decoding, message delivery, cross-device/offline behavior, real store checkout, push delivery and iOS runtime remain outside verified coverage.

`android-snapshot.ps1` is an environment-specific read-only snapshot helper. Screenshots may contain personal data and are ignored by Git.

See [RELEASE_NOTES.md](RELEASE_NOTES.md) for backend rollout and payment requirements and [DEPLOYMENT.md](DEPLOYMENT.md) for the live release. No deployment is part of the local test commands above. `deployment-state.cjs` performs read-only cloud metadata/rules inspection using the existing Firebase CLI login; `deployment-smoke.cjs` performs public checks without authenticating or writing app data. Deployment metadata backups stay in ignored `qa/deployment/`.

## Test font

`test/fixtures/fonts/PlusJakartaSans.ttf` comes from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/plusjakartasans), distributed under the SIL Open Font License. Its license is included as `test/fixtures/fonts/OFL.txt`. It is a test fixture, not a production asset.
