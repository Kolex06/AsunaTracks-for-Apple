import SwiftUI

/// Native site sections share cancellation, refresh, and AsunaTracks loading states.
private struct NativeAPIContent<Payload: Decodable, Content: View>: View {
    let path: String
    var query: [String: String] = [:]
    let content: (Payload) -> Content
    @Environment(\.accountTheme) private var theme
    @State private var payload: Payload?
    @State private var loading = true
    @State private var error: String?
    private var requestID: String {
        path + query.keys.sorted().map { "\($0)=\(query[$0] ?? "")" }.joined(separator: "&")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let payload { content(payload) }
                if loading && payload == nil {
                    AsunaLoadingView(title: "Loading…", accent: theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 320)
                }
                if let error { FailureView(message: error) { Task { await load() } } }
            }.padding(24).frame(maxWidth: 1400).frame(maxWidth: .infinity)
        }
        .asunaSurface()
        .task(id: requestID) { payload = nil; await load() }
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(loading).accessibilityLabel("Refresh")
            }
        }
    }
    private func load() async {
        let key = requestID
        loading = true; error = nil
        defer { if key == requestID && !Task.isCancelled { loading = false } }
        do {
            let response: Payload = try await APIClient.shared.request(path, query: query)
            try Task.checkCancellation()
            guard key == requestID else { return }
            payload = response
        } catch is CancellationError {} catch {
            if key == requestID && !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

struct SeasonsView: View {
    @Environment(\.accountTheme) private var theme
    @State private var search = ""
    var body: some View {
        NativeAPIContent(path: "public/api/seasons") { (page: SeasonPage) in
            VStack(alignment: .leading, spacing: 24) {
                Text("Every season has a story").font(.largeTitle.bold())
                Text("Explore the seasons in the AsunaTracks catalog.").foregroundStyle(.secondary)
                let matching = page.items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
                if matching.isEmpty { ContentUnavailableView.search(text: search) }
                ForEach(Set(matching.map(\.year)).sorted(by: >), id: \.self) { year in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(String(year)).font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                            ForEach(matching.filter { $0.year == year }) { season in
                                NavigationLink { SeasonTitlesView(season: season) } label: {
                                    VStack(alignment: .leading, spacing: 14) {
                                        Image(systemName: season.icon).font(.title2).foregroundStyle(theme.accent)
                                        Text(season.season.capitalized).font(.headline).foregroundStyle(.primary)
                                        if let count = season.animeCount { Text("\(count) titles").font(.subheadline).foregroundStyle(.secondary) }
                                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(theme.accent.opacity(0.07), in: .rect(cornerRadius: 20))
                                        .appCardInteraction()
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Seasons").searchable(text: $search, prompt: "Find a year or season")
    }
}

private struct SeasonTitlesView: View {
    let season: CatalogSeason
    var body: some View {
        NativeAPIContent(path: "public/api/seasons/\(season.year)/\(season.season)") { (page: MediaPage) in
            VStack(alignment: .leading, spacing: 20) {
                Text(season.title).font(.largeTitle.bold())
                Text("\(page.items.count) titles").foregroundStyle(.secondary)
                if page.items.isEmpty { ContentUnavailableView("No titles yet", systemImage: season.icon) }
                else { MediaGrid(items: page.items) }
            }
        }.navigationTitle(season.title)
    }
}

struct GenresView: View {
    @Environment(\.accountTheme) private var theme
    @State private var type: BrowseKind = .anime
    @State private var search = ""
    var body: some View {
        NativeAPIContent(path: "public/api/genres", query: ["type": type.apiType]) { (page: PublicGenrePage) in
            VStack(alignment: .leading, spacing: 24) {
                Text("Find your kind of story").font(.largeTitle.bold())
                Picker("Catalog", selection: $type) {
                    Text("Anime").tag(BrowseKind.anime)
                    Text("Manga").tag(BrowseKind.manga)
                }.pickerStyle(.segmented).frame(maxWidth: 400)
                let matching = page.items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                if matching.isEmpty { ContentUnavailableView.search(text: search) }
                ForEach(["genre", "theme", "demographic", "explicit"], id: \.self) { kind in
                    let genres = matching.filter { ($0.kind ?? "genre") == kind }.sorted { $0.name < $1.name }
                    if !genres.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(kind == "demographic" ? "Demographics" : kind == "explicit" ? "Explicit genres" : "\(kind.capitalized)s")
                                .font(.title2.bold())
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                                ForEach(genres) { genre in
                                    NavigationLink { BrowseView(initialKind: type, initialGenre: genre) } label: {
                                        HStack {
                                            Text(genre.name).font(.headline).foregroundStyle(.primary)
                                            Spacer(minLength: 4)
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.accent)
                                        }.padding(16).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                                            .background(theme.accent.opacity(0.07), in: .rect(cornerRadius: 16))
                                            .appCardInteraction()
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Genres").searchable(text: $search, prompt: "Genres, themes, or demographics")
    }
}

struct AnnouncementsView: View {
    @Environment(\.accountTheme) private var theme
    @State private var search = ""
    var body: some View {
        NativeAPIContent(path: "public/api/announcements", query: ["limit": "100"]) { (page: AnnouncementPage) in
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("What’s new at AsunaTracks").font(.largeTitle.bold())
                let matching = page.items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) }
                if matching.isEmpty { ContentUnavailableView.search(text: search) }
                ForEach(matching) { item in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label((item.category ?? "update").capitalized, systemImage: "megaphone")
                                .foregroundStyle(theme.accent)
                            Spacer()
                            if item.pinned == true { Label("Pinned", systemImage: "pin.fill") }
                        }.font(.caption.bold())
                        Text(item.title).font(.title2.bold()).textSelection(.enabled)
                        RichProfileBio(text: item.body)
                        if let date = item.createdAt {
                            Text(date.prefix(10)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.accent.opacity(0.05), in: .rect(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(theme.accent.opacity(0.15)))
                }
            }.frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.navigationTitle("Announcements").searchable(text: $search, prompt: "Search updates")
    }
}
