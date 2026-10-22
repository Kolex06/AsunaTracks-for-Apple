import SwiftUI

enum MediaDetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview", episodes = "Episodes", characters = "Characters", related = "Related", artwork = "Artwork", reviews = "Reviews"
    var id: String { rawValue }
    var icon: String {
        switch self { case .overview: "text.alignleft"; case .episodes: "play.rectangle"; case .characters: "person.2"; case .related: "rectangle.stack"; case .artwork: "photo.on.rectangle"; case .reviews: "text.bubble" }
    }
}
struct MediaExtrasView: View {
    let media: Media
    let section: MediaDetailTab
    @Environment(\.accountTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var episodes: [MediaEpisode] = []
    @State private var characters: [AsunaCharacter] = []
    @State private var pictures: [MediaPicture] = []
    @State private var relations: [MediaRelation] = []
    @State private var reviews: [MediaReview] = []
    @State private var loading = true
    @State private var error: String?
    @State private var page = 0
    @State private var more = false
    @State private var generation = UUID()
    @State private var fetching: UUID?
    @State private var selectedPicture: MediaPicture?
    @State private var showReviewComposer = false
    @State private var episodeQuery = ""
    @State private var unwatchedOnly = false
    @State private var progressError: String?
    @State private var progressBlocked = false
    private var listEntry: ListEntry? { store.entry(for: media) }
    private var filteredEpisodes: [MediaEpisode] {
        episodes.filter { episode in
            (!unwatchedOnly || !isWatched(episode)) && (episodeQuery.isEmpty || "\(episode.number) \(episode.title ?? "")".localizedCaseInsensitiveContains(episodeQuery))
        }
    }
    private func isWatched(_ episode: MediaEpisode) -> Bool {
        if episode.watchedAt != nil { return true }
        guard let number = episode.episodeNumber, number > 0, let entry = listEntry else { return false }
        return number <= Double(max(0, entry.progress ?? 0))
    }
    private func isNext(_ episode: MediaEpisode) -> Bool {
        guard let entry = listEntry, entry.canAdvance else { return false }
        return episode.episodeNumber == Double(max(0, entry.progress ?? 0) + 1)
    }
    private var base: String { "public/api/\(media.mediaType)/\(media.id)" }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(section.rawValue).font(.title2.bold())
                Spacer()
                if section == .reviews && store.user != nil { Button("Write a review", systemImage: "square.and.pencil") { showReviewComposer = true }.buttonStyle(.glass) }
            }
            if loading && page == 0 { AsunaLoadingView(title: "Loading \(section.rawValue.lowercased())…", accent: theme.accent).frame(maxWidth: .infinity, minHeight: 260) }
            if let error { FailureView(message: error) { Task { await load(reset: page == 0) } } }
            switch section {
            case .episodes:
                episodeControls
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 650), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(filteredEpisodes) { episode in episodeRow(episode) }
                }
                if !episodes.isEmpty && filteredEpisodes.isEmpty {
                    Text(unwatchedOnly ? "No unwatched episodes match. Clear the search or show all episodes." : "No episodes match your search.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if more && error == nil {
                    AsunaLoadingView(title: "Loading more episodes…", accent: theme.accent).frame(maxWidth: .infinity)
                        .onAppear { Task { await load(reset: false) } }
                }
            case .characters: CharacterGrid(items: characters)
            case .artwork:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 230), spacing: 16)], spacing: 16) {
                    ForEach(pictures) { picture in
                        Button { selectedPicture = picture } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                AsunaArtwork(path: picture.thumbnailUrl ?? picture.imageUrl, accent: theme.accent).frame(height: 200).clipShape(.rect(cornerRadius: 14))
                                Text((picture.pictureType ?? "Artwork").capitalized).font(.caption.bold()).foregroundStyle(.primary)
                            }
                        }.buttonStyle(.plain).appCardInteraction().accessibilityLabel("Open \(picture.pictureType ?? "artwork")")
                    }
                }
            case .related:
                ForEach(Array(relations.enumerated()), id: \.offset) { _, relation in
                    Text(relation.relation).font(.headline).foregroundStyle(theme.accent)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 220), spacing: 16)], spacing: 16) {
                        ForEach(relation.entries, id: \.identity) { title in relatedCard(title) }
                    }
                }
            case .reviews:
                ForEach(reviews) { review in reviewCard(review) }
            case .overview: EmptyView()
            }
            if !loading && error == nil && empty {
                ContentUnavailableView(section == .reviews ? "No reviews yet" : "Nothing added yet", systemImage: section.icon,
                    description: Text(section == .reviews ? "Share what you thought of this story." : "AsunaTracks does not have \(section.rawValue.lowercased()) for this title yet."))
            }
        }
        .task(id: "\(media.identity):\(section.rawValue)") { generation = UUID(); page = 0; more = false; episodes = []; episodeQuery = ""; unwatchedOnly = false; progressBlocked = false; progressError = nil; await load(reset: true) }
        .sheet(item: $selectedPicture) { picture in
            NavigationStack { MediaPictureViewer(picture: picture) }.frame(minWidth: 300, minHeight: 420)
        }
        .sheet(isPresented: $showReviewComposer, onDismiss: { Task { if section == .reviews { await load(reset: true) } } }) {
            NavigationStack { MediaReviewComposer(media: media) }.environment(store).frame(minWidth: 300, minHeight: 400)
        }
    }
    private var empty: Bool {
        switch section { case .episodes: episodes.isEmpty; case .characters: characters.isEmpty; case .artwork: pictures.isEmpty; case .related: relations.isEmpty; case .reviews: reviews.isEmpty; case .overview: false }
    }
    private var episodeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let entry = listEntry {
                HStack {
                    Label("\(max(0, entry.progress ?? 0))\(media.total > 0 ? " / \(media.total)" : "") watched", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold()).foregroundStyle(theme.accent)
                    Spacer()
                    Text("\(episodes.count) loaded").font(.caption).foregroundStyle(.secondary)
                }
                if media.total > 0 { ProgressView(value: min(1, max(0, Double(entry.progress ?? 0) / Double(media.total)))).tint(theme.accent) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { episodeSearch; episodeFilter }
                VStack(alignment: .leading, spacing: 10) { episodeSearch; episodeFilter }
            }
            if let progressError {
                Text(progressError).font(.caption).foregroundStyle(.secondary)
                Button("Refresh progress") {
                    Task {
                        do { try await store.refreshList(); self.progressError = nil; progressBlocked = false }
                        catch { self.progressError = error.localizedDescription }
                    }
                }.buttonStyle(.glass).disabled(store.loadingList)
            }
        }
    }
    private var episodeSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find episode or title", text: $episodeQuery).textFieldStyle(.plain)
                .accessibilityLabel("Search episodes by number or title")
            if !episodeQuery.isEmpty {
                Button { episodeQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear episode search")
            }
        }.padding(12).background(theme.accent.opacity(0.06), in: .rect(cornerRadius: 12))
    }
    private var episodeFilter: some View {
        Picker("Episodes", selection: $unwatchedOnly) {
            Text("All").tag(false)
            Text("Unwatched").tag(true)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
    }
    private func episodeRow(_ episode: MediaEpisode) -> some View {
        let watched = isWatched(episode)
        let next = isNext(episode)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let image = episode.imageUrl ?? episode.coverImageUrl, !image.isEmpty {
                        AsunaArtwork(path: image, accent: theme.accent)
                    } else {
                        ZStack {
                            theme.accent.opacity(0.10)
                            Text(episode.number).font(.title3.bold()).monospacedDigit().foregroundStyle(theme.accent)
                        }.accessibilityHidden(true)
                    }
                }.frame(width: 80, height: 54).clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Episode \(episode.number)").foregroundStyle(theme.accent)
                        if next { Text("Up next").foregroundStyle(theme.accent) }
                        Spacer(minLength: 0)
                        if watched { Image(systemName: "checkmark.circle.fill").foregroundStyle(StatusStyle.color("completed")).accessibilityLabel("Watched") }
                    }.font(.caption.bold())
                    if let title = episode.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(title).font(.subheadline.weight(.semibold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        if let aired = episode.aired { Text(aired.prefix(10)) }
                        if episode.filler == true { Text("Filler").foregroundStyle(.orange) }
                        if episode.recap == true { Text("Recap").foregroundStyle(.secondary) }
                    }.font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if next, let entry = listEntry {
                Button { Task { await logNextEpisode(entry) } } label: {
                    Group {
                        if store.busyIDs.contains(entry.id) { AsunaLoadingView(title: "Saving…", accent: theme.accent, compact: true) }
                        else { Label("Mark episode \(episode.number) watched", systemImage: "checkmark") }
                    }.font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 30)
                }.buttonStyle(.glass).disabled(store.busyIDs.contains(entry.id) || progressBlocked)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent.opacity(next ? 0.09 : 0.04), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(theme.accent.opacity(next ? 0.4 : 0.10)) }
    }
    private func logNextEpisode(_ entry: ListEntry) async {
        guard let accountID = store.user?.id, !store.busyIDs.contains(entry.id), !progressBlocked else { return }
        store.busyIDs.insert(entry.id)
        defer { store.busyIDs.remove(entry.id) }
        do {
            let result = try await ContinueProgressClient().advance(entry, accountID: accountID, accountStillCurrent: { store.user?.id == accountID })
            guard store.user?.id == accountID else { return }
            await store.applyList(result.list, accountID: accountID)
            progressError = nil
        } catch {
            guard store.user?.id == accountID else { return }
            progressError = error.localizedDescription; progressBlocked = true
        }
    }
    @ViewBuilder private func relatedCard(_ title: RelatedTitle) -> some View {
        if let opened = localRoute(title) {
            NavigationLink { OpenedMediaView(route: opened) } label: { relatedLabel(title) }.buttonStyle(.plain)
        } else if let raw = title.url, let url = ProfileBio.safeURL(raw) {
            Link(destination: url) { relatedLabel(title) }.buttonStyle(.plain)
        } else { relatedLabel(title) }
    }
    private func localRoute(_ title: RelatedTitle) -> OpenedMedia? {
        guard let route = title.route, let url = URL(string: route, relativeTo: APIClient.origin), url.host == APIClient.origin.host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 3, parts[0] == "media", ["anime", "manga"].contains(parts[1]), let id = Int(parts[2]), id > 0,
              let deepLink = URL(string: "asunatracks://media/\(parts[1])/\(id)") else { return nil }
        return OpenedMedia(url: deepLink)
    }
    private func relatedLabel(_ title: RelatedTitle) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            AsunaArtwork(path: title.imageUrl, accent: theme.accent).frame(height: 190).clipShape(.rect(cornerRadius: 14))
            Text(title.displayTitle).font(.subheadline.bold()).lineLimit(2).frame(minHeight: 36, alignment: .topLeading).foregroundStyle(.primary)
            Text((title.mediaType ?? title.type ?? "Related").capitalized).font(.caption).foregroundStyle(.secondary)
        }.padding(12).background(theme.accent.opacity(0.05), in: .rect(cornerRadius: 18)).appCardInteraction()
    }
    private func reviewCard(_ review: MediaReview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let user = review.user {
                NavigationLink { UserProfileView(username: user.username) } label: {
                    HStack { ProfileAvatar(user: user, size: 36); Text(user.displayName ?? user.username).font(.headline); Spacer(); Text(review.createdAt.map { String($0.prefix(10)) } ?? "").font(.caption).foregroundStyle(.secondary) }
                }.buttonStyle(.plain)
            }
            if let body = review.body { RichProfileBio(text: body) }
            if let votes = review.votes { Label("\(votes.score ?? 0) community votes", systemImage: "hand.thumbsup").font(.caption).foregroundStyle(.secondary) }
        }.padding(18).background(theme.accent.opacity(0.06), in: .rect(cornerRadius: 18))
    }
    private func load(reset: Bool) async {
        let token = generation; let selected = section
        guard fetching != token else { return }
        fetching = token; loading = true; error = nil
        defer { if fetching == token { fetching = nil }; if generation == token { loading = false } }
        do {
            let next = reset ? 1 : page + 1
            switch selected {
            case .episodes:
                let response: EpisodePage = try await APIClient.shared.request(base + "/episodes", query: ["page": "\(next)", "limit": "60"])
                try Task.checkCancellation(); guard generation == token else { return }
                if reset { episodes = [] }
                episodes += response.items.filter { item in !episodes.contains { $0.id == item.id } }
                more = response.hasNext ?? false
            case .characters:
                let response: CharacterPage = try await APIClient.shared.request(base + "/characters")
                try Task.checkCancellation(); guard generation == token else { return }; characters = response.items
            case .artwork:
                let response: PicturePage = try await APIClient.shared.request(base + "/pictures")
                try Task.checkCancellation(); guard generation == token else { return }; pictures = response.items
            case .related:
                let response: RelationPage = try await APIClient.shared.request(base + "/relations")
                try Task.checkCancellation(); guard generation == token else { return }; relations = response.items
            case .reviews:
                let response: ReviewPage = try await APIClient.shared.request(base + "/reviews", query: ["limit": "50"])
                try Task.checkCancellation(); guard generation == token else { return }; reviews = response.items
            case .overview: break
            }
            page = next
        } catch is CancellationError {} catch { if generation == token { self.error = error.localizedDescription } }
    }
}

private struct MediaPictureViewer: View {
    let picture: MediaPicture
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = 1.0
    @GestureState private var pinch = 1.0
    private var scale: Double { min(4, max(1, zoom * pinch)) }
    var body: some View {
        GeometryReader { geometry in
            if let raw = picture.imageUrl, let url = ProfileBio.safeURL(raw) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        ScrollView([.horizontal, .vertical]) {
                            image.resizable().scaledToFit().frame(width: geometry.size.width * scale, height: geometry.size.height * scale)
                                .onTapGesture(count: 2) { zoom = zoom > 1 ? 1 : 2 }
                        }.simultaneousGesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }.onEnded { zoom = min(4, max(1, zoom * $0.magnification)) })
                    } else if phase.error != nil { ContentUnavailableView("Artwork unavailable", systemImage: "photo") }
                    else { AsunaLoadingView(title: "Loading artwork…").frame(width: geometry.size.width, height: geometry.size.height) }
                }
            } else { ContentUnavailableView("Artwork unavailable", systemImage: "photo") }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).asunaSurface().navigationTitle((picture.pictureType ?? "Artwork").capitalized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Zoom out", systemImage: "minus.magnifyingglass") { zoom = max(1, zoom - 0.5) }.disabled(zoom <= 1)
                    Button("Zoom in", systemImage: "plus.magnifyingglass") { zoom = min(4, zoom + 0.5) }.disabled(zoom >= 4)
                    if let raw = picture.imageUrl, let url = ProfileBio.safeURL(raw) { ShareLink(item: url) }
                }
            }
    }
}

private struct MediaReviewComposer: View {
    let media: Media
    @State private var bodyText = ""
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section(media.displayTitle) { TextEditor(text: $bodyText).frame(minHeight: 180).accessibilityLabel("Your review"); Text("\(bodyText.count) / 4000").font(.caption).foregroundStyle(.secondary) }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.asunaSurface().navigationTitle("Write a review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await publish() } } label: {
                        if saving { AsunaLoadingView(title: "Publishing review…", compact: true) } else { Text("Publish") }
                    }.disabled(saving || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.count > 4000)
                }
            }.interactiveDismissDisabled(saving)
    }
    private func publish() async {
        saving = true; error = nil; defer { saving = false }
        do {
            let _: MutationAcknowledgement = try await APIClient.shared.request("api/media/\(media.mediaType)/\(media.id)/reviews", method: "POST", body: JSONSerialization.data(withJSONObject: ["body": bodyText]))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
