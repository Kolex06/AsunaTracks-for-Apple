# AsunaTracks for Apple

Native apps for **iPhone, iPad, Apple Watch, and Mac**, connected to your existing [AsunaTracks](https://asunatracks.space) account and API.

## Download

| Device | Download | Installation |
| --- | --- | --- |
| Mac | [Mac app ZIP](https://github.com/Kolex06/AsunaTracks-for-Apple/releases/download/v1.0.0-beta.3/AsunaTracks-macOS.zip) | Unzip and move into Applications. Development-signed; not notarized. |
| iPhone and iPad | [Universal unsigned IPA](https://github.com/Kolex06/AsunaTracks-for-Apple/releases/download/v1.0.0-beta.3/AsunaTracks-iPhone-iPad-unsigned.ipa) | Requires your own Apple signing. Includes the companion Watch app. |
| Apple Watch | [Unsigned Watch app ZIP](https://github.com/Kolex06/AsunaTracks-for-Apple/releases/download/v1.0.0-beta.3/AsunaTracks-Apple-Watch-unsigned.zip) | Requires developer signing and installation, normally through Xcode. |
| Source | [Source ZIP](https://github.com/Kolex06/AsunaTracks-for-Apple/archive/refs/heads/main.zip) | Open the Xcode project to build for any supported device. |

**[Installation guide](INSTALL.md) · [All releases](https://github.com/Kolex06/AsunaTracks-for-Apple/releases)**

Requires **macOS 26+, iOS/iPadOS 26+, or watchOS 26+**. iPhone/iPad and Watch downloads are developer packages, not tap-to-install installers. There is no active TestFlight invitation yet.

## Included

- Discover's draggable cover fan, momentum, and horizontal trackpad scrolling on Mac; no Shift key needed. Native For You uses the site's authenticated recommendations, reasons, and genre mixes, with honest fallback/sign-in states. Upcoming, most-tracked, highly rated, recent updates, and popular characters have their own sections.
- Native Browse and separate Top rankings, anime/manga/novel/character search, genres, and automatic pagination. Novels use the dedicated `/public/api/novels` catalog.
- Aligned portrait cards, two-line titles, separate AsunaTracks/MAL scores, rating counts, status colors, and artwork fallbacks.
- Native title details with episodes, characters, related titles, artwork, reviews, favorites, and tracking controls.
- My List with category/status filters, actual update-time sorting, notes, scores, and episode/chapter logging.
- Account colors, custom accent, and intensity from the settings API. Local light/dark/system appearance.
- Native profiles, animated GIF avatars/banners, rich image/GIF/video bios, Community posts/comments/replies and API likes, collections, release schedules, seasons, genres, and announcements. Other sections open in a focused website view on Mac, iPhone, and iPad.
- Branded loaders, Liquid Glass controls, larger-text layouts, VoiceOver labels, and Reduce Motion support.
- An independent Watch app with covers, its own sign-in, and direct API updates while the iPhone app is closed. Internet access is required.

## Widgets and Lock Screen

**Watching**, **Upcoming**, and **My List** each support small, medium, and large widgets on Mac, iPhone, and iPad. Watch and Lock Screen variants support rectangular, circular, and inline formats where available.

- **Watching:** current anime/manga/novel progress.
- **Upcoming:** releases from your own synced list, covering this and next week in local time.
- **My List:** recently updated titles with actual server update times.
- **+1 ep:** interactive buttons on supported Watching/My List layouts mark the next anime episode in the background. Actions check the account and fresh progress first; stale/repeated buttons refresh instead of blindly advancing again.
- Optional pinned progress appears in a Live Activity and Dynamic Island on supported iPhones, with system mirroring to the Watch Smart Stack. Remote changes do not push into a closed app's Live Activity.

Sign in once on each device before adding widgets. Circular/inline widgets remain compact title/progress links. Widget actions need internet access. Passwords are never stored; device-local session cookies stay in the Keychain, and only display snapshots/artwork use the shared container.

## Build

Use **Xcode 27+** and open `AsunaTracks.xcodeproj`.

| Scheme | Platforms |
| --- | --- |
| `AsunaTracks` | iPhone/iPad, companion Watch app, and widgets |
| `AsunaTracksWatch` | Apple Watch |
| `AsunaTracksMac` | Mac and widgets |

Choose your own team for every app/extension target. Update bundle identifiers, app groups, and related identifiers together if needed. The repository includes development identifiers, not signing credentials.

On the configured development Mac, `./script/build_and_run.sh --verify` builds, installs, and opens one copy at `~/Applications/AsunaTracks.app`, unregistering temporary build copies. Debug/log flags are available. `Package.swift` offers a source-only Mac build without widgets.

`./script/package_release.sh 1.0.0-beta.3` prepares every platform's downloads, the installation guide, and SHA-256 checksums under `dist/1.0.0-beta.3`. Portable device packages exclude private provisioning profiles. The Mac package uses development signing and is not notarized.

## Verification and limits

Mac, iOS/iPadOS, and watchOS builds pass. Model/API contract and widget safety tests use sanitized fixtures and a fake API. They cover stale/repeated taps, completed/planned titles, account mismatch, offline failures, and uncertain refreshes. The [UI review](UI_REVIEW.md) records the current visual-testing limits.

Username/password sign-in is supported. Provider-only accounts need password authentication configured on the website. Devices sign in separately. Offline writes are not queued. Full website parity and physical-Watch verification are not claimed.

## TestFlight

TestFlight and App Store distribution are included in the same **US$99/year Apple Developer Program membership**, priced locally where available. Testers do not pay. A GitHub release does not create a TestFlight invitation: signed builds must be uploaded to App Store Connect and approved for external beta testing. TestFlight builds expire after 90 days.

[Apple Developer Program](https://developer.apple.com/programs/) · [TestFlight](https://developer.apple.com/testflight/) · [Beta-testing overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

### Recommendation checks

For You keeps the server’s ranking, recommendation reasons, and genre mixes. It refreshes when account/list signals change and rejects late responses after a switch or logout. General catalog picks are explicitly labeled. To run the intercepted-request regression checks without changing a live account:

```sh
swiftc -module-cache-path /tmp/asuna-test-cache AsunaTracks/Shared/Models.swift AsunaTracks/Shared/SiteModels.swift AsunaTracks/iOS/APIClient.swift AsunaTracks/iOS/RecommendationFeed.swift Tests/RecommendationFeedTests.swift -o /tmp/asuna-recommendation-tests
/tmp/asuna-recommendation-tests Tests/Fixtures/discover-recommendations.json
```

### Build 7 platform parity

Beta 3 includes the same shared media/character grid alignment, Continue Watching/Reading, and personalized For You implementations on iPhone, iPad, and Mac. Continue cards show covers, actual progress, next episode/chapter, remaining count, and a guarded +1 action. Cards adapt to each window width and support snapping and previous/next navigation. Watch uses its own compact continuation list with direct +1 actions and independent API access.

Every release includes `BUILD_MANIFEST.json` with the app/widget bundle versions and supported device families. Packaging rejects mixed versions, missing widgets, private provisioning profiles, and an IPA that does not support both iPhone and iPad.
