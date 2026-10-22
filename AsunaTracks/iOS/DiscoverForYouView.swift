import SwiftUI

struct ForYouView: View {
    @Environment(AppStore.self) private var store
    @State private var feed = RecommendationFeed()
    @State private var refreshID = UUID()
    var body: some View {
        ScrollView {
            DiscoverForYouContent(compact: false, refreshID: refreshID, feed: feed)
                .padding(20).frame(maxWidth: 1200).frame(maxWidth: .infinity)
        }.asunaSurface().navigationTitle("For You")
            .refreshable { await feed.load(context: RecommendationContext(user: store.user, entries: store.entries)) }
    }
}

private struct RecommendationRequestKey: Hashable {
    let context: RecommendationContext
    let refreshID: UUID
}

struct DiscoverForYouContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accountTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    let compact: Bool
    let refreshID: UUID
    @State private var feed = RecommendationFeed()
    @State private var selectedMix: String?
    @State private var signIn = false
    @ScaledMetric(relativeTo: .subheadline) private var cardWidth = 180.0
    @ScaledMetric(relativeTo: .subheadline) private var placeholderHeight = 560.0

    init(compact: Bool, refreshID: UUID, feed: RecommendationFeed? = nil) {
        self.compact = compact; self.refreshID = refreshID
        _feed = State(initialValue: feed ?? RecommendationFeed())
    }
    private var context: RecommendationContext { RecommendationContext(user: store.user, entries: store.entries) }
    private var response: DiscoverRecommendationResponse? { feed.context == context ? feed.response : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(response?.isPersonalized == false ? "Discover picks" : "For You", systemImage: "sparkles")
                        .font(compact ? .title2.bold() : .largeTitle.bold())
                    Text(description).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if compact, response != nil {
                    NavigationLink { ForYouView() } label: { Image(systemName: "arrow.right").frame(width: 36, height: 36) }
                        .buttonStyle(.glass).accessibilityLabel("See all recommendations")
                } else if store.user != nil {
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise").frame(width: 36, height: 36) }
                        .buttonStyle(.glass).disabled(feed.loading).accessibilityLabel("Refresh recommendations")
                }
            }
            if store.user == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your next favorite should feel like you.").font(.headline)
                    Text("Sign in to get the website’s recommendations from your favorites, scores, and list activity.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Sign in for recommendations") { signIn = true }.buttonStyle(.glassProminent)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.accent.opacity(0.08), in: .rect(cornerRadius: 22))
            } else if let response {
                if let error = feed.error {
                    Label("Couldn’t refresh. Showing the previous picks. \(error)", systemImage: "wifi.exclamationmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !response.isPersonalized {
                    Label("Add titles, rate favorites, and log your progress to help AsunaTracks learn your taste. These are general picks for now.", systemImage: "heart.text.clipboard")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if response.uniqueItems.isEmpty {
                    ContentUnavailableView("No recommendations yet", systemImage: "sparkles", description: Text("Update your list or favorites, then refresh your picks."))
                } else {
                    mixPicker(response)
                    let items = response.genreMixes.first { $0.label == selectedMix }?.items ?? response.uniqueItems
                    if compact {
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(Array(items.prefix(12)), id: \.identity) { media in
                                    recommendationCard(media, personalized: response.isPersonalized).frame(width: typeSize.isAccessibilitySize ? max(250, cardWidth) : cardWidth)
                                }
                            }.padding(.vertical, 2)
                        }.appRailScrollIndicators()
                    } else {
                        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .top)] : [GridItem(.adaptive(minimum: 165, maximum: 230), spacing: 18, alignment: .top)], alignment: .leading, spacing: 24) {
                            ForEach(items, id: \.identity) { media in recommendationCard(media, personalized: response.isPersonalized) }
                        }
                    }
                    if feed.loading { Label("Refreshing your picks…", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary) }
                }
            } else if let error = feed.error {
                FailureView(message: error) { Task { await reload() } }
            } else {
                AsunaLoadingView(title: "Finding stories for you…", accent: theme.accent).frame(maxWidth: .infinity).frame(minHeight: compact ? placeholderHeight : 360)
            }
        }
        .task(id: RecommendationRequestKey(context: context, refreshID: refreshID)) { await reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reload() } } }
        .sheet(isPresented: $signIn) { NavigationStack { AccountView() }.environment(store).frame(minWidth: 320, minHeight: 360) }
    }
    private var description: String {
        if response?.isPersonalized == true { return "Picked from your favorites, scores, watch history, and people with similar lists." }
        if response?.isPersonalized == false { return "Explore while your personal recommendations take shape." }
        return "Recommendations from your AsunaTracks taste."
    }
    @ViewBuilder private func mixPicker(_ response: DiscoverRecommendationResponse) -> some View {
        if !response.genreMixes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(response.isPersonalized ? "Your genre mixes" : "Explore genre mixes").font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        mixButton("All picks", value: nil)
                        ForEach(response.genreMixes) { mix in mixButton(mix.label, value: mix.label) }
                    }.padding(.vertical, 4)
                }.appRailScrollIndicators()
            }
        }
    }
    private func mixButton(_ title: String, value: String?) -> some View {
        Button { selectedMix = value } label: {
            Text(title).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 9)
                .foregroundStyle(selectedMix == value ? theme.accent : .primary)
                .background(theme.accent.opacity(selectedMix == value ? 0.18 : 0.05), in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selectedMix == value ? .isSelected : [])
    }
    private func recommendationCard(_ media: Media, personalized: Bool) -> some View {
        NavigationLink { MediaDetailView(initial: media) } label: {
            VStack(alignment: .leading, spacing: 10) {
                MediaTile(media: media)
                if personalized {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(media.recommendationLabel ?? "Picked for your taste", systemImage: "sparkles")
                            .font(.caption.bold()).foregroundStyle(theme.accent).lineLimit(3, reservesSpace: true)
                        Text((media.recommendationReason ?? []).isEmpty ? "From your AsunaTracks activity" : "Because you like \((media.recommendationReason ?? []).joined(separator: " · "))")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                    }.padding(.horizontal, 4)
                }
            }.frame(maxWidth: .infinity, alignment: .topLeading)
        }.buttonStyle(.plain)
    }
    private func reload() async {
        let next = context
        if feed.context != next { selectedMix = nil }
        await feed.load(context: next)
    }
}

struct DiscoverCharacterRail: View {
    @Environment(\.accountTheme) private var theme
    @State private var items: [AsunaCharacter] = []
    @State private var error: String?
    @State private var loading = true
    @ScaledMetric(relativeTo: .subheadline) private var cardWidth = 160.0
    @ScaledMetric(relativeTo: .subheadline) private var placeholderHeight = 330.0
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Popular characters").font(.title2.bold())
                Spacer()
                NavigationLink { BrowseView(initialKind: .characters) } label: { Image(systemName: "arrow.right").frame(width: 36, height: 36) }
                    .buttonStyle(.glass).accessibilityLabel("Browse characters")
            }
            Text("Meet the community’s favorites.").font(.caption).foregroundStyle(.secondary)
            if loading { AsunaLoadingView(accent: theme.accent).frame(maxWidth: .infinity).frame(height: placeholderHeight) }
            else if let error { FailureView(message: error) { Task { await load() } } }
            else if items.isEmpty { Text("No characters available yet.").foregroundStyle(.secondary) }
            else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { character in
                            NavigationLink { CharacterDetailView(initial: character) } label: { CharacterTile(character: character).frame(width: cardWidth) }.buttonStyle(.plain)
                        }
                    }
                }.appRailScrollIndicators()
            }
        }.task { await load() }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let page: CharacterPage = try await APIClient.shared.request("api/discover/section", query: ["section": "characters"])
            try Task.checkCancellation()
            items = page.items
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
