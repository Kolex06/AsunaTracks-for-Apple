import SwiftUI

struct UserProfileView: View {
    let username: String
    @Environment(AppStore.self) private var store
    @Environment(\.accountTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var profile: ProfileResponse?
    @State private var loading = true
    @State private var error: String?
    @State private var tab = "overview"
    @State private var visibleCount = 60
    @State private var category = "all"
    @State private var followingBusy = false
    @State private var showFollows = false
    @State private var wide = false
    private var own: Bool { store.user?.username.lowercased() == username.lowercased() }
    private var user: User? { profile?.user ?? (own ? store.user : nil) }
    private var entries: [ListEntry] { profile?.items ?? (own ? store.entries : []) }
    private var list: [ListEntry] { entries.filter { category == "all" || $0.media.mediaType == category } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let user {
                    hero(user)
                    Picker("Profile section", selection: $tab) {
                        Text("Overview").tag("overview"); Text("List").tag("list"); Text("Collections").tag("collections")
                    }.pickerStyle(.segmented)
                    if loading { AsunaLoadingView(title: "Loading profile…", accent: theme.accent).frame(maxWidth: .infinity, minHeight: 320) }
                    if let error { FailureView(message: error) { Task { await load() } } }
                    if profile?.private == true {
                        ContentUnavailableView("Private profile", systemImage: "lock", description: Text("This person keeps their list private."))
                    } else if tab == "overview" {
                        if wide {
                            HStack(alignment: .top, spacing: 24) {
                                bioPanel.frame(width: 340)
                                dashboard.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            stats
                            bioPanel
                            dashboardContent
                        }
                    } else if tab == "list" {
                        Picker("Titles", selection: $category) { Text("All").tag("all"); Text("Anime").tag("anime"); Text("Manga & novels").tag("manga") }.pickerStyle(.segmented)
                        ForEach(Array(list.prefix(visibleCount))) { entry in profileEntry(entry) }
                        if visibleCount < list.count {
                            AsunaLoadingView(title: "Loading more titles…", accent: theme.accent).frame(maxWidth: .infinity)
                                .onAppear { visibleCount += 60 }
                        }
                        if list.isEmpty { ContentUnavailableView("No titles", systemImage: "books.vertical") }
                    } else {
                        ForEach(profile?.collections ?? []) { collection in
                            NavigationLink { CollectionDetailView(initial: collection) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(collection.title).font(.title3.bold())
                                    if let copy = collection.shortDescription { Text(copy).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                                    Text("\(collection.stats?.itemCount ?? collection.previewItems?.count ?? 0) titles").font(.caption).foregroundStyle(theme.accent)
                                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.glass)
                        }
                        if profile?.collections?.isEmpty != false { ContentUnavailableView("No public collections", systemImage: "rectangle.stack") }
                    }
                    if own {
                        NavigationLink { AccountView() } label: { Label("Account & appearance", systemImage: "person.crop.circle.badge.gearshape") }.buttonStyle(.glass)
                    }
                    NavigationLink { CommunityView() } label: { Label("Explore the community", systemImage: "person.2") }.buttonStyle(.glass)
                } else if loading { AsunaLoadingView(title: "Loading profile…", accent: theme.accent).frame(maxWidth: .infinity, minHeight: 320) }
                else if let error { FailureView(message: error) { Task { await load() } } }
            }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.onGeometryChange(for: Bool.self) { $0.size.width >= 850 } action: { wide = $0 }
            .asunaSurface().navigationTitle(own ? "Profile" : "@\(username)")
            .task(id: username) { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showFollows) {
                NavigationStack {
                    List {
                        Section("Followers · \(profile?.follow?.followers ?? 0)") { ForEach(profile?.follow?.followersList ?? []) { person in followRow(person) } }
                        Section("Following · \(profile?.follow?.following ?? 0)") { ForEach(profile?.follow?.followingList ?? []) { person in followRow(person) } }
                    }.navigationTitle("Connections").toolbar { Button("Done") { showFollows = false } }
                }.environment(store).frame(minWidth: 300, minHeight: 360)
            }
    }
    private var bioPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let bio = user?.bio, !bio.isEmpty {
                Text("About").font(.title2.bold())
                RichProfileBio(text: bio)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent.opacity(0.04), in: .rect(cornerRadius: 20))
    }
    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 24) { stats; dashboardContent }
    }
    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            statusOverview
            let favorites = entries.filter { $0.favorite == true }
            if !favorites.isEmpty { MediaRail(title: "Favorites", subtitle: "The stories that stand out", items: Array(favorites.prefix(20).map(\.media))) }
            let continuing = entries.filter(\.active)
            if !continuing.isEmpty { MediaRail(title: "In progress", subtitle: "Watching and reading now", items: Array(continuing.prefix(20).map(\.media))) }
            Text("Recently updated").font(.title2.bold())
            ForEach(Array(entries.prefix(8))) { entry in profileEntry(entry) }
            Button("Show full list") { tab = "list" }.buttonStyle(.glass)
        }
    }
    private func hero(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let banner = user.bannerUrl, !banner.isEmpty { AsunaArtwork(path: banner, accent: user.accountTheme.accent).frame(height: 190).clipShape(.rect(cornerRadius: 22)) }
            HStack(spacing: 16) {
                ProfileAvatar(user: user, size: 82)
                VStack(alignment: .leading, spacing: 5) {
                    Text(user.displayName ?? user.username).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("@\(user.username)").foregroundStyle(.secondary)
                    UserRoleBadges(user: user)
                }
                Spacer(minLength: 0)
            }
            let actionLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            actionLayout {
                if let follow = profile?.follow {
                    Button("\(follow.followers ?? 0) followers · \(follow.following ?? 0) following") { showFollows = true }.buttonStyle(.glass)
                }
                if !own && store.user != nil {
                    Button(profile?.follow?.isFollowing == true ? "Following" : "Follow") { Task { await toggleFollow() } }.buttonStyle(.glassProminent).disabled(followingBusy)
                }
            }
        }
    }
    private var stats: some View {
        let rated = entries.compactMap(\.rating)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 12) {
            stat("Anime", "\(entries.filter { $0.media.mediaType == "anime" }.count)")
            stat("Episodes", entries.filter { $0.media.mediaType == "anime" }.reduce(0) { $0 + ($1.progress ?? 0) }.formatted())
            stat("Manga & novels", "\(entries.filter { $0.media.mediaType == "manga" }.count)")
            stat("Chapters", entries.filter { $0.media.mediaType == "manga" }.reduce(0) { $0 + ($1.progress ?? 0) }.formatted())
            stat("Mean score", rated.isEmpty ? "—" : String(format: "%.1f", rated.reduce(0,+) / Double(rated.count)))
            stat("Favorites", "\(entries.filter { $0.favorite == true }.count)")
        }
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(value).font(.title2.bold()).foregroundStyle(theme.accent); Text(title).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(theme.accent.opacity(0.07), in: .rect(cornerRadius: 18))
    }
    private var statusOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("List overview").font(.title2.bold())
            ForEach(LibraryStatus.allCases) { status in
                let count = entries.filter { status.matches($0) }.count
                HStack { Circle().fill(StatusStyle.color(status.rawValue)).frame(width: 9, height: 9); Text(status.label); Spacer(); Text(count.formatted()).monospacedDigit().foregroundStyle(.secondary) }
                if !entries.isEmpty { StatusProgress(value: Double(count), total: Double(entries.count), status: status.rawValue) }
            }
        }.padding(20).background(theme.accent.opacity(0.04), in: .rect(cornerRadius: 20))
    }
    private func profileEntry(_ entry: ListEntry) -> some View {
        NavigationLink { MediaDetailView(initial: entry.media) } label: {
            HStack(spacing: 14) {
                Poster(media: entry.media).frame(width: 48, height: 70).clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) { Text(entry.media.displayTitle).font(.headline).lineLimit(2); StatusBadge(status: entry.status) }
                Spacer()
                Text("\(entry.progress ?? 0) / \(entry.media.total > 0 ? String(entry.media.total) : "?")").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(12).background(theme.accent.opacity(0.05), in: .rect(cornerRadius: 14))
        }.buttonStyle(.plain).appCardInteraction()
    }
    private func followRow(_ user: User) -> some View {
        NavigationLink { UserProfileView(username: user.username) } label: { HStack { ProfileAvatar(user: user, size: 32); Text(user.displayName ?? user.username) } }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            if store.user == nil {
                let result: ProfileResponse = try await APIClient.shared.request("public/api/users/\(username)")
                try Task.checkCancellation(); profile = result
            } else {
                async let fullPublic: ProfileResponse = APIClient.shared.request("public/api/users/\(username)")
                let result: ProfileResponse = try await APIClient.shared.request("api/users/\(username)", query: ["updates_limit": "20"])
                let enriched = try? await fullPublic
                try Task.checkCancellation()
                profile = ProfileResponse(user: result.user, items: enriched?.private == true ? result.items : enriched?.items ?? result.items,
                    collections: result.collections, follow: result.follow, private: result.private)
            }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func toggleFollow() async {
        guard !followingBusy else { return }
        followingBusy = true
        defer { followingBusy = false }
        do {
            let _: MutationAcknowledgement = try await APIClient.shared.request("api/users/\(username)/follow", method: "POST", body: JSONSerialization.data(withJSONObject: ["following": !(profile?.follow?.isFollowing ?? false)]))
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
