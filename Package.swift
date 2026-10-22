// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AsunaTracksMac",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "AsunaTracksMac", targets: ["AsunaTracksMac"])],
    targets: [.executableTarget(name: "AsunaTracksMac", path: "AsunaTracks",
        exclude: ["Watch", "Widgets", "AsunaTracks.entitlements", "iOS/App-Info.plist", "Shared/BrandAssets.xcassets"],
        sources: ["Shared/Models.swift", "Shared/SiteModels.swift", "Shared/ProfileBio.swift", "Shared/ProgressSnapshot.swift", "Shared/ProgressPublisher.swift", "Shared/WidgetProgressAction.swift", "Shared/ProgressActivityAttributes.swift", "Shared/AsunaLoadingView.swift", "iOS", "macOS"],
        resources: [.copy("Shared/AsunaTracksLogo.png")],
        swiftSettings: [.swiftLanguageMode(.v5)])]
)
