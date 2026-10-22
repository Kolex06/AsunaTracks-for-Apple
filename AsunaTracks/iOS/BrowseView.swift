import SwiftUI

enum BrowseKind: String, CaseIterable, Identifiable {
    case anime = "Anime", manga = "Manga", novels = "Novels", characters = "Characters"
    var id: String { rawValue }
    var apiType: String { self == .anime ? "anime" : self == .characters ? "characters" : "manga" }
    var icon: String { switch self { case .anime: "play.rectangle"; case .manga: "books.vertical"; case .novels: "book.closed"; case .characters: "person.2" } }
    var copy: String { switch self {
    case .anime: "Find your next favorite series, movie, or OVA."
    case .manga: "Stories worth turning the page for."
    case .novels: "Explore novels and light novels on AsunaTracks."
    case .characters: "Meet the characters behind your favorite stories."
    } }
}

struct BrowseView: View {
    var isSearch = false
    var isTop = false
    @Environment(\.accountTheme) private var theme
    @AppStorage("catalogUsesRows") private var usesRows = false
    @State private var kind: BrowseKind = .anime
    @State private var query = ""
    @State private var ranking = "score"
    @State private var media: [Media] = []
    @State private var characters: [AsunaCharacter] = []
    @State private var page = 0
    @State private var loadedRequestID: String?
    @State private var novelTotal: Int?
    @State private var genres: [Genre] = []
    @State private var selectedGenre: Genre?
    @State private var generation = UUID()
    @State private var more = false
    @State private var loading = true
    @State private var fetchingGeneration: UUID?
    @State private var error: String?
    private var requestID: String { "\(kind.rawValue):\(query):\(ranking):\(selectedGenre?.id ?? 0)" }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if !isTop {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search titles or characters", text: $query)
                            .textFieldStyle(.plain).autocorrectionDisabled()
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                    }.padding(14).background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(theme.accent.opacity(0.3)))
                        .frame(maxWidth: 620).frame(maxWidth: .infinity)
                        .accessibilityElement(children: .contain)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(isTop ? "Top \(kind.rawValue)" : isSearch ? "Find your next favorite" : kind == .novels ? "Novels & light novels" : "Browse \(kind.rawValue)")
                        .font(.largeTitle.bold())
                    Text(kind.copy).font(.subheadline).foregroundStyle(.secondary)
                    if isTop && kind != .characters {
                        Text("Ranked by AsunaTracks scores and community activity. MAL scores are shown for reference.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(BrowseKind.allCases.filter { !isTop || $0 != .novels }) { option in
                                Button { selectedGenre = nil; kind = option } label: {
                                    Label(option.rawValue, systemImage: option.icon)
                                        .font(.subheadline.weight(.semibold)).padding(.vertical, 5)
                                }.buttonStyle(.glass)
                                    .tint(kind == option ? theme.accent : .secondary)
                                    .accessibilityAddTraits(kind == option ? .isSelected : [])
                            }
                        }.padding(.vertical, 4)
                    }
                }.appRailScrollIndicators()
                if !isTop && !isSearch {
                    NavigationLink { ScrollView { WebsiteFeatureLinks().padding(24) }.navigationTitle("Explore AsunaTracks").asunaSurface() } label: {
                        Label("All AsunaTracks features", systemImage: "square.grid.3x3").frame(maxWidth: .infinity)
                    }.buttonStyle(.glass)
                }
                if !isTop && !isSearch && kind == .anime && query.isEmpty && selectedGenre == nil {
                    NavigationLink { CatalogView(title: "This Season", section: "season") } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "calendar").font(.title)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("This season").font(.headline)
                                Text("Explore the current anime lineup").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.padding(18).frame(maxWidth: .infinity)
                    }.buttonStyle(.glass)
                }
                if isTop {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(rankingOptions, id: \.value) { option in
                                Button(option.title) { ranking = option.value }
                                    .buttonStyle(.glass).tint(ranking == option.value ? theme.accent : .secondary)
                                    .accessibilityAddTraits(ranking == option.value ? .isSelected : [])
                            }
                        }.padding(.vertical, 4)
                    }.appRailScrollIndicators()
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(query.isEmpty ? (selectedGenre?.name ?? kind.rawValue) : "Results for “\(query)”").font(.title2.bold())
                        if !media.isEmpty || !characters.isEmpty {
                            Text(kind == .novels && novelTotal != nil ? "\(media.count) of \(novelTotal!) novels" : "\(kind == .characters ? characters.count : media.count) \(kind == .characters ? "characters" : "titles") loaded")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !isTop && kind != .characters {
                        Button { usesRows.toggle() } label: {
                            Image(systemName: usesRows ? "square.grid.2x2" : "list.bullet")
                        }.buttonStyle(.glass).accessibilityLabel(usesRows ? "Show cover cards" : "Show list")
                    }
                    if !isTop && kind != .characters {
                        Menu {
                            Button("All genres") { selectedGenre = nil }
                            ForEach(genres) { genre in Button(genre.name) { selectedGenre = genre } }
                        } label: { Label(selectedGenre == nil ? "Genres" : "Filtered", systemImage: "line.3.horizontal.decrease") }
                            .buttonStyle(.glass).disabled(genres.isEmpty)
                    }
                }
                if let selectedGenre {
                    Button { self.selectedGenre = nil } label: { Label("\(selectedGenre.name) · Clear", systemImage: "xmark.circle.fill") }
                        .font(.subheadline).tint(theme.accent)
                }
                if loading && media.isEmpty && characters.isEmpty {
                    AsunaLoadingView(title: "Loading \(kind.rawValue.lowercased())…", accent: theme.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 36)
                } else if kind == .characters {
                    CharacterGrid(items: characters)
                } else if isTop || usesRows {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(media.enumerated()), id: \.element.identity) { index, item in
                            NavigationLink { MediaDetailView(initial: item) } label: {
                                BrowseMediaRow(media: item, rank: isTop ? index + 1 : nil, showSearches: ranking == "searched")
                            }.buttonStyle(.plain)
                        }
                    }
                } else { MediaGrid(items: media) }
                if !loading && media.isEmpty && characters.isEmpty && error == nil {
                    ContentUnavailableView("No matches yet", systemImage: kind.icon,
                        description: Text(kind == .novels && more ? "Continue through the catalog to find more novels, or search for a title." : "Try an alternate title or another category."))
                }
                if let error { FailureView(message: error) { Task { await load(reset: page == 0) } } }
                if more && error == nil {
                    if loading && (!media.isEmpty || !characters.isEmpty) {
                        AsunaLoadingView(title: "Loading more…", accent: theme.accent).frame(maxWidth: .infinity)
                    } else if !loading {
                        AsunaLoadingView(title: "Loading more…", accent: theme.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .onAppear { Task { await load(reset: false) } }
                    }
                }

            }.padding(20).frame(maxWidth: 1200).frame(maxWidth: .infinity)
        }.asunaSurface().navigationTitle(isTop ? "" : isSearch ? "Search" : "Browse")

            .task(id: kind.apiType) {
                genres = []
                guard !isTop && kind != .characters else { return }
                do {
                    let response: BrowseGenreResponse = try await APIClient.shared.request("public/api/genres", query: ["type": kind.apiType])
                    try Task.checkCancellation()
                    genres = response.items.sorted { $0.name < $1.name }
                } catch {}
            }
            .task(id: requestID) {
                if loadedRequestID == requestID && page > 0 { return }
                generation = UUID(); loadedRequestID = nil
                media = []; characters = []; page = 0; novelTotal = nil; more = false; error = nil; loading = true
                do {
                    if !query.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                    try Task.checkCancellation()
                    await load(reset: true)
                    if !Task.isCancelled && page > 0 { loadedRequestID = requestID }
                } catch {}
            }
    }
    private var rankingOptions: [(title: String, value: String)] {
        if kind == .characters { return [("Favorites", "favorites"), ("Votes", "votes"), ("Appearances", "appearances"), ("Most searched", "searched")] }
        var options = [("Asuna Score", "score"), ("Popular", "popular"), ("Favorites", "favorites"), ("Most tracked", "tracked"), ("Most searched", "searched")]
        if kind == .anime { options += [("Airing now", "airing"), ("Upcoming", "upcoming")] }
        return options
    }
    private func load(reset: Bool) async {
        guard fetchingGeneration != generation else { return }
        let key = requestID
        let token = generation
        fetchingGeneration = token
        let selectedKind = kind
        loading = true; error = nil
        defer {
            if fetchingGeneration == token { fetchingGeneration = nil }
            if key == requestID && token == generation { loading = false }
        }
        var next = reset ? 1 : page + 1
        do {
            repeat {
                try Task.checkCancellation()
                if selectedKind == .novels {
                    var parameters = ["q": query, "page": "\(next)", "limit": "36"]
                    if let selectedGenre { parameters["genre"] = "\(selectedGenre.id)"; parameters["kind"] = selectedGenre.kind ?? "genre" }
                    let response: NovelCatalogPage = try await APIClient.shared.request("public/api/novels", query: parameters)
                    try Task.checkCancellation(); guard key == requestID && token == generation else { return }
                    media += response.items.filter { item in !media.contains { $0.identity == item.identity } }
                    more = response.hasNext
                    novelTotal = response.total
                    page = next
                    return
                }
                let searching = !isTop
                let route = searching && selectedKind == .characters ? "public/api/characters" : searching ? "api/search" : "api/top"
                var parameters = ["type": selectedKind.apiType, "page": "\(next)", "limit": "48"]
                if searching {
                    parameters["q"] = query
                    if let selectedGenre { parameters["genre"] = "\(selectedGenre.id)"; parameters["kind"] = selectedGenre.kind ?? "genre" }
                }
                else { parameters["tab"] = selectedKind == .characters ? (["favorites", "votes", "appearances", "searched"].contains(ranking) ? ranking : "favorites") : ((selectedKind == .anime ? ["score", "popular", "favorites", "tracked", "searched", "airing", "upcoming"] : ["score", "popular", "favorites", "tracked", "searched"]).contains(ranking) ? ranking : "score") }
                if selectedKind == .characters {
                    let response: CharacterPage = try await APIClient.shared.request(route, query: parameters)
                    try Task.checkCancellation(); guard key == requestID && token == generation else { return }
                    characters += response.items.filter { item in !characters.contains { $0.id == item.id } }
                    more = response.hasNext ?? response.pagination?.hasNextPage ?? false
                } else {
                    let response: MediaPage = try await APIClient.shared.request(route, query: parameters)
                    try Task.checkCancellation(); guard key == requestID && token == generation else { return }
                    let matches = selectedKind == .novels ? response.items.filter { ($0.type ?? "").localizedCaseInsensitiveContains("novel") } : response.items
                    media += matches.filter { item in !media.contains { $0.identity == item.identity } }
                    more = response.pagination?.hasNextPage ?? false
                }
                page = next; next += 1
                if !more { break }
            } while false
        } catch is CancellationError {} catch { if key == requestID && token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct CharacterGrid: View {
    let items: [AsunaCharacter]
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18)], spacing: 24) {
            ForEach(items) { character in
                NavigationLink { CharacterDetailView(initial: character) } label: { CharacterTile(character: character) }
                    .buttonStyle(.plain)
            }
        }
    }
}

struct CharacterTile: View {
    let character: AsunaCharacter
    @Environment(\.accountTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        PortraitCardLayout {
            Color.clear
                .overlay { AsunaArtwork(path: character.imageUrl, accent: theme.accent, fallbackPaths: character.imageFallbacks ?? []) }.clipped()
                .overlay(alignment: .bottomLeading) {
                    Text("CHARACTER").font(.caption2.bold()).tracking(1).padding(8)
                        .background(.black.opacity(0.75), in: Capsule()).foregroundStyle(.white).padding(8)
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(character.name).font(.subheadline.bold()).lineLimit(2, reservesSpace: true)
                Text(character.aliases?.first ?? character.nameKanji ?? "Character")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Label(character.favoriteCount.map { "\($0) \($0 == 1 ? "favorite" : "favorites")" } ?? "View character", systemImage: "heart.fill")
                    .font(.caption2).foregroundStyle(theme.accent).lineLimit(1)
            }.padding(12)
        }.background(scheme == .dark ? AsunaStyle.panel : .white, in: .rect(cornerRadius: 20))
            .clipShape(.rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(theme.accent.opacity(0.18)) }
            .appCardInteraction()
    }
}

struct CharacterDetailView: View {
    let initial: AsunaCharacter
    @Environment(\.accountTheme) private var theme
    @State private var detail: AsunaCharacter?
    @State private var loading = true
    @State private var fetchingGeneration: UUID?
    @State private var error: String?
    private var character: AsunaCharacter { detail ?? initial }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    AsunaArtwork(path: character.imageUrl, accent: theme.accent, fallbackPaths: character.imageFallbacks ?? [])
                        .frame(width: 112, height: 164).clipShape(.rect(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CHARACTER").font(.caption.bold()).tracking(2).foregroundStyle(theme.accent)
                        Text(character.name).font(.title2.bold())
                        if let japanese = character.nameKanji { Text(japanese).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                if loading { AsunaLoadingView(title: "Loading character…", accent: theme.accent).frame(maxWidth: .infinity) }
                if let error { FailureView(message: error) { Task { await load() } } }
                NavigationLink {
                    SiteFeatureView(title: character.name, path: "/character/\(character.id)")
                } label: { Label("Gallery, favorites & votes", systemImage: "photo.on.rectangle") }.buttonStyle(.glass)
                if let aliases = character.aliases, !aliases.isEmpty {
                    Text(aliases.joined(separator: " · ")).font(.subheadline).foregroundStyle(theme.accent).fixedSize(horizontal: false, vertical: true)
                }
                if let about = character.about, !about.isEmpty {
                    Text("About").font(.title2.bold())
                    Text(about).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled)
                }
                if let cast = character.voiceActors, !cast.isEmpty {
                    Text("Voice cast").font(.title2.bold())
                    VStack(spacing: 12) {
                        ForEach(Array(cast.enumerated()), id: \.offset) { _, actor in
                            HStack { Text(actor.person?.name ?? "Unknown"); Spacer(); Text(actor.language ?? "").foregroundStyle(.secondary) }.font(.subheadline)
                        }
                    }.padding(16).background(theme.accent.opacity(0.07), in: .rect(cornerRadius: 18))
                }
                if let appearances = character.media, !appearances.isEmpty {
                    Text("Appearances").font(.title2.bold())
                    MediaGrid(items: appearances)
                }
            }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.asunaSurface().navigationTitle(character.name).navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .toolbar { ShareLink(item: URL(string: "https://asunatracks.space/character/\(character.id)")!) }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { let response: CharacterResponse = try await APIClient.shared.request("public/api/characters/\(initial.id)"); detail = response.character }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}


private struct BrowseGenreResponse: Decodable { let items: [Genre] }

private struct BrowseMediaRow: View {
    let media: Media
    let rank: Int?
    let showSearches: Bool
    @Environment(\.accountTheme) private var theme
    @Environment(AppStore.self) private var store
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let rank { Text("#\(rank)").font(.caption.bold()).foregroundStyle(theme.accent).frame(width: 30).padding(.top, 8) }
            Poster(media: media).frame(width: 64, height: 94).clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 7) {
                Text(media.displayTitle).font(.headline).lineLimit(2)
                Text([media.type, media.year.map(String.init), media.total > 0 ? "\(media.total) \(media.unit)" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { scores }
                    VStack(alignment: .leading, spacing: 4) { scores }
                }
                if let status = store.entry(for: media)?.status ?? media.listEntry?.status {
                    StatusBadge(status: status)
                }
                HStack(spacing: 12) {
                    if let count = showSearches ? media.searchCount : media.trackedCount {
                        Label("\(count) \(showSearches ? "searches" : "tracked")", systemImage: showSearches ? "magnifyingglass" : "books.vertical")
                    }
                    if let count = media.favoriteCount { Label("\(count)", systemImage: "heart") }
                }.font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
        }.padding(14).background(theme.accent.opacity(0.06), in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(theme.accent.opacity(0.16)) }
            .appCardInteraction()
            .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var scores: some View {
        Text(media.asunatracksScore?.displayRating.map { String(format: "AsunaTracks %.1f / 10", $0) } ?? "AsunaTracks · Not rated")
            .font(.caption.bold()).foregroundStyle(theme.accent)
        Text(media.score.map { String(format: "MAL %.2f", $0) } ?? "MAL · Not rated")
            .font(.caption).foregroundStyle(.secondary)
        if let count = media.asunatracksScore?.count, count > 0 {
            Text("\(count) \(count == 1 ? "rating" : "ratings")").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct CatalogSearchModifier: ViewModifier {
    let enabled: Bool
    @Binding var query: String
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.searchable(text: $query, prompt: "Titles or characters") }
        else { content }
    }
}
