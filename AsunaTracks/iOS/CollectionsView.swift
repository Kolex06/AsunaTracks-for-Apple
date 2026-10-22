import SwiftUI

struct CollectionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accountTheme) private var theme
    @State private var scope = "featured"
    @State private var query = ""
    @State private var items: [TrackCollection] = []
    @State private var loading = true
    @State private var error: String?
    private var key: String { "\(scope):\(query):\(store.user?.id ?? 0)" }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Collections").font(.largeTitle.bold())
                Text("Watch orders, shared favorites, and stories worth collecting.").foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        scopeButton("Featured", "featured"); scopeButton("Newest", "recent")
                        if store.user != nil { scopeButton("Following", "following"); scopeButton("My Collections", "mine") }
                    }.padding(.vertical, 4)
                }.appRailScrollIndicators()
                if loading { AsunaLoadingView(title: "Finding collections…", accent: theme.accent).frame(maxWidth: .infinity, minHeight: 320) }
                if let error { FailureView(message: error) { Task { await load() } } }
                if !loading && items.isEmpty && error == nil {
                    ContentUnavailableView("No collections found", systemImage: "rectangle.stack", description: Text(query.isEmpty ? "Try another collection filter." : "Try another title or creator."))
                }
                ForEach(items) { collection in
                    NavigationLink { CollectionDetailView(initial: collection) } label: { CollectionCard(collection: collection) }.buttonStyle(.plain)
                }
            }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.asunaSurface().navigationTitle("Collections")
            .searchable(text: $query, prompt: "Collections or creators")
            .task(id: key) {
                do { if !query.isEmpty { try await Task.sleep(for: .milliseconds(300)) }; try Task.checkCancellation(); await load() } catch {}
            }
    }
    private func scopeButton(_ title: String, _ value: String) -> some View {
        Button(title) { scope = value }.buttonStyle(.glass).tint(scope == value ? theme.accent : .secondary)
            .accessibilityAddTraits(scope == value ? .isSelected : [])
    }
    private func load() async {
        let requestKey = key
        loading = true; error = nil; items = []
        defer { if requestKey == key && !Task.isCancelled { loading = false } }
        do {
            let response: CollectionPage = try await APIClient.shared.request("api/collections", query: ["scope": scope, "q": query, "limit": "60"])
            try Task.checkCancellation(); guard requestKey == key else { return }
            items = response.items
        } catch is CancellationError {} catch { if requestKey == key && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

private struct CollectionCard: View {
    let collection: TrackCollection
    @Environment(\.accountTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(Array((collection.previewItems ?? []).prefix(5)), id: \.identity) { media in
                        Poster(media: media).frame(width: 76, height: 110).clipShape(.rect(cornerRadius: 10))
                    }
                }
            }.appRailScrollIndicators()
            Text(collection.title).font(.title3.bold()).foregroundStyle(.primary)
            if let owner = collection.owner {
                HStack(spacing: 8) { ProfileAvatar(user: owner, size: 24); Text(owner.displayName ?? owner.username).font(.subheadline).foregroundStyle(.secondary) }
            }
            if let description = collection.shortDescription ?? collection.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            HStack(spacing: 16) {
                Label("\(collection.stats?.itemCount ?? 0) titles", systemImage: "books.vertical")
                Label("\(collection.stats?.likeCount ?? 0)", systemImage: "heart")
                Label("\(collection.stats?.followerCount ?? 0)", systemImage: "person.2")
                Spacer()
                Image(systemName: "chevron.right")
            }.font(.caption).foregroundStyle(theme.accent)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent.opacity(0.06), in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(theme.accent.opacity(0.18)) }
            .appCardInteraction()
            .accessibilityElement(children: .combine)
    }
}

struct CollectionDetailView: View {
    let initial: TrackCollection
    @Environment(AppStore.self) private var store
    @Environment(\.accountTheme) private var theme
    @State private var detail: TrackCollection?
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    private var collection: TrackCollection { detail ?? initial }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if let artwork = collection.bannerUrl ?? collection.heroImageUrl {
                    AsunaArtwork(path: artwork, accent: theme.accent).frame(height: 210).clipShape(.rect(cornerRadius: 20))
                }
                Text(collection.title).font(.largeTitle.bold())
                if let owner = collection.owner { HStack { ProfileAvatar(user: owner, size: 32); Text("By \(owner.displayName ?? owner.username)").foregroundStyle(.secondary) } }
                if let description = collection.description { Text(.init(description)).textSelection(.enabled).lineSpacing(4) }
                if let tags = collection.tags, !tags.isEmpty { Text(tags.map { "#\($0)" }.joined(separator: "  ")).font(.caption).foregroundStyle(theme.accent) }
                if loading { AsunaLoadingView(title: "Loading collection…", accent: theme.accent).frame(maxWidth: .infinity, minHeight: 320) }
                if let error { FailureView(message: error) { Task { await load() } } }
                if store.user != nil && detail != nil {
                    HStack {
                        Button { Task { await react("like", enabled: !(collection.viewerLiked ?? false)) } } label: { Label(collection.viewerLiked == true ? "Liked" : "Like", systemImage: collection.viewerLiked == true ? "heart.fill" : "heart") }
                        Button { Task { await react("follow", enabled: !(collection.viewerFollowing ?? false)) } } label: { Label(collection.viewerFollowing == true ? "Following" : "Follow", systemImage: collection.viewerFollowing == true ? "checkmark.circle.fill" : "plus.circle") }
                        if busy { AsunaLoadingView(title: "Updating collection…", accent: theme.accent, compact: true) }
                    }.buttonStyle(.glass).disabled(busy || loading)
                }
                Text(collection.ranked == true ? "Watch order" : "Titles").font(.title2.bold())
                ForEach(Array((collection.items ?? []).enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink { MediaDetailView(initial: item.media) } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Text("\(index + 1)").font(.headline).foregroundStyle(theme.accent).frame(width: 24)
                                Poster(media: item.media).frame(width: 70, height: 102).clipShape(.rect(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.media.displayTitle).font(.headline)
                                    Text(item.media.type ?? item.media.mediaType.capitalized).font(.caption).foregroundStyle(.secondary)
                                    if let score = item.media.asunatracksScore?.displayRating { Text(String(format: "AsunaTracks %.1f / 10", score)).font(.caption.bold()).foregroundStyle(theme.accent) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        if let title = item.noteTitle, !title.isEmpty { Text(title).font(.headline) }
                        if let note = item.note, !note.isEmpty { Text(.init(note)).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                    }.padding(16).background(theme.accent.opacity(0.05), in: .rect(cornerRadius: 18))
                }
                if let comments = collection.comments, !comments.isEmpty {
                    Text("Comments").font(.title2.bold())
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { ProfileAvatar(user: comment.user, size: 26); Text(comment.user?.displayName ?? comment.user?.username ?? "AsunaTracks user").font(.subheadline.bold()) }
                            Text(.init(comment.body)).font(.subheadline).textSelection(.enabled)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(theme.accent.opacity(0.05), in: .rect(cornerRadius: 16))
                    }
                }
                NavigationLink { SiteFeatureView(title: "Manage collection", path: "/collections/\(collection.id)", forceWebsite: true) } label: { Label("Edit, collaborate & comment", systemImage: "square.and.pencil") }.buttonStyle(.glass)
            }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.asunaSurface().navigationTitle(collection.title).task { await load() }
            .toolbar { ShareLink(item: APIClient.origin.appendingPathComponent("collections/\(initial.id)")) }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { let response: CollectionResponse = try await APIClient.shared.request("api/collections/\(initial.id)"); try Task.checkCancellation(); detail = response.collection }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func react(_ kind: String, enabled: Bool) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["enabled": enabled])
            let _: MutationAcknowledgement = try await APIClient.shared.request("api/collections/\(initial.id)/\(kind)", method: "POST", body: body)
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
