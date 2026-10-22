import SwiftUI

private struct AccountThemeKey: EnvironmentKey {
    static let defaultValue = AccountTheme()
}
extension EnvironmentValues {
    var accountTheme: AccountTheme {
        get { self[AccountThemeKey.self] }
        set { self[AccountThemeKey.self] = newValue }
    }
}
extension AccountTheme {
    var accent: Color { let c = accentRGB; return Color(red: c[0], green: c[1], blue: c[2]) }
    var secondary: Color { let c = secondaryRGB; return Color(red: c[0], green: c[1], blue: c[2]) }
}

enum AsunaStyle {
    static let pink = Color(red: 1, green: 0.247, blue: 0.553)
    static let violet = Color(red: 0.659, green: 0.333, blue: 0.969)
    static let navy = Color(red: 0.02, green: 0.035, blue: 0.086)
    static let panel = Color(red: 0.047, green: 0.071, blue: 0.149)
    static let muted = Color(red: 0.608, green: 0.659, blue: 0.780)
}

struct AsunaBackdrop: View {
    @Environment(\.accountTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            scheme == .dark ? AsunaStyle.navy : Color(red: 0.965, green: 0.96, blue: 0.985)
            RadialGradient(colors: [theme.accent.opacity(scheme == .dark ? 0.16 : 0.07), .clear], center: .topLeading, startRadius: 0, endRadius: 500)
            RadialGradient(colors: [theme.secondary.opacity(0.11), .clear], center: .topTrailing, startRadius: 0, endRadius: 650)
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

extension View {
    func asunaSurface() -> some View { scrollContentBackground(.hidden).background { AsunaBackdrop() } }
}

struct BrandMark: View {
    @Environment(\.accountTheme) private var theme
    var body: some View {
        HStack(spacing: 8) {
            Image.asunaLogo.resizable().scaledToFill()
                .frame(width: 30, height: 30).clipShape(Circle())
                .overlay(Circle().strokeBorder(theme.accent.opacity(0.5)))
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                Text("Asuna").foregroundStyle(.primary)
                Text("Tracks").foregroundStyle(theme.accent)
            }.font(.headline.weight(.heavy))
        }.accessibilityElement(children: .combine)
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case discover = "Discover", library = "My List", season = "Browse", top = "Top", account = "Profile"
    var id: String { rawValue }
    var icon: String {
        switch self { case .discover: "sparkles"; case .library: "rectangle.stack"; case .season: "square.grid.2x2"; case .top: "trophy"; case .account: "person.crop.circle" }
    }
}

#if !os(macOS)
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppStore.self) private var store
    @State private var selected: AppSection = .discover
    @State private var openedTitle: OpenedMedia?
    var body: some View {
        TabView(selection: $selected) {
            ForEach(AppSection.allCases) { section in
                NavigationStack { content(section) }.id("\(section.id):\(store.user?.id ?? 0):\(store.user?.showNsfw ?? false)")
                    // Preserve adaptive iPad content inside bottom tab navigation.
                    .environment(\.horizontalSizeClass, sizeClass)
                    .tabItem { Label(section.rawValue, systemImage: section.icon) }
                    .tag(section)
            }
        }
        .tabViewStyle(.tabBarOnly)
        .environment(\.horizontalSizeClass, .compact)
        .overlay {
            if !store.accountLoaded {
                ZStack {
                    AsunaBackdrop()
                    AsunaLoadingView(title: "Your next story awaits…", accent: store.user?.accountTheme.accent ?? AsunaStyle.pink)
                }
            }
        }
        .onOpenURL { url in
            if url.scheme == "asunatracks", url.host == "library" { selected = .library }
            else if let route = OpenedMedia(url: url) { openedTitle = route }
        }
        .sheet(item: $openedTitle) { route in NavigationStack { OpenedMediaView(route: route) }.environment(store) }
        .alert("AsunaTracks", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
    @ViewBuilder private func content(_ section: AppSection) -> some View {
        Group {
        switch section {
        case .discover: DiscoverView()
        case .library: LibraryView()
        case .season: BrowseView()
        case .top: BrowseView(isTop: true)
        case .account: ProfileView()
        }
        }.asunaSurface()
    }
}

#endif

struct Poster: View {
    @Environment(\.accountTheme) private var theme
    let media: Media
    var body: some View {
        AsunaArtwork(path: media.imageUrl, accent: theme.accent)

    }
}

/// Poster height comes from card width, never from a neighbour's text or image dimensions.
struct PortraitCardLayout: Layout {
    var ratio: CGFloat = 0.7
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposed = proposal.width ?? 168
        let width = proposed.isFinite ? max(1, proposed) : 168
        let body = subviews.dropFirst().first?.sizeThatFits(.init(width: width, height: nil)) ?? .zero
        return CGSize(width: width, height: width / ratio + body.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let posterHeight = bounds.width / ratio
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: bounds.width, height: posterHeight))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + posterHeight), anchor: .topLeading,
                          proposal: .init(width: bounds.width, height: nil))
    }
}

struct MediaTile: View {
    @Environment(\.accountTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(AppStore.self) private var store
    let media: Media
    private var status: String? { store.entry(for: media)?.status ?? media.listEntry?.status }
    var body: some View {
        PortraitCardLayout {
            Color.clear
                .overlay { Poster(media: media) }.clipped()
                .overlay(alignment: .topLeading) {
                    Label(media.asunatracksScore?.displayRating.map { String(format: "AT %.1f", $0) } ?? "AT Not rated", systemImage: "star.fill")
                        .font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.black.opacity(0.78), in: Capsule()).padding(9)
                        .accessibilityLabel(media.asunatracksScore?.displayRating.map { "AsunaTracks score \(String(format: "%.1f", $0)) out of 10" } ?? "AsunaTracks: not rated")
                }
                .overlay(alignment: .bottomLeading) {
                    if let status {
                        Label(StatusStyle.label(status), systemImage: "checkmark.circle.fill")
                            .font(.caption2.bold()).foregroundStyle(.white).lineLimit(1)
                            .padding(7).background(.black.opacity(0.78), in: Capsule())
                            .overlay(Capsule().strokeBorder(StatusStyle.color(status).opacity(0.8)))
                            .padding(9)
                    }
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(media.displayTitle).font(.subheadline.weight(.bold)).lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading).foregroundStyle(.primary)
                HStack {
                    Text("AsunaTracks")
                    Spacer(minLength: 2)
                    Text(media.asunatracksScore?.displayRating.map { String(format: "%.1f / 10", $0) } ?? "Not rated")
                }.font(.caption2.weight(.semibold)).foregroundStyle(theme.accent)
                let count = media.asunatracksScore?.count ?? 0
                Text(count > 0 ? "\(count) community \(count == 1 ? "rating" : "ratings")" : "No community ratings yet")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Text("MAL")
                    Spacer(minLength: 2)
                    Text(media.score.map { String(format: "%.1f / 10", $0) } ?? "Not rated")
                }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                HStack(spacing: 5) {
                    Text(media.type ?? media.mediaType.capitalized).lineLimit(1)
                    if let year = media.year { Text("·"); Text(String(year)) }
                }.font(.caption).foregroundStyle(.secondary)
                Text((media.genres ?? []).prefix(2).map(\.name).joined(separator: " · "))
                    .font(.caption2.weight(.medium)).foregroundStyle(theme.accent).lineLimit(1, reservesSpace: true)
                Text(media.total > 0 ? media.totalLabel : "Count to be announced")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(scheme == .dark ? AsunaStyle.panel : .white, in: .rect(cornerRadius: 20))
        .clipShape(.rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder((status.map(StatusStyle.color) ?? theme.accent).opacity(status == nil ? 0.16 : 0.35)))
        .appCardInteraction()
        .accessibilityElement(children: .combine)
    }
}

struct MediaGrid: View {
    let items: [Media]
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18)], alignment: .leading, spacing: 24) {
            ForEach(items, id: \.identity) { media in
                NavigationLink { MediaDetailView(initial: media) } label: { MediaTile(media: media) }.buttonStyle(.plain)
            }
        }
    }
}

struct FailureView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t load this", systemImage: "wifi.exclamationmark")
        } description: { Text(message) } actions: { Button("Try again", action: retry).buttonStyle(.bordered) }
    }
}

struct CatalogView: View {
    @Environment(\.accountTheme) private var theme
    let title: String
    let section: String
    @State private var items: [Media] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        ScrollView {
            if loading && items.isEmpty { AsunaLoadingView(title: "Loading titles…", accent: theme.accent).padding(60) }
            else if let error { FailureView(message: error) { Task { await load() } } }
            else if items.isEmpty { ContentUnavailableView("No titles yet", systemImage: "sparkles.tv") }
            else { MediaGrid(items: items).padding(20) }
        }.asunaSurface().navigationTitle(title).task { await load() }.toolbar { ToolbarItem(placement: .primaryAction) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.disabled(loading).accessibilityLabel("Refresh") } }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { let page: MediaPage = try await APIClient.shared.request("api/discover/section", query: ["section": section]); items = page.items }
        catch { self.error = error.localizedDescription }
    }
}

struct DiscoverView: View {
    @Environment(\.accountTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var items: [Media] = []
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Discover").font(.largeTitle.bold())
                    Text("Your anime. Your manga. Your next favorite.")
                        .font(.subheadline).foregroundStyle(AsunaStyle.muted)
                }
                if !items.isEmpty { FeaturedShowcase(items: items) }
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) { shortcuts }.padding(.vertical, 4)
                    }
                }.appRailScrollIndicators()
                if loading { AsunaLoadingView(title: "Finding your next favorite…", accent: theme.accent).frame(maxWidth: .infinity).padding() }
                else if let error { FailureView(message: error) { Task { await load() } } }
                else {
                    if !store.entries.filter(\.active).isEmpty {
                        MediaRail(title: "Continue your story", subtitle: "Pick up right where you left off.", items: store.entries.filter(\.active).map(\.media))
                    }
                    MediaRail(title: "In the spotlight", subtitle: "Stories worth getting lost in.", items: items)
                    DiscoveryRail(title: "Airing this season", subtitle: "A new chapter starts here.", section: "season")
                    DiscoveryRail(title: "Hidden gems", subtitle: "Great stories. A little less discovered.", section: "hidden")
                    DiscoveryRail(title: "Manga worth reading", subtitle: "Just one more chapter.", section: "manga")
                }
            }.padding(20).frame(maxWidth: 1200).frame(maxWidth: .infinity)
        }
        .navigationTitle("Discover").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { BrandMark() }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { ProfileView() } label: { ProfileAvatar(user: store.user, size: 28) }.accessibilityLabel("Profile")
            }
        }
        .task { await load() }
    }
    @ViewBuilder private var shortcuts: some View {
        NavigationLink { GenreMixView() } label: { Label("Pick a mood", systemImage: "slider.horizontal.3").font(.subheadline.bold()).padding(.vertical, 4) }.buttonStyle(.glass)
        NavigationLink { CatalogView(title: "For You", section: "for-you") } label: { Label("For you", systemImage: "heart").font(.subheadline.bold()).padding(.vertical, 4) }.buttonStyle(.glass)
        NavigationLink { CatalogView(title: "Manga", section: "manga") } label: { Label("Manga", systemImage: "book").font(.subheadline.bold()).padding(.vertical, 4) }.buttonStyle(.glass)
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { let page: MediaPage = try await APIClient.shared.request("api/discover/spotlight"); items = page.items }
        catch { self.error = error.localizedDescription }
    }
}

struct FeaturedShowcase: View {
    @Environment(\.accountTheme) private var theme
    let items: [Media]
    @State private var selection = 0
    @State private var position = 0.0
    @State private var dragOrigin: Double?
    @State private var spinTask: Task<Void, Never>?
    @State private var wheelSettlement: Task<Void, Never>?
    @State private var suppressTapUntil = 0.0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var index: Int { min(selection, max(items.count - 1, 0)) }
    var body: some View {
        if !items.isEmpty {
            let media = items[index]
            VStack(spacing: 14) {
                Text("DISCOVER YOUR NEXT FAVORITE").font(.caption2.weight(.heavy)).tracking(2).foregroundStyle(theme.accent)
                GeometryReader { geometry in
                    let width = min(geometry.size.width * 0.29, 150.0)
                    let compact = geometry.size.width < 600
                    let spacing = compact ? 85.0 : 125.0
                    ZStack {
                        ForEach(Array(items.enumerated()), id: \.element.identity) { itemIndex, item in
                            let offset = offset(for: itemIndex)
                            let distance = abs(offset)
                            Button {
                                guard ProcessInfo.processInfo.systemUptime >= suppressTapUntil else { return }
                                choose(itemIndex)
                            } label: {
                                Poster(media: item).frame(width: width, height: width * 1.43)
                                    .clipShape(.rect(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(itemIndex == index ? theme.accent : .white.opacity(0.15), lineWidth: itemIndex == index ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                            .rotationEffect(.degrees(offset * (compact ? 5 : 6)))
                            .scaleEffect(1 - min(distance, 3) * (compact ? 0.13 : 0.1))
                            .offset(x: offset * spacing, y: distance * (compact ? 12 : 14))
                            .brightness(-min(0.62, distance * 0.16))
                            .opacity(max(0, min(1, (4 - distance) / 1.2)))
                            .zIndex(20 - distance * 3)
                            .allowsHitTesting(distance <= 3.5)
                            .accessibilityHidden(distance > 3.5)
                            .accessibilityLabel("Show \(item.displayTitle)")
                            .accessibilityAddTraits(itemIndex == index ? .isSelected : [])
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard dragOrigin != nil || abs(value.translation.width) > abs(value.translation.height) else { return }
                            if dragOrigin == nil { stopSpin(); dragOrigin = position }
                            suppressTapUntil = ProcessInfo.processInfo.systemUptime + 0.35
                            position = (dragOrigin ?? position) - value.translation.width / spacing
                        }
                        .onEnded { value in
                            guard dragOrigin != nil else { return }
                            dragOrigin = nil
                            suppressTapUntil = ProcessInfo.processInfo.systemUptime + 0.35
                            startSpin(velocity: -value.velocity.width / spacing / 1000)
                        })
                    #if os(macOS)
                    .background {
                        CarouselTrackpadInput { delta in
                            stopSpin(); dragOrigin = nil
                            suppressTapUntil = ProcessInfo.processInfo.systemUptime + 0.3
                            position -= delta / spacing
                            wheelSettlement = Task { @MainActor in
                                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                                guard !Task.isCancelled else { return }
                                settle(); wheelSettlement = nil
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    #endif
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: choose(index + 1)
                        case .decrement: choose(index - 1)
                        @unknown default: break
                        }
                    }
                }.frame(height: 230)
                VStack(spacing: 7) {
                    Text(media.displayTitle).font(.title2.weight(.heavy)).multilineTextAlignment(.center).lineLimit(3)
                    Text([media.type, media.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(AsunaStyle.muted)
                    if let synopsis = media.synopsis {
                        Text(synopsis).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(2).multilineTextAlignment(.center)
                    }
                }
                GlassEffectContainer(spacing: 18) {
                    HStack(spacing: 18) {
                        Button("Previous title", systemImage: "chevron.left") { choose((index - 1 + items.count) % items.count) }
                            .labelStyle(.iconOnly).frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: Circle())
                        NavigationLink { MediaDetailView(initial: media) } label: {
                            Label("Explore title", systemImage: "arrow.up.right").font(.subheadline.bold()).padding(.vertical, 5)
                        }.buttonStyle(.glassProminent)
                        Button("Next title", systemImage: "chevron.right") { choose((index + 1) % items.count) }
                            .labelStyle(.iconOnly).frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }.buttonStyle(.plain)
                }
                Text("\(index + 1) / \(items.count)").font(.caption2.monospacedDigit()).foregroundStyle(AsunaStyle.muted)
            }
            .padding(.horizontal, 18).padding(.vertical, 22).frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .background {
                GeometryReader { geometry in
                    Poster(media: media).frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .overlay(LinearGradient(colors: [AsunaStyle.navy.opacity(0.68), AsunaStyle.navy.opacity(0.96)], startPoint: .top, endPoint: .bottom))
                }
            }
            .clipShape(.rect(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(theme.accent.opacity(0.22)))
            .onDisappear {
                stopSpin(); dragOrigin = nil; settle()
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { stopSpin(); dragOrigin = nil; settle() } }
            .onChange(of: reduceMotion) { _, enabled in if enabled { stopSpin(); settle() } }
            .onChange(of: items.map(\.identity)) { _, _ in
                stopSpin(); dragOrigin = nil; position = 0; selection = 0
            }
        }
    }
    private func offset(for item: Int) -> Double {
        let count = Double(items.count)
        var offset = (Double(item) - position).truncatingRemainder(dividingBy: count)
        if offset > count / 2 { offset -= count }
        if offset < -count / 2 { offset += count }
        return offset
    }
    private func stopSpin() {
        wheelSettlement?.cancel(); wheelSettlement = nil
        spinTask?.cancel()
        spinTask = nil
    }
    private func choose(_ target: Int) {
        stopSpin()
        guard !items.isEmpty else { return }
        let selected = ((target % items.count) + items.count) % items.count
        let destination = position + offset(for: selected)
        selection = selected
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { position = destination }
    }
    private func settle() {
        guard !items.isEmpty else { position = 0; selection = 0; return }
        let target = Int(position.rounded())
        selection = ((target % items.count) + items.count) % items.count
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { position = Double(target) }
    }
    private func startSpin(velocity: Double) {
        stopSpin()
        guard items.count > 1, !reduceMotion else { settle(); return }
        spinTask = Task { @MainActor in
            var speed = min(0.045, max(-0.045, velocity))
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard !Task.isCancelled else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let elapsed = min(40, max(0, (now - previous) * 1000))
                previous = now
                let decay = exp(-elapsed / 1050)
                position += speed * 1050 * (1 - decay)
                speed *= decay
                if abs(speed) < 0.00025 { settle(); spinTask = nil; return }
            }
        }
    }
}

struct MediaRail: View {
    let title: String
    let subtitle: String
    let items: [Media]
    @ScaledMetric(relativeTo: .subheadline) private var cardWidth = 168.0
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                if !title.isEmpty { Text(title).font(.title2.bold()) }
                Text(subtitle).font(.caption).foregroundStyle(AsunaStyle.muted)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items, id: \.identity) { media in
                        NavigationLink { MediaDetailView(initial: media) } label: { MediaTile(media: media).frame(width: cardWidth) }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 2)
            }.appRailScrollIndicators()
        }
    }
}

struct DiscoveryRail: View {
    @Environment(\.accountTheme) private var theme
    let title: String
    let subtitle: String
    let section: String
    @State private var items: [Media] = []
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                NavigationLink { CatalogView(title: title, section: section) } label: {
                    Image(systemName: "arrow.right").frame(width: 36, height: 36)
                }.buttonStyle(.glass).accessibilityLabel("See all \(title)")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary); Button("Retry") { Task { await load() } }.buttonStyle(.glass) }
            else if loading && items.isEmpty { AsunaLoadingView(accent: theme.accent).frame(maxWidth: .infinity).padding() }
            else if items.isEmpty { Text("No titles here yet.").foregroundStyle(.secondary) }
            else { MediaRail(title: "", subtitle: subtitle, items: items) }
        }.task { await load() }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { let page: MediaPage = try await APIClient.shared.request("api/discover/section", query: ["section": section]); items = page.items }
        catch { self.error = error.localizedDescription }
    }
}

struct HeroView: View {
    @Environment(\.accountTheme) private var theme
    let media: Media
    @State private var wide = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: wide ? 250 : 180)
                .overlay { AsunaArtwork(path: media.bannerImageUrl ?? media.imageUrl, accent: theme.accent) }
                .overlay { LinearGradient(colors: [.black.opacity(0.05), AsunaStyle.navy.opacity(0.96)], startPoint: .top, endPoint: .bottom) }
                .clipped().accessibilityHidden(true)
            HStack(alignment: .top, spacing: wide ? 26 : 16) {
                Poster(media: media).frame(width: wide ? 145 : 100, height: wide ? 208 : 144)
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.28)) }
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                VStack(alignment: .leading, spacing: 12) {
                    Text(media.type?.uppercased() ?? media.mediaType.uppercased()).font(.caption.bold()).tracking(1.8).foregroundStyle(theme.accent)
                    Text(media.displayTitle).font(wide ? .largeTitle.bold() : .title2.bold()).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    if media.displayTitle != media.title { Text(media.title).font(.subheadline).foregroundStyle(.white.opacity(0.7)) }
                    if let japanese = media.titleJapanese, japanese != media.title { Text(japanese).font(.caption).foregroundStyle(.white.opacity(0.6)) }
                    Text([media.year.map(String.init), media.status].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.white.opacity(0.8))
                }.padding(.top, 20).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(wide ? 26 : 18).padding(.top, wide ? -72 : -54)
        }.background(AsunaStyle.navy, in: .rect(cornerRadius: 28))
            .clipShape(.rect(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(theme.accent.opacity(0.28)))
            .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { wide = $0 }
    }
}

struct SearchView: View {
    var body: some View { BrowseView(isSearch: true) }
}

private struct DesktopCardFeedback: ViewModifier {
    @State private var hovering = false
    @Environment(\.accountTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        #if os(macOS)
        content
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(theme.accent.opacity(hovering ? 0.7 : 0), lineWidth: 2).allowsHitTesting(false) }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
        #else
        content
        #endif
    }
}
extension View {
    @ViewBuilder func appRailScrollIndicators() -> some View {
        #if os(macOS)
        self.scrollIndicators(.automatic)
        #else
        self.scrollIndicators(.hidden)
        #endif
    }
    func appCardInteraction() -> some View { modifier(DesktopCardFeedback()) }
}
