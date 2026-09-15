# Na2slna: iOS App Store handoff

The project is prepared for an iOS release, but **no iOS archive or signed IPA has been built or tested on this Windows computer**. An App Store build still needs a Mac, Xcode, Apple Developer Program membership, signing, and the service setup below. Nothing in this workflow uploads or publishes the app.

## Project settings

- Bundle identifier: `com.ghandour.na2slna` (matches the existing Firebase iOS options).
- Version: read from `pubspec.yaml`; choose a new, unused build number when archiving.
- Minimum iOS version: 15.0, required by the resolved Firebase plugins.
- Flutter already manages native plugins through Swift Package Manager. Do not manually add duplicate Firebase packages or create a Podfile for this preparation.
- Google Sign-In uses the existing iOS OAuth client and its callback URL scheme. Firebase initializes from `lib/firebase_options.dart`.
- Camera/photo permission explanations, notification background modes, push entitlement, and the invitation domain are configured in the iOS project. Microphone/speech purpose strings are included for the linked speech plugin; no voice UI has been added.
- Debug builds use Google's sample AdMob application ID. Release builds require your own **iOS** AdMob application ID and banner ad unit ID.

The portable settings have been prepared without executing Swift, resolving Apple SDK dependencies, or editing native dependency registrations on Windows. Xcode must still resolve and validate the project on the Mac.

Validated on Windows: both property lists parse without duplicate keys; the OAuth client/callback matches the existing Firebase options; configuration includes and permission keys are consistent; the helper passes Bash syntax checking and correctly refuses to run on Windows. Flutter analysis reports no errors or warnings and one existing `avoid_print` information message in `login_screen.dart:55`. These checks do not establish a successful iOS compile, code signature, or App Store validation.

## One-time setup on the Mac

1. Install Flutter compatible with the repository's SDK constraints and Xcode 26.2 or later with the iOS 26 or later SDK. Firebase's Apple SDK has a stricter supported Xcode minimum than the App Store's SDK requirement. Complete Xcode's first launch setup and confirm `flutter doctor` can use its iOS toolchain.
2. Enroll in the Apple Developer Program. Register `com.ghandour.na2slna` and create its App Store Connect app record. Enable Push Notifications and Associated Domains for that App ID.
3. Open `ios/Runner.xcworkspace` in Xcode, sign in to your Apple developer account, and configure the Runner team's automatic signing. Xcode/account access must provide an appropriate distribution certificate and provisioning profile. Keep private signing keys and account credentials in the Mac's keychain or your build service's secret storage; do not paste them into chat or commit them.
4. Copy `ios/Flutter/Signing.example.xcconfig` to `ios/Flutter/Signing.local.xcconfig`. Fill in `DEVELOPMENT_TEAM` and `IOS_ADMOB_APP_ID` using the Apple team and the AdMob iOS app. The local file is excluded from Git. An Android AdMob app ID cannot substitute for the iOS ID.
5. In Firebase, verify the existing iOS app registration, OAuth client, bundle ID, and Google provider settings. Create an APNs authentication key in the Apple developer portal and upload it through Firebase's Cloud Messaging settings with its key ID and team ID. Keep the private `.p8` file out of the repository.
6. Configure the two non-consumable App Store Connect products used by the app: `na2slna_pro_lifetime` and `na2slna_gold_lifetime`. Complete their availability and metadata, then test purchases and restoration in Apple's sandbox.

## Invitation links

The entitlement declares `applinks:na2slna.web.app`. Universal links also require a valid HTTPS association file at:

`https://na2slna.web.app/.well-known/apple-app-site-association`

Its app identifier must contain the registered app's actual Apple App ID prefix and `com.ghandour.na2slna`. Permit only `/join` and `/join/` paths so `/help` and `/privacy` continue to open in the browser. The file must be served directly as JSON without a redirect. This preparation does **not** deploy the association file or configure Firebase Hosting. Test both HTTPS invitations and the existing `na2slna://join` QR link on an iPhone after installation.

## Create the IPA

From the repository root on the configured Mac, replace the banner placeholder and choose an unused build number:

```sh
BUILD_NUMBER=10 \
IOS_ADMOB_BANNER_AD_UNIT_ID='YOUR_REAL_IOS_BANNER_AD_UNIT_ID' \
bash scripts/build_ios_app_store.sh
```

The helper checks the Mac/Xcode/SDK requirements and local signing settings, generates Flutter's iOS configuration, checks the effective Xcode settings, and calls `flutter build ipa` for App Store export. It requires a real iOS banner ID, not a Google sample ID. The resulting archive is under `build/ios/archive/` and the signed `.ipa` is under `build/ios/ipa/` when export succeeds. The helper requires a freshly exported IPA with the expected bundle ID and build number, so an older file cannot hide an export failure. It does not upload the IPA. The export check was exercised locally with synthetic ZIP fixtures for fresh, stale, wrong-app and wrong-build cases.

Run the app on an iPhone and validate the archive in Xcode before uploading to TestFlight or App Store Connect. Confirm that the exported signing profile and APNs entitlement use the production environment; Xcode's provisioning/export settings determine the final signed entitlements. Complete the app's screenshots, privacy details, age rating, support/privacy URLs, purchase metadata, and reviewer access instructions in App Store Connect.

## Work remaining before review

Preparing signing settings does not resolve the existing app defects or establish App Store approval readiness:

- **Account deletion:** the app allows account creation but has no in-app account deletion flow. Apple requires users to be able to initiate deletion within the app.
- **Login:** Google Sign-In is offered without an equivalent login option meeting Apple's privacy requirements. Add an appropriate option such as Sign in with Apple, or make a deliberate compliant change to the offered login methods before review.
- **Security and purchases:** earlier isolated tests found permissive local database rules, unverified entitlement changes, and payment validation defects. The deployed rules were not verified. Resolve these issues and repeat the relevant tests before exposing real customer data or payments.
- **iOS runtime checks:** verify startup, Google sign-in, camera capture, QR scanning, permissions, push registration/delivery, invitations, StoreKit purchases/restoration, iPhone/iPad layouts, and error recovery. Current notification code requests an FCM token without first checking APNs token availability and only displays foreground notifications on Android; these need iOS implementation/testing.
- **Icons:** the existing icon dimensions are correct, including the 1024px marketing image, but PNGs retain an alpha channel. The marketing image's pixels are fully opaque. Normalize the classic App Store icon to RGB without changing its appearance, then verify it in Xcode's archive validation. Icon assets have not been changed in this preparation.
- **Privacy:** review the archive's aggregated SDK privacy report and provide accurate App Store privacy declarations. Do not assume that the presence or absence of a top-level `PrivacyInfo.xcprivacy` alone proves compliance. The speech plugin is installed and purpose strings are present, but no voice UI is currently implemented; permission requests and behavior must be tested if that feature is enabled.

## Primary documentation

- [Flutter: build and release an iOS app](https://docs.flutter.dev/deployment/ios)
- [Apple: upcoming submission requirements](https://developer.apple.com/news/upcoming-requirements/)
- [Apple: App Review Guidelines, including login and account deletion](https://developer.apple.com/app-store/review/guidelines/)
- [Apple: offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app)
- [Firebase: Cloud Messaging setup for Flutter and APNs prerequisites](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
- [Firebase: Apple SDK release notes and supported Xcode version](https://firebase.google.com/support/release-notes/ios)
- [Apple: APNs environment and provisioning profiles](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment)
- [Google: Flutter AdMob setup](https://developers.google.com/admob/flutter/quick-start)
- [Google Sign-In: iOS plugin setup](https://pub.dev/packages/google_sign_in_ios)
- [Apple: supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
