#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'Cannot build: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Use a Mac with Xcode; Windows cannot produce this signed IPA."
for command in flutter xcodebuild xcrun swift python3; do
  command -v "$command" >/dev/null 2>&1 || fail "Install $command on the Mac first."
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

[[ "${BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]] || fail "Set BUILD_NUMBER to an unused positive App Store build number."
[[ "${IOS_ADMOB_BANNER_AD_UNIT_ID:-}" =~ ^ca-app-pub-[0-9]{16}/[0-9]{10}$ ]] || fail "Set IOS_ADMOB_BANNER_AD_UNIT_ID to your real iOS banner unit ID."
[[ "$IOS_ADMOB_BANNER_AD_UNIT_ID" != ca-app-pub-3940256099942544/* ]] || fail "A Google sample banner cannot be used for an App Store build."
[[ -f ios/Flutter/Signing.local.xcconfig ]] || fail "Copy Signing.example.xcconfig to Signing.local.xcconfig and fill in your Apple team and iOS AdMob app ID."

xcode_version="$(xcodebuild -version | awk '/^Xcode / {print $2}')"
sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
IFS=. read -r xcode_major xcode_minor _ <<< "$xcode_version"
[[ "$xcode_major" -gt 26 || ( "$xcode_major" -eq 26 && "${xcode_minor:-0}" -ge 2 ) ]] || fail "The Firebase Apple SDK requires Xcode 26.2 or newer."
[[ "${sdk_version%%.*}" -ge 26 ]] || fail "Select an Xcode installation with the iOS 26 SDK or newer."
swift --version

flutter pub get
flutter build ios --release --config-only --build-number="$BUILD_NUMBER" \
  --dart-define="IOS_ADMOB_BANNER_AD_UNIT_ID=$IOS_ADMOB_BANNER_AD_UNIT_ID"

# Ask Xcode for resolved target settings; do not assume the optional file was read.
settings_file="$(mktemp -t na2slna-ios-settings)"
trap 'rm -f "$settings_file"' EXIT
xcodebuild -project ios/Runner.xcodeproj -scheme Runner -configuration Release \
  -sdk iphoneos -showBuildSettings -json > "$settings_file"
python3 - "$settings_file" <<'PY'
import json
import re
import sys

with open(sys.argv[1]) as stream:
    targets = json.load(stream)
settings = next(entry['buildSettings'] for entry in targets if entry['target'] == 'Runner')
def require(condition, message):
    if not condition:
        sys.exit('Cannot build: ' + message)

require(settings.get('PRODUCT_BUNDLE_IDENTIFIER') == 'com.ghandour.na2slna', 'Unexpected bundle ID in Runner.')
require(re.fullmatch(r'[A-Z0-9]{10}', settings.get('DEVELOPMENT_TEAM', '')), 'Set a valid Apple development team in Signing.local.xcconfig.')
app_id = settings.get('IOS_ADMOB_APP_ID', '')
require(re.fullmatch(r'ca-app-pub-\d{16}~\d{10}', app_id), 'Set your iOS AdMob app ID in Signing.local.xcconfig.')
require(not app_id.startswith('ca-app-pub-3940256099942544~'), 'Replace the sample AdMob app ID for release.')
require(float(settings.get('IPHONEOS_DEPLOYMENT_TARGET', '0')) >= 15, 'Runner must target iOS 15 or newer.')
require(settings.get('CODE_SIGN_ENTITLEMENTS') == 'Runner/Runner.entitlements', 'Runner entitlements are not configured.')
require(settings.get('IOS_APS_ENVIRONMENT') == 'production', 'Release push entitlement must use production.')
print('Release settings validated. Creating a signed App Store archive and IPA.')
PY

# Flutter defaults to App Store export. Signing must already be configured in Xcode.
# This command creates artifacts only; it does not upload or publish the app.
build_started_at="$(python3 -c 'import time; print(time.time_ns())')"
flutter build ipa --release --no-pub --build-number="$BUILD_NUMBER" \
  --dart-define="IOS_ADMOB_BANNER_AD_UNIT_ID=$IOS_ADMOB_BANNER_AD_UNIT_ID"

# Flutter can return success after archiving even when exporting the IPA fails.
# Preserve older artifacts, but never report one as the result of this build.
python3 - "$BUILD_NUMBER" "$build_started_at" <<'PY'
from pathlib import Path
import plistlib
import sys
import zipfile

expected_build, started_at = sys.argv[1], int(sys.argv[2])
fresh_ipas = [path for path in Path('build/ios/ipa').glob('*.ipa')
              if path.stat().st_mtime_ns >= started_at]
if not fresh_ipas:
    sys.exit('Cannot build: no fresh IPA was exported. Check Xcode signing and provisioning; older artifacts were preserved.')

for path in fresh_ipas:
    with zipfile.ZipFile(path) as archive:
        info_paths = [name for name in archive.namelist()
                      if len(name.split('/')) == 3
                      and name.startswith('Payload/')
                      and name.endswith('.app/Info.plist')]
        if len(info_paths) != 1:
            sys.exit('Cannot build: exported IPA has no unique application Info.plist.')
        info = plistlib.loads(archive.read(info_paths[0]))
    if info.get('CFBundleIdentifier') != 'com.ghandour.na2slna' or str(info.get('CFBundleVersion')) != expected_build:
        sys.exit('Cannot build: exported IPA identity/build number does not match this request.')
    print(f'App Store IPA created: {path} (build {expected_build})')
PY
