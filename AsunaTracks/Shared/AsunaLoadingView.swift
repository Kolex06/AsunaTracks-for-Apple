import SwiftUI

/// Shared branded loading state. The logo is bundled so loading never depends on another request.
struct AsunaLoadingView: View {
    var title: String = "Loading…"
    var accent: Color = .pink
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var started = Date()
    private var diameter: CGFloat {
        #if os(watchOS)
        compact ? 20 : 48
        #else
        compact ? 24 : 76
        #endif
    }
    var body: some View {
        VStack(spacing: compact ? 0 : 14) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || isLuminanceReduced)) { context in
                ZStack {
                    Circle().stroke(accent.opacity(0.16), lineWidth: compact ? 2 : 3)
                    Circle().trim(from: 0.05, to: 0.78)
                        .stroke(AngularGradient(colors: [accent.opacity(0.08), accent], center: .center), style: StrokeStyle(lineWidth: compact ? 2 : 3, lineCap: .round))
                        .rotationEffect(.degrees(reduceMotion || isLuminanceReduced ? -90 : context.date.timeIntervalSince(started).truncatingRemainder(dividingBy: 2) * 180))
                    Image.asunaLogo.resizable().scaledToFill()
                        .frame(width: diameter - 10, height: diameter - 10)
                        .clipShape(Circle())
                }.frame(width: diameter, height: diameter)
            }
            if !compact {
                Text(title).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Every remote artwork request has a branded loading state and an explicit retry state.
struct AsunaArtwork: View {
    let path: String?
    var accent: Color = .pink
    var fallbackPaths: [String] = []
    @State private var attempt = 0
    @State private var candidate = 0
    private var candidates: [URL] {
        let paths = ([path].compactMap { $0 } + fallbackPaths).filter { !$0.isEmpty }
        var urls: [URL] = []
        for path in paths {
            guard let url = URL(string: path, relativeTo: URL(string: "https://asunatracks.space"))?.absoluteURL,
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            if !urls.contains(url) { urls.append(url) }
            if url.host == "cdn.myanimelist.net", url.pathExtension.lowercased() == "webp" {
                let jpg = url.deletingPathExtension().appendingPathExtension("jpg")
                if !urls.contains(jpg) { urls.append(jpg) }
            }
        }
        return urls
    }
    private var url: URL? { candidates.indices.contains(candidate) ? candidates[candidate] : nil }
    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped().accessibilityHidden(true)
                }
                else if phase.error != nil {
                    Button { candidate = 0; attempt += 1 } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel("Retry artwork")
                        .task {
                            if candidate + 1 < candidates.count { candidate += 1; attempt += 1 }
                        }
                } else if url != nil {
                    AsunaLoadingView(title: "Loading artwork…", accent: accent, compact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image.asunaLogo.resizable().scaledToFit().padding(12)
                        .opacity(0.35).accessibilityLabel("No artwork available")
                }
            }.id(attempt).frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.background(accent.opacity(0.06)).onChange(of: path) { _, _ in candidate = 0; attempt = 0 }
    }
}

#if !os(watchOS)
/// A loading screen always fills its destination, including Mac split-view details.
struct AsunaLoadingPage: View {
    var title: String = "Loading…"
    @Environment(\.accountTheme) private var theme
    var body: some View {
        AsunaLoadingView(title: title, accent: theme.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AsunaBackdrop() }
    }
}

#endif

// SwiftPM packages keep resources in their module bundle on macOS.
extension Image {
    static var asunaLogo: Image {
        #if os(macOS)
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        if let url = Bundle.main.url(forResource: "AsunaTracksLogo", withExtension: "png") ?? bundle.url(forResource: "AsunaTracksLogo", withExtension: "png"), let image = NSImage(contentsOf: url) { return Image(nsImage: image) }
        return Image(systemName: "sparkles")
        #else
        return Image("AsunaTracksLogo")
        #endif
    }
}
