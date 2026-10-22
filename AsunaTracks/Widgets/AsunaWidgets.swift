import SwiftUI
import WidgetKit
import ImageIO
import AppIntents
#if os(iOS)
import ActivityKit
#endif

enum StoryWidgetMode: String, CaseIterable {
    case watching, upcoming, list
    var title: String { switch self { case .watching: "Watching"; case .upcoming: "Upcoming"; case .list: "My List" } }
    var symbol: String { switch self { case .watching: "play.rectangle.fill"; case .upcoming: "calendar"; case .list: "rectangle.stack.fill" } }
    var kind: String { self == .watching ? "AsunaTracksContinue" : "AsunaTracks" + rawValue.capitalized }
}
struct ContinueEntry: TimelineEntry {
    let date: Date
    let snapshot: ProgressSnapshot
    var covers: [String: Data] = [:]
    var mode: StoryWidgetMode = .watching
    var notice: String? = nil
}
struct ContinueProvider: TimelineProvider {
    var mode: StoryWidgetMode = .watching
    func placeholder(in context: Context) -> ContinueEntry { preview() }
    func getSnapshot(in context: Context, completion: @escaping (ContinueEntry) -> Void) {
        let cached = ProgressCache.read()
        guard cached.username != nil else { completion(context.isPreview ? preview() : .init(date: .now, snapshot: cached, mode: mode)); return }
        var items = mode == .list ? cached.listItems ?? cached.items : cached.items
        if mode == .upcoming {
            items = UpcomingWidgetSchedule.cachedItems(libraryIDs: Set(cached.libraryIDs ?? (cached.listItems ?? cached.items).map(\.id))) ?? []
        }
        var covers: [String: Data] = [:]
        for item in items.prefix(6) {
            if let file = ProgressCache.imageFile(for: item), let data = try? Data(contentsOf: file) { covers[item.id] = data }
        }
        completion(.init(date: .now, snapshot: .init(username: cached.username, updatedAt: cached.updatedAt,
            items: items, accentRGB: cached.accentRGB, actionNotice: cached.actionNotice), covers: covers, mode: mode))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueEntry>) -> Void) {
        Task {
            let current = await entry(preview: false)
            var entries = [current]
            // Remove aired episodes at their scheduled times without waiting for a network refresh.
            if mode == .upcoming {
                for date in Array(Set(current.snapshot.items.compactMap(\.releaseDate))).sorted().prefix(8) where date > .now {
                    var snapshot = current.snapshot
                    snapshot = .init(username: snapshot.username, updatedAt: snapshot.updatedAt,
                        items: snapshot.items.filter { ($0.releaseDate ?? .distantPast) > date }, accentRGB: snapshot.accentRGB, listItems: snapshot.listItems)
                    entries.append(.init(date: date.addingTimeInterval(1), snapshot: snapshot, covers: current.covers, mode: mode, notice: current.notice))
                }
            }
            completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(1800))))
        }
    }
    private func entry(preview: Bool) async -> ContinueEntry {
        let cached = ProgressCache.read()
        if preview && cached.username == nil { return self.preview() }
        var items = mode == .list ? cached.listItems ?? cached.items : cached.items
        var notice: String?
        if mode == .upcoming {
            if cached.username != nil {
                let result = await UpcomingWidgetSchedule.load(libraryIDs: Set(cached.libraryIDs ?? (cached.listItems ?? cached.items).map(\.id)))
                items = result.items; notice = result.notice
            } else { items = [] }
        }
        var covers: [String: Data] = [:]
        await withTaskGroup(of: (String, Data?).self) { group in
            for item in items.prefix(6) { group.addTask { (item.id, await ProgressCache.cacheCover(item)) } }
            for await (id, data) in group { if let data { covers[id] = data } }
        }
        guard ProgressCache.read().username == cached.username else { return .init(date: .now, snapshot: .empty, mode: mode) }
        return .init(date: .now, snapshot: .init(username: cached.username, updatedAt: cached.updatedAt,
            items: items, accentRGB: cached.accentRGB, listItems: cached.listItems, actionNotice: cached.actionNotice), covers: covers, mode: mode, notice: notice)
    }
    private func preview() -> ContinueEntry {
        let now = Date()
        let items = [
            ProgressItem(id: "anime:32", mediaID: 32, mediaType: "anime", title: "Sword Art Online", imageURL: nil, progress: 3, total: 25, unit: "episodes", status: "watching", lastUpdated: now.addingTimeInterval(-1800), releaseDate: mode == .upcoming ? now.addingTimeInterval(3600) : nil, episodeNumber: 4),
            ProgressItem(id: "anime:71", mediaID: 71, mediaType: "anime", title: "Sword Art Online II", imageURL: nil, progress: 1, total: 24, unit: "episodes", status: "planning", lastUpdated: now.addingTimeInterval(-7200), releaseDate: mode == .upcoming ? now.addingTimeInterval(86400) : nil, episodeNumber: 2)
        ]
        return .init(date: now, snapshot: .init(username: "Preview", updatedAt: now, items: items), mode: mode)
    }
}

struct ContinueWidget: Widget {
    var mode: StoryWidgetMode = .watching
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: mode.kind, provider: ContinueProvider(mode: mode)) { entry in
            ContinueWidgetView(entry: entry).containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.025, green: 0.04, blue: 0.09), widgetAccent(entry.snapshot.accentRGB).opacity(0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .configurationDisplayName(mode.title)
        .description(mode == .upcoming ? "The next episode releases from your own list, in your local time." : mode == .list ? "Your most recently updated titles, with progress and update times." : "Pick up your anime, manga, and novels with cover art and progress.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #elseif os(macOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
        #endif
    }
}
struct ContinueWidgetView: View {
    let entry: ContinueEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var systemFamily
    private var family: WidgetFamily { familyOverride ?? systemFamily }
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var accent: Color { widgetAccent(entry.snapshot.accentRGB) }
    private var ink: Color { renderingMode == .fullColor ? .white : .primary }
    private var first: ProgressItem? { entry.snapshot.items.first }
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(first.map { inlineText($0) } ?? "\(entry.mode.title) · Open to sync", systemImage: entry.mode.symbol)
            case .accessoryCircular:
                if let first {
                    if entry.mode == .upcoming, let date = first.releaseDate {
                        VStack(spacing: 1) {
                            Image(systemName: "calendar").widgetAccentable()
                            Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 8))
                            Text(date, style: .time).font(.caption2.bold()).minimumScaleFactor(0.65).lineLimit(1)
                        }
                    } else if entry.mode == .list {
                        VStack(spacing: 2) {
                            Image(systemName: "clock.arrow.circlepath").widgetAccentable()
                            if let date = first.lastUpdated { Text(date, style: .relative).font(.caption2).lineLimit(1).minimumScaleFactor(0.5) }
                            else { Text("Unknown").font(.system(size: 8)) }
                        }.accessibilityLabel("Last update for \(first.title)")
                    } else if let fraction = first.fraction {
                        Gauge(value: fraction) { Image(systemName: entry.mode.symbol) } currentValueLabel: { Text("\(max(0, first.progress))").font(.caption.bold()) }.gaugeStyle(.accessoryCircular).tint(accent)
                    } else { VStack { Image(systemName: entry.mode.symbol); Text("\(max(0, first.progress))").font(.caption.bold()) } }
                } else { Image(systemName: entry.mode.symbol).accessibilityLabel("Open AsunaTracks to sync") }
            case .accessoryRectangular:
                if let first { storyRow(first, compact: true) }
                else { VStack(alignment: .leading, spacing: 3) { Text(entry.mode.title).font(.headline); Text(emptyText).font(.caption).lineLimit(2) } }
            default:
                #if os(iOS) || os(macOS)
                homeContent
                #else
                Text(entry.mode.title)
                #endif
            }
        }.widgetURL(first?.url ?? URL(string: "asunatracks://library")!)
    }
    #if os(iOS) || os(macOS)
    private var homeContent: some View {
        GeometryReader { geometry in
            let small = family == .systemSmall
            let large = family == .systemLarge
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: entry.mode.symbol).foregroundStyle(accent).widgetAccentable()
                    Text(entry.mode.title).font(.caption.bold())
                    Spacer(minLength: 0)
                    widgetBrandLogo.resizable().renderingMode(.original).widgetAccentedRenderingMode(.fullColor).scaledToFit().frame(width: 21, height: 21).accessibilityHidden(true)
                }
                if let first {
                    if small {
                        HStack(alignment: .top, spacing: 10) {
                            cover(first).frame(width: geometry.size.width * 0.31, height: 56).clipShape(.rect(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(first.title).font(.subheadline.bold()).lineLimit(3).minimumScaleFactor(0.8)
                                if entry.mode == .upcoming { Text(entry.notice == nil ? "Next release" : "Cached schedule").font(.caption2).foregroundStyle(accent) }
                                else { Text(first.statusLabel).font(.caption2).foregroundStyle(accent) }
                            }
                        }
                        Spacer(minLength: 0)
                        details(first, compact: true)
                    } else if large {
                        ForEach(Array(entry.snapshot.items.prefix(3))) { item in
                            HStack(spacing: 6) {
                                Link(destination: item.url) { storyRow(item, compact: false) }
                                advanceButton(item)
                            }.padding(6).background(.white.opacity(0.055), in: .rect(cornerRadius: 12))
                        }
                        Spacer(minLength: 0)
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            cover(first).frame(width: large ? 78 : 66, height: large ? 108 : 91).clipShape(.rect(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(first.title).font(large ? .title3.bold() : .headline).lineLimit(2)
                                details(first, compact: !large)
                                if !large, let next = entry.snapshot.items.dropFirst().first {
                                    Text("\(entry.mode == .list ? "Also updated" : "Next") · \(next.title)").font(.system(size: 10)).lineLimit(1).opacity(0.65)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Spacer(minLength: 0)
                    }
                    if let notice = entry.snapshot.actionNotice, entry.mode != .upcoming {
                        Text(notice).font(.system(size: 9)).lineLimit(2).foregroundStyle(accent)
                    } else if !small {
                        HStack(spacing: 4) {
                            if entry.mode == .upcoming { Text(entry.notice == nil ? "From your list · This & next week" : "Cached schedule · From your list") }
                            else { Text("Synced"); Text(entry.snapshot.updatedAt, style: .relative) }
                            Spacer(minLength: 4)
                            Link(destination: URL(string: "asunatracks://library")!) { Image(systemName: "arrow.up.right") }
                        }.font(.system(size: 9)).opacity(0.55)
                    }
                } else {
                    Spacer(minLength: 0)
                    Image(systemName: entry.mode.symbol).font(small ? .title2 : .largeTitle).foregroundStyle(accent)
                    Text(emptyText).font(small ? .subheadline.bold() : .headline).lineLimit(2).minimumScaleFactor(0.85)
                    Text(entry.notice ?? (entry.snapshot.username == nil ? "Sign in to AsunaTracks on this device." : entry.mode == .upcoming ? "This and next week · From your list" : "Open the app to refresh your list.")).font(.caption).opacity(0.65).lineLimit(small ? 2 : 3)
                    Spacer(minLength: 0)
                }
            }.foregroundStyle(ink).padding(14).frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }
    #endif
    @ViewBuilder private func advanceButton(_ item: ProgressItem) -> some View {
        if entry.mode != .upcoming, item.mediaType == "anime",
           ["watching", "rewatching"].contains(item.status),
           item.total <= 0 || item.progress < item.total,
           let username = entry.snapshot.username {
            Button(intent: AdvanceEpisodeIntent(item: item, username: username)) {
                Text("+1 ep").font(.caption.bold().monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(accent.opacity(0.22), in: Capsule())
            }.buttonStyle(.plain).foregroundStyle(ink)
                .accessibilityLabel("Mark episode \(item.progress + 1) of \(item.title) watched")
        }
    }
    private var emptyText: String {
        if entry.notice != nil { return "Schedule unavailable" }
        if entry.snapshot.username == nil { return "Your stories, at a glance" }
        switch entry.mode { case .upcoming: return "Nothing airing soon"; case .watching: return "Ready for a new story?"; case .list: return "Your list starts here" }
    }
    private func storyRow(_ item: ProgressItem, compact: Bool) -> some View {
        HStack(spacing: 9) {
            cover(item).frame(width: compact ? 32 : 42, height: compact ? 46 : 56).clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(compact ? .caption.bold() : .subheadline.bold()).lineLimit(compact ? 1 : 2)
                details(item, compact: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            #if !os(macOS)
            if family == .accessoryRectangular { advanceButton(item) }
            #endif
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private func details(_ item: ProgressItem, compact: Bool) -> some View {
        if entry.mode == .upcoming {
            HStack(spacing: 3) {
                if entry.notice != nil { Image(systemName: "clock.arrow.circlepath").accessibilityLabel("Cached schedule") }
                Text(releaseText(item)).lineLimit(1).minimumScaleFactor(0.75)
            }.font(compact ? .caption2.bold() : .subheadline.bold()).foregroundStyle(accent)
            Text(episodeText(item)).font(.system(size: compact ? 10 : 12)).opacity(0.7)
        } else {
            HStack(spacing: 4) {
                if entry.mode == .list { Circle().fill(statusColor(item.status)).frame(width: 5, height: 5).accessibilityLabel(item.statusLabel) }
                Text(item.progressLabel).font(.caption.bold().monospacedDigit())
                #if os(iOS) || os(macOS)
                if family != .systemSmall { Text(item.unit).font(.system(size: 10)).opacity(0.65) }
                if family == .systemSmall || family == .systemMedium {
                    Spacer(minLength: 2)
                    advanceButton(item)
                }
                #else
                Text(item.unit).font(.system(size: 10)).opacity(0.65)
                #endif
            }.lineLimit(1).minimumScaleFactor(0.75)
            if let fraction = item.fraction { GeometryReader { proxy in
                ZStack(alignment: .leading) { Capsule().fill(accent.opacity(0.18)); Capsule().fill(accent).frame(width: proxy.size.width * fraction) }
            }.frame(height: 4).widgetAccentable() }
            if entry.mode == .list {
                if let date = item.lastUpdated { (Text("Updated ") + Text(date, style: .relative) + Text(" ago")).font(.system(size: 9)).opacity(0.65).lineLimit(1) }
                else { Text("\(item.statusLabel) · Update time unavailable").font(.system(size: 9)).opacity(0.65).lineLimit(1) }
            }
        }
    }
    private func inlineText(_ item: ProgressItem) -> String {
        if entry.mode == .upcoming { return "\(item.title) · \(releaseText(item))" }
        if entry.mode == .list {
            guard let date = item.lastUpdated else { return "\(item.title) · Update time unknown" }
            let formatter = RelativeDateTimeFormatter(); formatter.unitsStyle = .abbreviated
            return "\(item.title) · Updated \(formatter.localizedString(for: date, relativeTo: entry.date))"
        }
        return "\(item.title) · \(item.progressLabel)"
    }
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "completed", "rewatched", "reread": Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
        case "planning": Color(red: 234 / 255, green: 179 / 255, blue: 8 / 255)
        case "dropped": Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
        case "paused": Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
        default: Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)
        }
    }
    private func releaseText(_ item: ProgressItem) -> String {
        guard let date = item.releaseDate else { return "Time to be announced" }
        let day = Calendar.current.isDateInToday(date) ? "Today" : Calendar.current.isDateInTomorrow(date) ? "Tomorrow" : date.formatted(.dateTime.weekday(.abbreviated))
        return "\(day) · \(date.formatted(date: .omitted, time: .shortened))"
    }
    private func episodeText(_ item: ProgressItem) -> String {
        [item.episodeNumber.map { "Episode \($0.formatted(.number.precision(.fractionLength(0...1))))" }, item.airType?.uppercased()].compactMap { $0 }.joined(separator: " · ")
    }
    @ViewBuilder private func cover(_ item: ProgressItem) -> some View {
        #if os(macOS)
        if let data = entry.covers[item.id], let image = widgetThumbnail(data) { Image(nsImage: NSImage(cgImage: image, size: .zero)).resizable().renderingMode(.original).widgetAccentedRenderingMode(.fullColor).scaledToFill() }
        else { fallbackCover }
        #else
        if let data = entry.covers[item.id], let image = widgetThumbnail(data) { Image(uiImage: UIImage(cgImage: image)).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill() }
        else { fallbackCover }
        #endif
    }
    private var fallbackCover: some View {
        widgetBrandLogo.resizable().renderingMode(.original).widgetAccentedRenderingMode(.fullColor).scaledToFit().padding(3).frame(maxWidth: .infinity, maxHeight: .infinity).background(accent.opacity(0.12))
    }
}

#if os(iOS)
struct PinnedProgressActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProgressActivityAttributes.self) { context in
            HStack(spacing: 14) {
                activityCover(context.attributes.item).frame(width: 44, height: 64).clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text("AsunaTracks").font(.caption.bold()).foregroundStyle(widgetAccent(context.attributes.item.accentRGB))
                    Text(context.attributes.item.title).font(.headline).lineLimit(2)
                    Text("\(context.state.progress) / \(context.state.total > 0 ? String(context.state.total) : "?") \(context.attributes.item.unit)").font(.caption).foregroundStyle(.secondary)
                    if context.state.total > 0 { ProgressView(value: Double(min(context.state.progress, context.state.total)), total: Double(context.state.total)).tint(widgetAccent(context.attributes.item.accentRGB)) }
                    if context.isStale { Text("Open AsunaTracks to refresh").font(.caption2).foregroundStyle(.secondary) }
                }
            }.padding(16).activityBackgroundTint(.black.opacity(0.85)).activitySystemActionForegroundColor(widgetAccent(context.attributes.item.accentRGB))
                .widgetURL(context.attributes.item.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { activityCover(context.attributes.item).frame(width: 34, height: 48).clipShape(.rect(cornerRadius: 5)) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.progress)/\(context.state.total > 0 ? String(context.state.total) : "?")").font(.headline.monospacedDigit()) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.attributes.item.title).font(.headline).lineLimit(2)
                        if context.state.total > 0 { ProgressView(value: Double(min(context.state.progress, context.state.total)), total: Double(context.state.total)).tint(widgetAccent(context.attributes.item.accentRGB)) }
                    }
                }
            } compactLeading: { Image(systemName: context.attributes.item.mediaType == "anime" ? "play.tv.fill" : "book.fill").foregroundStyle(widgetAccent(context.attributes.item.accentRGB)) }
            compactTrailing: { Text("\(context.state.progress)").monospacedDigit() }
            minimal: { Image(systemName: "books.vertical.fill").foregroundStyle(widgetAccent(context.attributes.item.accentRGB)) }
            .widgetURL(context.attributes.item.url).keylineTint(widgetAccent(context.attributes.item.accentRGB))
        }
        .supplementalActivityFamilies([.small, .medium])
    }
    @ViewBuilder private func activityCover(_ item: ProgressItem) -> some View {
        if let file = ProgressCache.imageFile(for: item), let data = try? Data(contentsOf: file), let image = widgetThumbnail(data) { Image(uiImage: UIImage(cgImage: image)).resizable().scaledToFill() }
        else { Image(systemName: "books.vertical.fill").foregroundStyle(widgetAccent(item.accentRGB)) }
    }
}
#endif
@main struct AsunaTracksWidgets: WidgetBundle {
    var body: some Widget {
        ContinueWidget(mode: .watching)
        ContinueWidget(mode: .upcoming)
        ContinueWidget(mode: .list)
        #if os(iOS)
        PinnedProgressActivity()
        #endif
    }
}

private func widgetAccent(_ rgb: [Double]?) -> Color {
    guard let rgb, rgb.count == 3 else { return .pink }
    return Color(red: rgb[0], green: rgb[1], blue: rgb[2])
}

private var widgetBrandLogo: Image {
    if let url = Bundle.main.url(forResource: "AsunaTracksLogo", withExtension: "png") {
        #if os(macOS)
        if let image = NSImage(contentsOf: url) { return Image(nsImage: image) }
        #else
        if let image = UIImage(contentsOfFile: url.path) { return Image(uiImage: image) }
        #endif
    }
    return Image(systemName: "books.vertical.fill")
}

/// Decode only the pixels a widget can display, keeping large remote posters within its memory budget.
private func widgetThumbnail(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 360,
        kCGImageSourceShouldCacheImmediately: true
    ] as CFDictionary)
}
