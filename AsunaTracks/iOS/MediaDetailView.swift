import SwiftUI

struct MediaDetailView: View {
    let initial: Media
    @Environment(\.accountTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var detail: Media?
    @State private var error: String?
    @State private var editor: Media?
    @State private var loading = true
    @State private var tab: MediaDetailTab = .overview
    @State private var expandedStory = false
    @State private var favoriteBusy = false
    private var media: Media { detail ?? initial }
    private var tabs: [MediaDetailTab] { MediaDetailTab.allCases.filter { media.mediaType == "anime" || $0 != .episodes } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HeroView(media: media)
                scores
                if loading { AsunaLoadingView(title: "Loading title details…", accent: theme.accent).frame(maxWidth: .infinity) }
                if let error { FailureView(message: error) { Task { await loadDetail() } } }
                if let entry = store.entry(for: media) { progress(entry) }
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(tabs) { item in
                                Button { tab = item } label: { Label(item.rawValue, systemImage: item.icon).font(.subheadline.bold()).padding(.vertical, 5) }
                                    .buttonStyle(.glass).tint(tab == item ? theme.accent : .secondary)
                                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                            }
                        }.padding(.vertical, 4)
                    }
                }.appRailScrollIndicators()
                if tab == .overview { overview }
                else { MediaExtrasView(media: media, section: tab).id(media.identity) }
            }.padding(20).frame(maxWidth: 1150).frame(maxWidth: .infinity)
        }.asunaSurface().navigationTitle(media.displayTitle).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { trackingDock }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if store.user != nil {
                        Button { Task { await toggleFavorite() } } label: {
                            if favoriteBusy { AsunaLoadingView(title: "Saving favorite…", accent: theme.accent, compact: true) }
                            else { Image(systemName: store.entry(for: media)?.favorite == true ? "heart.fill" : "heart") }
                        }.disabled(favoriteBusy).tint(.pink)
                            .accessibilityLabel(store.entry(for: media)?.favorite == true ? "Remove from favorites" : "Add to favorites")
                    }
                    ShareLink(item: URL(string: "https://asunatracks.space/media/\(media.mediaType)/\(media.id)")!)
                }
            }
            .task(id: initial.identity) { await loadDetail() }
            .sheet(item: $editor) { media in NavigationStack { TrackingEditor(media: media) }.presentationDetents([.large]).presentationBackground(AsunaStyle.navy) }
    }
    private var scores: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            scoreCard("AsunaTracks", media.asunatracksScore?.displayRating, caption: "\(media.asunatracksScore?.count ?? 0) community ratings", icon: "star.fill", tint: theme.accent)
            scoreCard("MyAnimeList", media.score, caption: "MAL reference score", icon: "star", tint: .secondary)
        }
    }
    private func scoreCard(_ title: String, _ score: Double?, caption: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(score.map { String(format: "%.1f", $0) } ?? "—").font(.title.bold())
                if score != nil { Text("/ 10").font(.caption).foregroundStyle(.secondary) }
            }
            Text(score == nil ? "Not rated yet" : caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(tint.opacity(0.07), in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(tint.opacity(0.16)))
    }
    private func progress(_ entry: ListEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Your progress", systemImage: "books.vertical").font(.headline)
                Spacer()
                StatusBadge(status: entry.status)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.progress ?? 0)").font(.title.bold()).monospacedDigit()
                Text("/ \(media.total > 0 ? String(media.total) : "?") \(media.unit)").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let rating = entry.rating { Label(String(format: "%.1f", rating), systemImage: "star.fill").font(.subheadline.bold()).foregroundStyle(theme.accent) }
            }
            if media.total > 0 { StatusProgress(value: Double(entry.progress ?? 0), total: Double(media.total), status: entry.status) }
            #if os(iOS)
            if entry.active { LiveProgressButton(entry: entry) }
            #endif
        }.padding(18).background(StatusStyle.color(entry.status).opacity(0.06), in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(StatusStyle.color(entry.status).opacity(0.24)))
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let genres = media.genres, !genres.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(genres) { genre in Text(genre.name).font(.caption.weight(.semibold)).foregroundStyle(theme.accent).padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity).background(theme.accent.opacity(0.08), in: Capsule()) }
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("The story").font(.title2.bold())
                if let synopsis = media.synopsis, !synopsis.isEmpty {
                    Text(synopsis).lineSpacing(5).foregroundStyle(.secondary).lineLimit(expandedStory ? nil : 8).textSelection(.enabled)
                    if synopsis.count > 500 { Button(expandedStory ? "Show less" : "Read more") { expandedStory.toggle() }.font(.subheadline.bold()).tint(theme.accent) }
                } else { Text("No synopsis has been added yet.").foregroundStyle(.secondary) }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(theme.accent.opacity(0.04), in: .rect(cornerRadius: 20))
            Text("Title information").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], alignment: .leading, spacing: 12) {
                info("Format", media.type ?? media.mediaType.capitalized)
                info("Status", media.status ?? "Unknown")
                info(media.unit.capitalized, media.total > 0 ? String(media.total) : "To be announced")
                if let volumes = media.volumes, volumes > 0 { info("Volumes", String(volumes)) }
                if let year = media.year { info("Year", String(year)) }
                if let season = media.season, !season.isEmpty { info("Season", season.capitalized) }
                if let date = media.startDate { info("Released", String(date.prefix(10))) }
                if let date = media.endDate { info("Finished", String(date.prefix(10))) }
                if let rating = media.ageRating { info("Age rating", rating) }
            }
            if let cast = media.characters, !cast.isEmpty {
                HStack { Text("Characters").font(.title2.bold()); Spacer(); Button("See cast") { tab = .characters }.buttonStyle(.glass) }
                CharacterGrid(items: Array(cast.prefix(6)))
            }
            NavigationLink { CollectionsView() } label: { Label("Explore community collections", systemImage: "rectangle.stack") }.buttonStyle(.glass)
        }
    }
    private func info(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true) }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading).padding(14)
            .background(theme.accent.opacity(0.04), in: .rect(cornerRadius: 16))
    }
    private var trackingDock: some View {
        GlassEffectContainer(spacing: 12) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                if let entry = store.entry(for: media) {
                    Button { editor = media } label: { Label("Edit progress", systemImage: "slider.horizontal.3").font(.subheadline.bold()).padding(.vertical, 6) }.buttonStyle(.glass)
                    if entry.canAdvance {
                        Button { Task { do { try await store.advance(entry) } catch { self.error = error.localizedDescription } } } label: {
                            Group {
                                if store.busyIDs.contains(entry.id) { AsunaLoadingView(title: "Updating…", accent: theme.accent, compact: true) }
                                else { Label("Log \(media.mediaType == "manga" ? "chapter" : "episode") \((entry.progress ?? 0) + 1)", systemImage: "plus").font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.75) }
                            }.padding(.vertical, 6)
                        }.buttonStyle(.glassProminent).disabled(store.busyIDs.contains(entry.id))
                    }
                } else if store.user != nil {
                    Button { editor = media } label: { Label("Add to my list", systemImage: "plus").font(.headline).padding(.vertical, 6) }.buttonStyle(.glassProminent)
                } else {
                    NavigationLink { AccountView() } label: { Label("Sign in to track", systemImage: "person.crop.circle").font(.headline).padding(.vertical, 6) }.buttonStyle(.glassProminent)
                }
            }.frame(maxWidth: 1100).frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.vertical, 12)
        }
    }
    private func loadDetail() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let response: DetailResponse = try await APIClient.shared.request("public/api/\(initial.mediaType)/\(initial.id)")
            try Task.checkCancellation(); detail = response.media
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func toggleFavorite() async {
        guard !favoriteBusy else { return }
        favoriteBusy = true; defer { favoriteBusy = false }
        do {
            let _: MutationAcknowledgement = try await APIClient.shared.request("api/media/\(media.mediaType)/\(media.id)/favorite", method: "POST", body: JSONSerialization.data(withJSONObject: ["favorite": !(store.entry(for: media)?.favorite ?? false)]))
            try await store.refreshList()
        } catch { self.error = error.localizedDescription }
    }
}
