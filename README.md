# AsunaTracks for Apple

Native SwiftUI app connected to **https://asunatracks.space**. Requires iOS/iPadOS 26+, watchOS 26+, or macOS 26+.

**Downloads for every platform:** use the [latest release](../../releases/latest) and read the [installation guide](INSTALL.md). Mac has an app ZIP; iPhone/iPad and Apple Watch builds require Apple signing. There is no TestFlight invitation yet. Uses the real AsunaTracks catalog and account service, with no separate database or Jikan account integration.

## Open and run

Open `AsunaTracks.xcodeproj` in Xcode 27 or later. Select the **AsunaTracks** scheme and an iPhone or iPad destination. For a physical device, select your Apple developer team in Signing & Capabilities for **both targets**, and use unique matching bundle identifiers if necessary. The Watch companion identifier must match the iOS app identifier.

The **AsunaTracksWatch** scheme builds the Watch app. Select a Watch simulator or physical Watch, then sign in once inside the Watch app with your existing AsunaTracks username and password. The Watch keeps its own Keychain session and makes direct HTTPS API requests. The iPhone app can remain closed; no iPhone app installation or pairing is required by the app for API operations. Internet access is required for refreshes and writes (the OS can route traffic through a nearby phone, Wi-Fi, or cellular).

## Included

- AsunaTracks navy, pink, and violet design with an interactive cover carousel and horizontal discovery rails.
- Discover covers support continuous dragging and inertial flick-to-spin with wraparound, matching the website's friction curve. Taps/arrows select titles; Reduce Motion skips inertia. Spinning cancels when leaving the screen or backgrounding the app.
- Native Browse uses the dedicated `/public/api/novels` endpoint for novels and light novels, with server pagination, title search, and genre filters. No manga scanning is needed. Browse and Top are separate tabs.
- Genre mix: up to six catalog genres/themes, exact intersection search, and pagination.
- Existing account username/password login and Keychain-protected session cookies. Passwords are never persisted.
- My List with all six tracking statuses, search, and episode/chapter progress.
- Cover-and-banner title details, character galleries, character biographies, voice cast, and linked appearances.
- Improved adaptive media cards with scores, format/year, chapter/episode totals, genres, and account list status.
- Detail screens, notes, favorites, and scoring completed titles.
- Bundled logo loaders for startup, remote artwork, catalog/search/detail requests, pagination, sign-in/out, list refresh, and tracking saves. Determinate progress bars still represent episode/chapter completion.
- Native bottom tabs on iPhone and iPad, with adaptive iPad grids and independent navigation for each section.
- Independent Apple Watch sign-in, in-progress list, cached browsing, and direct next episode/chapter updates.
- Watch library cover thumbnails, larger artwork on progress screens, account-colored backgrounds, and a pinned native Liquid Glass logging action with loading state and success haptics.
- Native Liquid Glass tabs, toolbars, carousel controls, morphing selected genre chips, and floating tracking actions. Glass is reserved for controls; artwork and content remain readable.
- AsunaTracks Dark, Light, and System appearance settings, Dynamic Type, VoiceOver labels, and reduced-motion-aware transitions.
- Account accent preset, custom hex color, and color intensity from `/api/account/settings` apply across iPhone/iPad controls, glass tints, and background glows. Refreshes after login and on returning to the app; the Watch fetches the same account settings directly and caches them for offline display. Signed-out users receive the website's default pink theme.

## API integration

The client uses observed website routes: `/api/me`, `/api/auth/login`, `/api/auth/logout`, `/api/list`, `/api/search`, `/api/media/{type}/{id}`, `/api/media/anime/{id}/episodes/{number}/watched`, `/api/discover/spotlight`, `/api/discover/section`, `/api/genres`, and `/api/discover/mood`.

Progress changes are sent immediately to the server; success is followed by a list refresh. Existing notes, dates, favorites, volume progress and repeat counts are preserved. Watch updates validate the displayed progress against fresh server data before advancing. Mutations are never silently queued offline.

## Current limits

This is the first native client, not every feature from the website. Provider/OAuth login, sign-up, social/community features, moderation, notifications, complications, and streaming are not implemented. Username/password login uses the existing server session flow; authenticated operations require testing with a real account. No live user data was changed during development.

Watch and phone sign in separately. Signing out on one device does not sign out the other. Watch passwords are never persisted or transferred from the phone. Cached list data stays in the Watch app sandbox, is tied to its account, and is cleared on sign-out or session expiry. Offline reads use the cache; updates are never queued or automatically retried. If a write result is uncertain, refresh is required before another update. Provider/OAuth-only accounts need username/password authentication configured on AsunaTracks before using this sign-in flow.

## Verification

Verified during development on October 11–12, 2026 with Xcode 27:

- Combined iOS/iPadOS and embedded Watch simulator build: **passed**.
- Dedicated watchOS simulator build: **passed**.
- Public API/model contract checks: **passed**.
- Independent Watch workflow tests (direct refresh/update, stale progress, offline/session expiry, uncertain writes, cache and logout): **passed**.
- Real URLSession client with intercepted HTTP responses (HTTPS routes, progress POST, refreshed list and 401 handling): **passed**.

iOS 27 runtime is installed. The redesigned app was launched and verified visually with live catalog data on iPhone 17e and iPad Pro 11-inch (M5). The independent Watch app launched on an unpaired watchOS 27 simulator with the iPhone app stopped. Watch sign-in and live authenticated Watch writes still require a real-account/device check; automated workflow tests use a fake API.

Build both targets:

```sh
xcodebuild -project AsunaTracks.xcodeproj -scheme AsunaTracks -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/asunatracks-build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AsunaTracks.xcodeproj -scheme AsunaTracksWatch -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/asunatracks-watch-build CODE_SIGNING_ALLOWED=NO build
```

Run the model/API contract checks against public responses captured during development:

```sh
swiftc AsunaTracks/Shared/Models.swift AsunaTracks/Shared/SiteModels.swift Tests/ModelContractTests.swift -o /tmp/asunatracks-contract-tests
/tmp/asunatracks-contract-tests Tests/Fixtures
```

Before distribution: configure distribution signing; test a real account login/logout and list changes; test independent Watch login and updates with the iPhone app stopped, offline states, large text, VoiceOver, small/large iPhones, and iPad split-screen on devices or configured simulators.

Run the independent Watch workflow tests:

```sh
swiftc -parse-as-library AsunaTracks/Shared/Models.swift AsunaTracks/Shared/ProgressSnapshot.swift AsunaTracks/Shared/ProgressPublisher.swift AsunaTracks/iOS/APIClient.swift AsunaTracks/Watch/WatchStore.swift Tests/WatchStoreTests.swift -o /tmp/asuna-watch-store-tests
/tmp/asuna-watch-store-tests Tests/Fixtures
swiftc -parse-as-library AsunaTracks/Shared/Models.swift AsunaTracks/Shared/ProgressSnapshot.swift AsunaTracks/Shared/ProgressPublisher.swift AsunaTracks/iOS/APIClient.swift AsunaTracks/Watch/WatchStore.swift Tests/WatchTransportTests.swift -o /tmp/asuna-watch-http-tests
/tmp/asuna-watch-http-tests Tests/Fixtures
```

Design reference: [Apple — Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

Navigation: Browse opens the unranked searchable catalog with genres and novels. Top is a separate bottom tab for community rankings of anime, manga, and characters. Search is built into Browse.

## Native macOS app

Requires macOS 26 or later. Run `./script/build_and_run.sh` from this project folder, or use the Codex Run action. The run script installs and opens the single copy at `~/Applications/AsunaTracks.app`; build artifacts are removed from the launcher. Open `AsunaTracks.xcodeproj` and use the `AsunaTracksMac` scheme for the complete Mac app and its widget extension. `Package.swift` remains available for source-only builds without the widget bundle.

The Mac app shares API, account themes, catalog, tracking, and artwork components with iOS. It has a resizable sidebar window, a Settings scene, and Command-R library sync. Sign in on the Mac using your AsunaTracks account. This is a locally signed development build, not a notarized distribution.

`--verify` checks launch, `--debug` opens LLDB, and `--logs`/`--telemetry` stream app logs. The run script uses the native macOS Xcode scheme, embeds the Mac WidgetKit extension, and preserves development signing and shared-container entitlements. Apple Development signing is required.

## Profile and website sections

Mac sidebar and the mobile Profile tab show the signed-in account avatar, display name, username, bio, banner (when provided by the API), and library counts. Watch has a compact avatar/name header. The spinning refresh/sync controls were removed from the Discover logo toolbar; Mac Command-R still syncs the library.

Collections, community, messages, schedule, seasons, genres, Wrapped, playback progress, edits, map, AI, streaming, AMVs, store, announcements, integrations, and website settings are accessible through live website-backed screens on iPhone, iPad, and Mac. They are not native reimplementations. Browse and Profile link to all sections; Mac exposes them in the sidebar. Website screens seed an account-scoped in-memory WebKit cookie store from the native AsunaTracks session, replace that shared website session when the native account changes, and send external main-frame links to the system browser. Website-only sign-ins are not imported into native tracking. Full web sections are not available on watchOS.

## Native API sections and Mac input

Collections and Schedule now use SwiftUI screens with API data on Mac, iPhone, and iPad. Collections includes search, Featured/Newest/Following/Mine filters, ordered title lists, notes, read-only comments, and explicit Like/Follow actions. Collection editing, collaboration, and posting comments remain available in the focused website view. Schedule supports ISO week navigation, local times, Sub/Dub/Raw filters, in-list filtering, cached-data warnings, and links to native title details.

Other website sections use a focused layout with duplicate site navigation and footer hidden, system typography, and larger controls. Page options can reveal the site menus, including website-only notification controls. Privacy/consent UI is preserved.

Discover keeps the original fan carousel across devices. On Mac it supports press-and-drag and horizontal trackpad scrolling with momentum and snapping; Shift is not required. Vertical gestures continue scrolling the page. Other horizontal rails use native scrolling. Command-1 through Command-5 navigate within the focused Mac window; Command-R syncs the library.

Contract checks now compile with both `AsunaTracks/Shared/Models.swift` and `AsunaTracks/Shared/SiteModels.swift`.

## Widgets and pinned progress

The iOS app includes a WidgetKit extension with small, medium, large, and Lock Screen widgets. The Watch app includes circular, inline, and rectangular complications; the rectangular widget also works in the Smart Stack. Add **AsunaTracks / Watching, Upcoming, or My List** from the system widget gallery or Watch face editor after installing and signing in on that device.

Open an in-progress title and choose **Pin progress to Lock Screen** for a Live Activity and Dynamic Island progress display on supported devices. Its compact presentation supports Apple's Live Activity mirroring to the Watch Smart Stack. The pin is optional and can be ended from the same title. It ends when the title stops being in progress or the account signs out.

Widgets share only display snapshots and public cover images through `group.space.asunatracks.apple`; passwords are never stored, and device-local session cookies stay in the Keychain. iPhone/iPad and Watch share their session only with their own widget extension through a Keychain access group. Mac widget actions run in the app process using its existing Keychain sign-in. Each device syncs its own snapshot when its app refreshes or changes progress. The Home Screen widget shows its sync age; stale Live Activities ask you to refresh. This version does not register server push tokens, so changes made elsewhere do not push into a closed phone app's Live Activity. Refresh/open that device's app to sync them.

The native Community page uses the public users and activity APIs. Profiles include public lists, favorites, collection links, statistics, follow controls, and the site's GIF/image/video bio syntax. Profile markup is parsed into a restricted fragment; arbitrary HTML and scripts are escaped. Wide screens use an About column beside the dashboard. Browse uses automatic pagination and the documented public character API.

The rich bio and widget snapshot checks can be run with:

```sh
swiftc AsunaTracks/Shared/ProfileBio.swift AsunaTracks/Shared/ProgressSnapshot.swift Tests/NativeFeaturesTests.swift -o /tmp/asuna-native-features-tests
/tmp/asuna-native-features-tests
```

Debug builds accept `--preview-progress` to inspect a widget snapshot and a Live Activity using a public title and local preview progress. No account list writes occur. This screen is excluded from Release builds; a normal launch restores the signed-in or signed-out flow.

## Native Mac widgets, account preferences, and page polish

The `AsunaTracksMac` Xcode app target embeds `AsunaTracksMacWidgets`, supporting small, medium, and large widgets on the desktop and in Notification Center. The Mac app and widget share display snapshots and cover images through `B6NP2879G2.space.asunatracks.apple`; phone and Watch retain their existing device-local app group. Each app must sync its own account before its widgets show library data. Widget links open the native title page or library.

Mac account colors, custom accents, and intensity refresh on activation and every 30 seconds while active, after account settings closes, and with Command-R. The Settings window shares the same tint and local light/dark preference. Account privacy and explicit-catalog preferences are read from the settings API and displayed in Account. Catalog destinations reset when the signed-in account or explicit-content preference changes; filtering and privacy enforcement remain server-side. Profile and account preferences can be edited through the authenticated settings destination. Local light/dark mode is a device preference, separate from the site's accent palette.

Login now fills the destination with a readable centered form on large screens. Initial loading states have space to breathe, and website destinations and Mac startup use a full-canvas branded loading state. Native media pages include episodes, characters, relations, artwork viewing, reviews, separate AsunaTracks/MAL scores, and a tracking dock. Rich bios support `webm-sound(https://example.com/clip.webm)` with an explicit Play with sound control; ordinary `webm(...)` starts muted when played.

The iPhone/iPad and Watch targets use the shared `AppIcon` asset set, with opaque 1024-pixel artwork derived from the existing AsunaTracks logo. Xcode generates all platform sizes. To regenerate after updating the brand image:

```sh
swift script/generate_app_icon.swift AsunaTracks/Shared/AsunaTracksLogo.png AsunaTracks/Shared/BrandAssets.xcassets/AppIcon.appiconset/AppIcon.png
```

## Watching, Upcoming, and My List widgets

The widget gallery now offers three separate widgets. **Watching** shows current anime/manga/novel progress. **Upcoming** checks this and next week's public schedule and shows only future releases matching titles in your own synced list, with episode numbers, release type, and local release times. **My List** shows the most recently updated titles with their server update times; its footer separately shows when the device last synced. Unknown update times are labeled rather than replaced with the current time.

All three support small, medium, and large widgets on iPhone, iPad, and Mac. Watch and Lock Screen versions support circular, rectangular, and inline families. Widgets share account colors, real covers, branded artwork fallbacks, and title deep links. Schedule snapshots remove aired episodes at their scheduled times and preserve a marked cached schedule on network failure. Preview snapshots read cached artwork without waiting for network requests. A device must open/sync its app to update account membership and progress; schedule requests use public data and no credentials. Watching and My List widgets offer a background **+1 ep** action for active anime; it re-reads the authenticated account and list, rejects stale progress, and refreshes only from confirmed server data.

Run the schedule and snapshot checks:

```sh
swiftc AsunaTracks/Shared/ProgressSnapshot.swift AsunaTracks/Widgets/WidgetSchedule.swift Tests/WidgetScheduleTests.swift -o /tmp/asuna-widget-tests
/tmp/asuna-widget-tests
```

## Build release downloads

Run `./script/package_release.sh 1.0.0-beta.1` on a Mac with Xcode and a development signing identity. It produces a Mac app ZIP, unsigned universal iPhone/iPad IPA (with companion Watch app), unsigned Watch app ZIP, installation guide, and SHA-256 checksums under `dist/1.0.0-beta.1`. Device packages contain no provisioning profiles. No credentials or local app data are packaged.

Widget action safety checks use an in-memory fake API and do not modify an account:

```sh
swiftc -parse-as-library -module-cache-path /tmp/asuna-test-cache AsunaTracks/Shared/Models.swift AsunaTracks/Shared/ProgressSnapshot.swift AsunaTracks/Shared/ProgressPublisher.swift AsunaTracks/Shared/WidgetProgressAction.swift AsunaTracks/iOS/APIClient.swift Tests/WidgetProgressActionTests.swift -o /tmp/asuna-widget-action-tests
/tmp/asuna-widget-action-tests
```
