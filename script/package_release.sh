#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 script/configure_signing.py --check
VERSION="${1:-1.0.0-beta.3}"
[[ "$VERSION" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "Invalid version" >&2; exit 2; }
OUTPUT="$PWD/dist/$VERSION"
RELEASE_BUILD_ROOT="${ASUNATRACKS_RELEASE_BUILD_ROOT:-/tmp/asunatracks-release.noindex}"
mkdir -p "$OUTPUT"

# Use the same single installed Mac copy as the normal Run workflow.
ASUNATRACKS_CONFIGURATION=Release ASUNATRACKS_BUILD_ROOT="$RELEASE_BUILD_ROOT/mac" ./script/build_and_run.sh --verify
ditto -c -k --sequesterRsrc --keepParent "$HOME/Applications/AsunaTracks.app" "$OUTPUT/AsunaTracks-macOS.zip"

# These portable device binaries deliberately contain no private provisioning profiles.
# They require the recipient's own Apple signing before installation.
xcodebuild -project AsunaTracks.xcodeproj -scheme AsunaTracks -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$RELEASE_BUILD_ROOT/devices" \
    CODE_SIGNING_ALLOWED=NO -jobs "${ASUNATRACKS_BUILD_JOBS:-2}" build
IOS_APP="$RELEASE_BUILD_ROOT/devices/Build/Products/Release-iphoneos/AsunaTracks.app"
PAYLOAD_ROOT="$RELEASE_BUILD_ROOT/package"
rm -rf "$PAYLOAD_ROOT"
mkdir -p "$PAYLOAD_ROOT/Payload"
ditto --norsrc --noextattr "$IOS_APP" "$PAYLOAD_ROOT/Payload/AsunaTracks.app"
if find "$PAYLOAD_ROOT" \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print -quit | read -r _; then
    echo "Refusing to publish private device provisioning profiles." >&2; exit 1
fi
(cd "$PAYLOAD_ROOT" && zip -q -r AsunaTracks-iPhone-iPad-unsigned.ipa Payload)
mv "$PAYLOAD_ROOT/AsunaTracks-iPhone-iPad-unsigned.ipa" "$OUTPUT/AsunaTracks-iPhone-iPad-unsigned.ipa"
ditto -c -k --keepParent "$IOS_APP/Watch/AsunaTracksWatch.app" "$OUTPUT/AsunaTracks-Apple-Watch-unsigned.zip"
cp INSTALL.md "$OUTPUT/INSTALL.md"
RELEASE_BUILD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$IOS_APP/Info.plist")
RELEASE_APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$IOS_APP/Info.plist")
python3 script/verify_release.py "$OUTPUT" "$RELEASE_BUILD_VERSION" "$RELEASE_APP_VERSION"
(cd "$OUTPUT" && shasum -a 256 AsunaTracks-macOS.zip AsunaTracks-iPhone-iPad-unsigned.ipa AsunaTracks-Apple-Watch-unsigned.zip BUILD_MANIFEST.json > SHA256SUMS.txt)
echo "Release downloads: $OUTPUT"
