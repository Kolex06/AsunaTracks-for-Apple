#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-1.0.0-beta.2}"
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
    CODE_SIGNING_ALLOWED=NO build
IOS_APP="$RELEASE_BUILD_ROOT/devices/Build/Products/Release-iphoneos/AsunaTracks.app"
PAYLOAD_ROOT="$RELEASE_BUILD_ROOT/package"
rm -rf "$PAYLOAD_ROOT"
mkdir -p "$PAYLOAD_ROOT/Payload"
ditto --norsrc --noextattr "$IOS_APP" "$PAYLOAD_ROOT/Payload/AsunaTracks.app"
if find "$PAYLOAD_ROOT" \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print -quit | read -r _; then
    echo "Refusing to publish private device provisioning profiles." >&2; exit 1
fi
(cd "$PAYLOAD_ROOT" && zip -q -r "$OUTPUT/AsunaTracks-iPhone-iPad-unsigned.ipa" Payload)
ditto -c -k --keepParent "$IOS_APP/Watch/AsunaTracksWatch.app" "$OUTPUT/AsunaTracks-Apple-Watch-unsigned.zip"
cp INSTALL.md "$OUTPUT/INSTALL.md"
(cd "$OUTPUT" && shasum -a 256 AsunaTracks-macOS.zip AsunaTracks-iPhone-iPad-unsigned.ipa AsunaTracks-Apple-Watch-unsigned.zip > SHA256SUMS.txt)
echo "Release downloads: $OUTPUT"
