import SwiftUI

struct CommunityView: View {
    @Environment(\.accountTheme) private var theme
    @State private var section = "activity"
    @State private var query = ""
    @State private var users: [User] = []
    @State private var posts: [CommunityPost] = []
    @State private var page = 0
    @State private var more = false
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()
    @State private var fetching: UUID?
    private var key: String { "\(section):\(query)" }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Community").font(.largeTitle.bold())
                Text("Meet the people behind the lists.").foregroundStyle(.secondary)
                Picker("Community", selection: $section) { Text("Activity").tag("activity"); Text("People").tag("people") }.pickerStyle(.segmented)
                if section == "people" {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                        ForEach(users) { user in
                            NavigationLink { UserProfileView(username: user.username) } label: {
                                HStack(spacing: 14) {
                                    ProfileAvatar(user: user, size: 52)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(user.displayName ?? user.username).font(.headline).lineLimit(1)
                                        Text("@\(user.username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        if let role = user.role, role != "user" { Text(role.capitalized).font(.caption2).foregroundStyle(user.accountTheme.accent) }
                                    }
                                    Spacer(minLength: 0)
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(theme.accent.opacity(0.06), in: .rect(cornerRadius: 20)).appCardInteraction()
                            }.buttonStyle(.plain)
                        }
                    }
                } else { ForEach(posts) { post in CommunityPostCard(post: post) } }
                if let error { FailureView(message: error) { Task { await load(reset: page == 0) } } }
                if loading { AsunaLoadingView(title: "Loading community…", accent: theme.accent).frame(maxWidth: .infinity, minHeight: 320) }
                if more && !loading && error == nil {
                    AsunaLoadingView(title: "Loading more…", accent: theme.accent).frame(maxWidth: .infinity)
                        .onAppear { Task { await load(reset: false) } }
                }
                if !loading && error == nil && users.isEmpty && posts.isEmpty { ContentUnavailableView.search(text: query) }
            }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.asunaSurface().navigationTitle("Community").searchable(text: $query, prompt: section == "people" ? "Find users" : "Search posts")
            .task(id: key) {
                generation = UUID(); page = 0; users = []; posts = []; more = false
                do { if !query.isEmpty { try await Task.sleep(for: .milliseconds(300)) }; try Task.checkCancellation(); await load(reset: true) } catch {}
            }
    }
    private func load(reset: Bool) async {
        let token = generation
        guard fetching != token else { return }
        fetching = token; loading = true; error = nil
        defer { if fetching == token { fetching = nil }; if generation == token { loading = false } }
        do {
            let next = reset ? 1 : page + 1
            let parameters = ["q": query, "page": "\(next)", "limit": "24"]
            if section == "people" {
                let response: PublicUserPage = try await APIClient.shared.request("public/api/users", query: parameters)
                try Task.checkCancellation(); guard generation == token else { return }
                users += response.items.filter { user in !users.contains { $0.id == user.id } }
                more = response.hasNext ?? (response.items.count == 24)
            } else {
                let response: ActivityPage = try await APIClient.shared.request("public/api/activity", query: parameters)
                try Task.checkCancellation(); guard generation == token else { return }
                posts += response.items.filter { post in !posts.contains { $0.id == post.id } }
                more = response.hasNext ?? false
            }
            page = next
        } catch is CancellationError {} catch { if token == generation { self.error = error.localizedDescription } }
    }
}

struct CommunityPostCard: View {
    let post: CommunityPost
    @Environment(\.accountTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let user = post.user {
                NavigationLink { UserProfileView(username: user.username) } label: {
                    HStack(spacing: 12) {
                        ProfileAvatar(user: user, size: 40)
                        VStack(alignment: .leading, spacing: 4) { Text(user.displayName ?? user.username).font(.headline); Text("@\(user.username)").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if let date = post.createdAt { Text(date.prefix(10)).font(.caption).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(.plain)
            }
            if let body = post.body, !body.isEmpty { RichProfileBio(text: body) }
            if let url = post.attachment?.url, ProfileBio.safeURL(url) != nil { RichProfileBio(text: "img(\(url))") }
            HStack(spacing: 18) {
                Label("\(post.likeCount ?? 0)", systemImage: "heart")
                Label("\(post.commentCount ?? 0)", systemImage: "bubble.right")
                Spacer()
                NavigationLink { SiteFeatureView(title: "Post", path: "/post/\(post.id)") } label: { Text("Open conversation").font(.caption.bold()) }
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(theme.accent.opacity(0.05), in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(theme.accent.opacity(0.18)))
    }
}
