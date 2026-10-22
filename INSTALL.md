# Install AsunaTracks

Requires macOS 26+, iOS/iPadOS 26+, or watchOS 26+. iPhone and iPad use the same universal app. Apple Watch has an independent app with its own sign-in.

## Mac

Download **AsunaTracks-macOS.zip** from this repository's Releases, unzip it, then move **AsunaTracks.app** into Applications. Replace the existing copy to avoid duplicates. The beta is development-signed and **not notarized**; macOS may block it. If you trust this project, use the system's Privacy & Security → Open Anyway option when offered. Otherwise build from source using Xcode. Do not disable Gatekeeper globally.

## iPhone and iPad

There is no active TestFlight invitation yet. The **AsunaTracks-iPhone-iPad-unsigned.ipa** download is a build for people who can sign it themselves; tapping the download does not install it. It includes the companion Watch app, but third-party signing tools may not preserve or install Watch apps and extensions.

The supported installation route today is Xcode on a Mac:

1. Download this repository's source ZIP and open `AsunaTracks.xcodeproj` in Xcode 27 or newer.
2. Sign in to Xcode Settings → Accounts with your Apple Account.
3. In Signing & Capabilities, choose your team for all app and widget targets. Use your own bundle identifiers, app groups, and matching Keychain group where required; do not reuse the publisher's signing team.
4. Connect and trust your iPhone/iPad, enable Developer Mode, select the **AsunaTracks** scheme and your device, then Run.

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
