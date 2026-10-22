// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AsunaTracksMac",
    // Set iOS's minimum explicitly too, so an accidental iPhone destination does not
    // default to an obsolete iOS version before the Mac-only build guard is shown.
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [.executable(name: "AsunaTracksMac", targets: ["AsunaTracksMac"])],
    targets: [.executableTarget(name: "AsunaTracksMac", path: "AsunaTracks",
        exclude: ["Watch", "Widgets", "AsunaTracks.entitlements", "iOS/App-Info.plist", "Shared/BrandAssets.xcassets",
                  "macOS/AsunaTracksMac-Info.plist", "macOS/AsunaTracksMac.entitlements",
                  "macOS/AsunaTracksMacWidgets-Info.plist", "macOS/AsunaTracksMacWidgets.entitlements"],
        sources: ["Shared/Models.swift", "Shared/SiteModels.swift", "Shared/ProfileBio.swift", "Shared/ProgressSnapshot.swift", "Shared/ProgressPublisher.swift", "Shared/WidgetProgressAction.swift", "Shared/ProgressActivityAttributes.swift", "Shared/AsunaLoadingView.swift", "iOS", "macOS"],
        resources: [.copy("Shared/AsunaTracksLogo.png")],
        swiftSettings: [.swiftLanguageMode(.v5)])]
)
