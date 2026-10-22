#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
APP_NAME="AsunaTracksMac"
# Stage outside Documents: File Provider can attach signing-incompatible Finder metadata.
STAGED_APP="${TMPDIR:-/tmp}/AsunaTracksMac-${UID}/AsunaTracks.app"
APP_BUNDLE="$HOME/Applications/AsunaTracks.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
case "$MODE" in run|--verify|--debug|--logs|--telemetry) ;; *) echo "Usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2;; esac
BUILD_ROOT="${ASUNATRACKS_BUILD_ROOT:-/tmp/asunatracks-mac}"
BUILD_CONFIGURATION="${ASUNATRACKS_CONFIGURATION:-Debug}"
xcodebuild -project AsunaTracks.xcodeproj -scheme AsunaTracksMac -configuration "$BUILD_CONFIGURATION" -destination 'platform=macOS' -derivedDataPath "$BUILD_ROOT" -jobs "${ASUNATRACKS_BUILD_JOBS:-2}" build
BUILD_DIR="$BUILD_ROOT/Build/Products/$BUILD_CONFIGURATION"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
# Preserve the app and extension signatures and their shared-container entitlements.
ditto --norsrc --noextattr "$BUILD_DIR/AsunaTracks.app" "$STAGED_APP"
ICON_DIR="$PWD/.build/AsunaTracks.iconset"
mkdir -p "$ICON_DIR"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" AsunaTracks/Shared/AsunaTracksLogo.png --out "$ICON_DIR/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" AsunaTracks/Shared/AsunaTracksLogo.png --out "$ICON_DIR/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_DIR" -o "$STAGED_APP/Contents/Resources/AsunaTracks.icns"
xattr -rd com.apple.FinderInfo "$STAGED_APP" 2>/dev/null || true
xattr -rd com.apple.ResourceFork "$STAGED_APP" 2>/dev/null || true
# The icon is added after Xcode builds; re-sign only the containing app with the same identity.
codesign --force --sign "Apple Development" --preserve-metadata=entitlements --options runtime "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
mkdir -p "$HOME/Applications"
INSTALL_CANDIDATE="$HOME/Applications/.AsunaTracks-install.noindex"
rm -rf "$INSTALL_CANDIDATE"
ditto --norsrc --noextattr "$STAGED_APP" "$INSTALL_CANDIDATE"
codesign --verify --deep --strict "$INSTALL_CANDIDATE"
rm -rf "$APP_BUNDLE"
mv "$INSTALL_CANDIDATE" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
# Only the installed copy belongs in the launcher and widget gallery.
for ARTIFACT in "$BUILD_DIR/AsunaTracks.app" "$STAGED_APP"; do
    pluginkit -r "$ARTIFACT/Contents/PlugIns/AsunaTracksMacWidgets.appex" 2>/dev/null || true
    "$LSREGISTER" -u "$ARTIFACT" 2>/dev/null || true
done
"$LSREGISTER" -f "$APP_BUNDLE"
pluginkit -a "$APP_BUNDLE/Contents/PlugIns/AsunaTracksMacWidgets.appex"
rm -rf "$STAGED_APP"
if [[ "$MODE" == --debug ]]; then lldb "$APP_BUNDLE/Contents/MacOS/$APP_NAME"; exit; fi
open -n "$APP_BUNDLE"
case "$MODE" in
--verify) sleep 2; pgrep -x "$APP_NAME" >/dev/null; echo "AsunaTracks is running.";;
--logs|--telemetry) /usr/bin/log stream --info --style compact --predicate 'process == "AsunaTracksMac"';;
esac
