import SwiftUI
import ImageIO

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
    var animateLoading = true
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
            if let url, ["gif", "apng"].contains(url.pathExtension.lowercased()) {
                AnimatedArtwork(url: url, accent: accent)
            } else {
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
                        if animateLoading {
                            AsunaLoadingView(title: "Loading artwork…", accent: accent, compact: true)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Image.asunaLogo.resizable().scaledToFit().padding(4)
                                .opacity(0.35).accessibilityLabel("Loading profile picture")
                        }
                    } else {
                        Image.asunaLogo.resizable().scaledToFit().padding(12)
                            .opacity(0.35).accessibilityLabel("No artwork available")
                    }
                }.id(attempt).frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
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


/// ImageIO preserves GIF frame delays; decoding and bounded caching stay off the UI actor.
nonisolated private final class AnimatedArtworkFrames: @unchecked Sendable {
    let images: [CGImage]
    let frameEnds: [Double]
    let duration: Double
    let cost: Int
    init(images: [CGImage], frameEnds: [Double], cost: Int) {
        self.images = images; self.frameEnds = frameEnds
        duration = frameEnds.last ?? 0.1; self.cost = cost
    }
}
private actor AnimatedArtworkCache {
    static let shared = AnimatedArtworkCache()
    private let cache: NSCache<NSString, AnimatedArtworkFrames> = {
        let cache = NSCache<NSString, AnimatedArtworkFrames>(); cache.totalCostLimit = 96 * 1024 * 1024; return cache
    }()
    private var pending: [URL: Task<AnimatedArtworkFrames, Error>] = [:]
    func frames(for url: URL) async throws -> AnimatedArtworkFrames {
        if let frames = cache.object(forKey: url.absoluteString as NSString) { return frames }
        if let task = pending[url] { return try await task.value }
        let task = Task { try await Self.decode(url) }
        pending[url] = task
        defer { pending[url] = nil }
        let frames = try await task.value
        cache.setObject(frames, forKey: url.absoluteString as NSString, cost: frames.cost)
        return frames
    }
    private static func decode(_ url: URL) async throws -> AnimatedArtworkFrames {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= 24 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw URLError(.cannotDecodeContentData) }
        let count = CGImageSourceGetCount(source)
        guard count > 0 && count <= 600 else { throw URLError(.cannotDecodeContentData) }
        // Bound decoded memory per animation, including large animated profile banners.
        let pixels = min(900, max(64, Int(sqrt(Double(32 * 1024 * 1024 / 4 / count)))))
        var images: [CGImage] = [], ends: [Double] = [], duration = 0.0, cost = 0
        for index in 0..<count {
            try Task.checkCancellation()
            let image: CGImage? = autoreleasepool {
                CGImageSourceCreateThumbnailAtIndex(source, index, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary)
            }
            guard let image else { throw URLError(.cannotDecodeContentData) }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
                ?? (png?[kCGImagePropertyAPNGDelayTime] as? Double) ?? 0.1
            duration += delay < 0.02 ? 0.1 : delay
            images.append(image); ends.append(duration); cost += image.bytesPerRow * image.height
        }
        return AnimatedArtworkFrames(images: images, frameEnds: ends, cost: cost)
    }
}
private struct AnimatedArtwork: View {
    let url: URL
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @State private var frames: AnimatedArtworkFrames?
    @State private var started = Date()
    @State private var failed = false
    @State private var attempt = 0
    var body: some View {
        GeometryReader { geometry in
            if let frames {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || luminanceReduced || frames.images.count == 1)) { context in
                    let time = max(0, context.date.timeIntervalSince(started)).truncatingRemainder(dividingBy: frames.duration)
                    let index = reduceMotion || luminanceReduced ? 0 : (frames.frameEnds.firstIndex { time < $0 } ?? 0)
                    Image(decorative: frames.images[index], scale: 1).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            } else if failed {
                Button { attempt += 1 } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                }.buttonStyle(.plain).accessibilityLabel("Retry animated image")
            } else {
                Image.asunaLogo.resizable().scaledToFit().padding(4).opacity(0.35)
            }
        }.clipped().task(id: "\(url.absoluteString):\(attempt)") {
            frames = nil; failed = false
            do {
                let loaded = try await AnimatedArtworkCache.shared.frames(for: url)
                try Task.checkCancellation(); started = Date(); frames = loaded
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
