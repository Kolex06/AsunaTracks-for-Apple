# Install AsunaTracks

Requires macOS 26+, iOS/iPadOS 26+, or watchOS 26+. iPhone and iPad use the same universal app. Apple Watch has an independent app with its own sign-in.

## Mac

Download **AsunaTracks-macOS.zip** from this repository's Releases, unzip it, then move **AsunaTracks.app** into Applications. Replace the existing copy to avoid duplicates. The beta is development-signed and **not notarized**; macOS may block it. If you trust this project, use the system's Privacy & Security → Open Anyway option when offered. Otherwise build from source using Xcode. Do not disable Gatekeeper globally.

## iPhone and iPad

There is no active TestFlight invitation yet. The **AsunaTracks-iPhone-iPad-unsigned.ipa** download is a build for people who can sign it themselves; tapping the download does not install it. It includes the companion Watch app, but third-party signing tools may not preserve or install Watch apps and extensions.

The supported installation route today is Xcode on a Mac:

1. Download this repository's source ZIP and open `AsunaTracks.xcodeproj` in Xcode 27 or newer.
2. Sign in to Xcode Settings → Accounts with your Apple Account.
3. In Terminal, change to the downloaded source folder and run the setup helper below with **your own** team ID and unique bundle ID. Then choose that team in Xcode for the app and extension targets.
4. Connect and trust your iPhone/iPad, enable Developer Mode, select the **AsunaTracks** scheme and your device, then Run.

### Configure your signing settings together

Find your team ID in Xcode's signing settings or your Apple Developer account. Replace `YOURTEAMID` and `com.example.asunatracks` with your own values:

```sh
python3 script/configure_signing.py --team YOURTEAMID --bundle-id com.example.asunatracks
python3 script/configure_signing.py --check
```

The helper updates both build configurations, all six targets, App Group entitlements, the runtime widget cache and shared session groups. It checks for conflicting manual target overrides before writing anything, and prints the groups to provision. It is safe to rerun with the same settings. Review the changes with `git diff` when working in a Git checkout.

**Apple still needs to allow those capabilities for your team.** Enable the printed App Groups for the corresponding app and widget identifiers in your developer account/Signing & Capabilities, and let Xcode generate matching profiles. This helper cannot register identifiers, grant capabilities or remove Personal Team restrictions. It never asks for your Apple password.

Do not change only the team or the main app ID while leaving the original sharing groups in place. If you already customized targets individually and the helper reports conflicting overrides, preserve your local work and use a fresh source download for setup.

A free Personal Team can install development builds on its own devices, subject to Apple's limitations and short-lived signing. Some capabilities require a paid membership. Rebuilding from Xcode renews the development installation.

## Building from source: choose the Xcode project

Open **AsunaTracks.xcodeproj**, not `Package.swift` or the downloaded folder. Use Xcode 27+ with the matching Apple SDKs. Select **AsunaTracksMac → My Mac** for Mac, **AsunaTracks → your iPhone/iPad** for mobile, or **AsunaTracksWatch → your Watch**. The apps require OS 26 or newer; lowering the deployment target does not add compatibility with older systems.

`Package.swift` is an optional Mac-only executable build without widgets. In Terminal, use `swift build`; it is not the installation route for iPhone, iPad, or Watch.

If Xcode reports `Invalid redeclaration` of `asunaGlassButtonStyle`, `asunaProminentButtonStyle`, or `AsunaGlassContainer`, start with a fresh source ZIP in a new folder and open its `.xcodeproj`. Those compatibility helpers are not part of the official source; adding copies to several files creates duplicate declarations. Keep your existing folder until any local changes are preserved. After switching to the correct project, use Product → Clean Build Folder if diagnostics from the previous build remain.

## Apple Watch

Use the same Xcode project, select **AsunaTracksWatch**, choose your paired Watch, enable Watch Developer Mode, and Run. The Watch app keeps its own sign-in and talks directly to AsunaTracks; your iPhone app can stay closed. Internet access is still required to update the list.

**AsunaTracks-Apple-Watch-unsigned.zip** contains the watchOS app and widget extension for developer signing/install workflows. It is not a standalone installer you can open on the Watch. For ordinary users, a future TestFlight invitation will be the simplest option.

## Widgets

Open the app and sign in once on each device, then add **Watching**, **Upcoming**, or **My List** from its widget gallery. Watching and My List include a **+1 ep** button for active anime. The button reads your current account/list and marks the next episode through the API; stale buttons refresh rather than blindly logging another episode. Your passwords are never stored. Device-local session cookies stay in the Keychain.

## TestFlight and App Store

The Apple Developer Program is US$99 per year, charged in local currency where available. One membership includes both TestFlight and App Store distribution; there is no separate TestFlight subscription and testers do not pay to test. TestFlight requires uploading signed builds to App Store Connect. External testing requires Apple's beta review; each build can be tested for up to 90 days.

- [Apple Developer Program](https://developer.apple.com/programs/)
- [TestFlight](https://developer.apple.com/testflight/)
- [TestFlight overview and build expiry](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

No App Store or TestFlight availability is implied by a GitHub release.

## Fix: InvalidCompanionAppBundleIdentifier

This error means the Watch app still names a different iPhone app as its companion. For example, an iPhone ID of `com.example.asunatracks` must have a Watch `WKCompanionAppBundleIdentifier` of exactly `com.example.asunatracks`.

For an existing checkout where the iPhone target was renamed manually, set the **AsunaTracksWatch** target's Build Settings → `INFOPLIST_KEY_WKCompanionAppBundleIdentifier` (shown as **WKCompanionAppBundleIdentifier**) to the iPhone target's exact Bundle Identifier, for both Debug and Release. Use matching nested IDs:

| Target / key | Example |
| --- | --- |
| AsunaTracks | `com.example.asunatracks` |
| AsunaTracksWidgets | `com.example.asunatracks.widgets` |
| AsunaTracksWatch | `com.example.asunatracks.watchkitapp` |
| Watch companion key | `com.example.asunatracks` |
| AsunaTracksWatchWidgets | `com.example.asunatracks.watchkitapp.widgets` |

Then use Product → Clean Build Folder and Run again. On a fresh download of the updated project, change only the project-level `ASUNATRACKS_APP_BUNDLE_ID` setting instead of editing each target independently. This fixes identifier matching; signing capabilities must still be configured for the chosen team.
