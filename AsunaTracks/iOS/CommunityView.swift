import SwiftUI

struct CommunityView: View {
    @Environment(\.accountTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var section = "activity"
    @State private var query = ""
    @State private var users: [User] = []
    @State private var posts: [CommunityPost] = []
    @State private var page = 0
    @State private var more = false
    @State private var loading = true
    @State private var error: String?
    @State private var generation = UUID()
    @State private var fetching: UUID?
    @State private var loadedKey: String?
    private var hasItems: Bool { section == "people" ? !users.isEmpty : !posts.isEmpty }
    private var key: String { "\(section):\(query):\(store.user?.id ?? 0)" }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Community").font(.largeTitle.bold())
                Text("Meet the people behind the lists.").foregroundStyle(.secondary)
                Picker("Community", selection: $section) { Text("Activity").tag("activity"); Text("People").tag("people") }.pickerStyle(.segmented)
                if section == "activity", store.user != nil {
                    CommunityComposer(postID: nil) { Task { await load(reset: true) } }
                }
                if section == "people" {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                        ForEach(users) { user in
                            NavigationLink { UserProfileView(username: user.username) } label: {
                                HStack(spacing: 14) {
                                    ProfileAvatar(user: user, size: 52)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(user.displayName ?? user.username).font(.headline).lineLimit(1)
                                        Text("@\(user.username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        UserRoleBadges(user: user).frame(height: 22, alignment: .leading)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(theme.accent.opacity(0.06), in: .rect(cornerRadius: 20)).appCardInteraction()
                            }.buttonStyle(.plain)
                                .onAppear {
                                    if users.suffix(6).contains(where: { $0.id == user.id }) {
                                        Task { await loadMore() }
                                    }
                                }
                        }
                    }
                } else {
                    ForEach(posts) { post in
                        CommunityPostCard(post: post, onUpdate: updatePost).onAppear {
                            if posts.suffix(3).contains(where: { $0.id == post.id }) {
                                Task { await loadMore() }
                            }
                        }
                    }
                }
                if let error { FailureView(message: error) { Task { await load(reset: page == 0) } } }
                if loading {
                    if hasItems {
                        HStack(spacing: 12) {
                            AsunaLoadingView(accent: theme.accent, compact: true)
                            Text(page == 0 ? "Updating results…" : "Loading more…").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 64)
                    } else {
                        AsunaLoadingView(title: "Loading community…", accent: theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 320)
                    }
                } else if more && error == nil {
                    // A fixed-height footer never replaces the grid with a full-page loader.
                    Color.clear.frame(height: 64).onAppear { Task { await loadMore() } }
                }
                if !loading && error == nil && !hasItems && loadedKey == key {
                    ContentUnavailableView.search(text: query)
                }
            }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.asunaSurface().navigationTitle("Community").searchable(text: $query, prompt: section == "people" ? "Find users" : "Search posts")
            .task(id: key) {
                generation = UUID(); page = 0; more = false; loading = true; error = nil
                do { if !query.isEmpty { try await Task.sleep(for: .milliseconds(300)) }; try Task.checkCancellation(); await load(reset: true) } catch {}
            }
    }
    private func updatePost(_ updated: CommunityPost) {
        if let index = posts.firstIndex(where: { $0.id == updated.id }) { posts[index] = updated }
    }
    private func loadMore() async {
        guard more, !loading, loadedKey == key, error == nil else { return }
        await load(reset: false)
    }
    private func load(reset: Bool) async {
        let token = generation
        let requestKey = key
        let requestedSection = section
        guard fetching != token else { return }
        fetching = token; loading = true; error = nil
        defer { if fetching == token { fetching = nil }; if generation == token && requestKey == key { loading = false } }
        do {
            let next = reset ? 1 : page + 1
            let parameters = ["q": query, "page": "\(next)", "limit": "24"]
            if requestedSection == "people" {
                let response: PublicUserPage = try await APIClient.shared.request("public/api/users", query: parameters)
                try Task.checkCancellation(); guard generation == token && requestKey == key else { return }
                var seen = Set(reset ? [] : users.map(\.id))
                let additions = response.items.filter { seen.insert($0.id).inserted }
                users = reset ? additions : users + additions
                more = response.hasNext ?? (response.items.count == 24)
            } else {
                let response: ActivityPage = try await APIClient.shared.request(store.user == nil ? "public/api/activity" : "api/activity", query: parameters)
                try Task.checkCancellation(); guard generation == token && requestKey == key else { return }
                var seen = Set(reset ? [] : posts.map(\.id))
                let additions = response.items.filter { seen.insert($0.id).inserted }
                posts = reset ? additions : posts + additions
                more = response.hasNext ?? false
            }
            page = next; loadedKey = requestKey
        } catch is CancellationError {} catch { if token == generation && requestKey == key && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct CommunityPostCard: View {
    let post: CommunityPost
    var onUpdate: (CommunityPost) -> Void = { _ in }
    var showsConversation = true
    @Environment(\.accountTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let user = post.user { CommunityAuthorHeader(user: user, date: post.createdAt) }
            if let body = post.body, !body.isEmpty { CommunityBody(text: body) }
            CommunityAttachmentView(attachment: post.attachment)
            HStack(spacing: 10) {
                SocialLikeButton(target: "activity", id: post.id, initialLiked: post.userLiked ?? false, initialCount: post.likeCount ?? 0) { result in
                    var updated = post; updated.userLiked = result.userLiked; updated.likeCount = result.likeCount; onUpdate(updated)
                }
                if showsConversation {
                    NavigationLink { CommunityConversationView(initial: post, onUpdate: onUpdate) } label: {
                        Label("\(post.commentCount ?? 0) comments", systemImage: "bubble.left.and.bubble.right")
                            .font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 40)
                            .background(theme.accent.opacity(0.08), in: Capsule())
                    }.buttonStyle(.plain).accessibilityLabel("\(post.commentCount ?? 0) comments")
                }
                Spacer(minLength: 0)
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(theme.accent.opacity(0.05), in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(theme.accent.opacity(0.18)))
    }
}

struct CommunityAttachmentView: View {
    let attachment: PostAttachment?
    var body: some View {
        if let path = attachment?.url,
           let url = URL(string: path, relativeTo: APIClient.origin)?.absoluteURL,
           ProfileBio.safeURL(url.absoluteString) != nil {
            let video = ["webm", "mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
            RichProfileBio(text: "\(video ? "video" : "img")(\(url.absoluteString))", mediaMaxHeight: 420)
                .accessibilityLabel(attachment?.title ?? (video ? "Attached video" : "Attached image"))
        }
    }
}

struct SocialLikeButton: View {
    let target: String
    let id: Int
    let initialLiked: Bool
    let initialCount: Int
    var onUpdate: (SocialLikeResponse) -> Void = { _ in }
    @Environment(AppStore.self) private var store
    @Environment(\.accountTheme) private var theme
    @State private var result: SocialLikeResponse?
    @State private var busy = false
    @State private var error: String?
    @State private var signIn = false
    private var liked: Bool { result?.userLiked ?? initialLiked }
    private var count: Int { result?.likeCount ?? initialCount }
    var body: some View {
        Button {
            guard store.user != nil else { signIn = true; return }
            Task { await toggle() }
        } label: {
            Label(count > 0 ? "\(count)" : "Like", systemImage: liked ? "heart.fill" : "heart")
                .font(.subheadline.weight(.medium)).monospacedDigit()
                .foregroundStyle(liked ? theme.accent : .secondary)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(theme.accent.opacity(liked ? 0.16 : 0.06), in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).disabled(busy)
            .accessibilityLabel(liked ? "Unlike" : "Like")
            .accessibilityValue("\(count) likes")
            .accessibilityAddTraits(liked ? .isSelected : [])
            .onChange(of: initialLiked) { _, _ in result = nil }
            .onChange(of: initialCount) { _, _ in result = nil }
            .onChange(of: store.user?.id) { _, _ in result = nil }
            .alert("Couldn’t update like", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .sheet(isPresented: $signIn) { NavigationStack { AccountView() }.environment(store).frame(minWidth: 320, minHeight: 360) }
    }
    private func toggle() async {
        guard !busy, let owner = store.user?.id else { return }
        busy = true; defer { busy = false }
        do {
            let updated = try await APIClient.shared.setSocialLike(target: target, id: id, liked: !liked)
            guard owner == store.user?.id else { return }
            result = updated; onUpdate(updated)
        } catch { self.error = error.localizedDescription }
    }
}

struct CommunityConversationView: View {
    let initial: CommunityPost
    var onUpdate: (CommunityPost) -> Void = { _ in }
    @Environment(AppStore.self) private var store
    @Environment(\.accountTheme) private var theme
    @State private var post: CommunityPost?
    @State private var loading = true
    @State private var error: String?
    @State private var signIn = false
    private var current: CommunityPost { post ?? initial }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                CommunityPostCard(post: current, onUpdate: { post = $0; onUpdate($0) }, showsConversation: false)
                if store.user != nil {
                    CommunityComposer(postID: initial.id) { Task { await load() } }
                        .id("comment-editor")
                } else {
                    Button("Sign in to comment", systemImage: "person.crop.circle") { signIn = true }.buttonStyle(.glass)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Conversation").font(.title2.bold())
                    Text("\(current.commentCount ?? current.comments?.count ?? 0)")
                        .font(.subheadline.bold()).foregroundStyle(theme.accent)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(theme.accent.opacity(0.12), in: Capsule())
                }.padding(.top, 8)
                if loading { AsunaLoadingView(title: "Loading comments…", accent: theme.accent).frame(maxWidth: .infinity) }
                if let error { FailureView(message: error) { Task { await load() } } }
                ForEach(current.comments ?? []) { comment in
                    CommunityCommentRow(comment: comment, postID: initial.id,
                                        requireSignIn: { signIn = true },
                                        onReplied: { Task { await load() } })
                }
                if !loading && error == nil && (current.comments ?? []).isEmpty {
                    ContentUnavailableView("Start the conversation", systemImage: "bubble.left.and.bubble.right", description: Text("Be the first to leave a comment."))
                }
            }.padding(24).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }.asunaSurface().navigationTitle("Conversation")
            .task(id: store.user?.id) { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $signIn) { NavigationStack { AccountView() }.environment(store).frame(minWidth: 320, minHeight: 360) }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let response: CommunityPostResponse = try await APIClient.shared.request("\(store.user == nil ? "public/api" : "api")/activity/\(initial.id)")
            try Task.checkCancellation()
            post = response.item; onUpdate(response.item)
        } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct CommunityComposer: View {
    let postID: Int?
    var reply: CommunityComment? = nil
    var focusToken: UUID? = nil
    var onCancelReply: () -> Void = {}
    let onSent: () -> Void
    @Environment(AppStore.self) private var store
    @State private var text = ""
    @State private var attachment = ""
    @Environment(\.accountTheme) private var theme
    @State private var showAttachment = false
    @State private var previewAttachment = false
    @FocusState private var editorFocused: Bool
    @State private var sending = false
    @State private var error: String?
    private var cleanText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanAttachment: String { attachment.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var attachmentValid: Bool { cleanAttachment.isEmpty || ProfileBio.safeURL(cleanAttachment) != nil }
    private var canSend: Bool { !sending && store.user != nil && attachmentValid && (!cleanText.isEmpty || !cleanAttachment.isEmpty) }
    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                if let user = store.user { CommunityAuthorHeader(user: user, date: nil) }
                if let reply {
                    HStack(alignment: .top, spacing: 8) {
                        CommunityReplyQuote(name: reply.user?.displayName ?? reply.user?.username ?? "comment", text: reply.body)
                        Button(action: onCancelReply) { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Cancel reply")
                    }
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(postID == nil ? "What would you like to share?" : "Add to the conversation…")
                            .foregroundStyle(.tertiary).padding(.horizontal, 14).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text).font(.body).scrollContentBackground(.hidden)
                        .padding(8).frame(height: postID == nil ? 110 : 88)
                        .focused($editorFocused).disabled(sending)
                        .accessibilityLabel(postID == nil ? "Post text" : "Comment text")
                }
                .background(theme.accent.opacity(0.035), in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(theme.accent.opacity(editorFocused ? 0.45 : 0.15)))
                if showAttachment {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Attach media", systemImage: "photo.on.rectangle").font(.subheadline.bold())
                            Spacer()
                            Button { attachment = ""; showAttachment = false; previewAttachment = false } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Remove attachment")
                        }
                        TextField("Paste an image, GIF, or video link", text: $attachment)
                            .textFieldStyle(.plain).autocorrectionDisabled().disabled(sending)
                            .padding(12).background(.background.opacity(0.4), in: .rect(cornerRadius: 12))
                            .onChange(of: attachment) { _, _ in previewAttachment = false }
                        if !attachmentValid {
                            Label("Enter a full http or https media URL.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red)
                        } else if !cleanAttachment.isEmpty {
                            Button("Preview attachment", systemImage: "eye") { previewAttachment = true }.buttonStyle(.glass).controlSize(.small)
                        }
                        if previewAttachment {
                            CommunityAttachmentView(attachment: PostAttachment(url: cleanAttachment, previewUrl: nil, title: nil))
                        }
                    }.padding(16).background(theme.accent.opacity(0.05), in: .rect(cornerRadius: 18))
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle").font(.subheadline)
                        .foregroundStyle(.red).textSelection(.enabled)
                }
                HStack(spacing: 14) {
                    Button { showAttachment.toggle() } label: { Label(cleanAttachment.isEmpty ? "Media" : "Media attached", systemImage: cleanAttachment.isEmpty ? "photo.badge.plus" : "photo.badge.checkmark") }
                        .buttonStyle(.glass).disabled(sending)
                    Spacer(minLength: 0)
                    if sending { AsunaLoadingView(compact: true).accessibilityLabel("Sending") }
                    Button { Task { await send() } } label: {
                        Label(postID == nil ? "Post" : "Send", systemImage: "arrow.up")
                            .font(.subheadline.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                    }.buttonStyle(.glassProminent).tint(theme.accent).disabled(!canSend)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.accent.opacity(0.045), in: .rect(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(theme.accent.opacity(0.16)))
                .onChange(of: focusToken) { _, value in editorFocused = value != nil }
    }
    private func send() async {
        guard canSend else { return }
        sending = true; error = nil; defer { sending = false }
        do {
            try await APIClient.shared.publishCommunity(body: cleanText, attachment: cleanAttachment, postID: postID, parentID: reply?.id)
            text = ""; attachment = ""; showAttachment = false; previewAttachment = false
            editorFocused = false; onSent()
        } catch { self.error = error.localizedDescription }
    }
}

private struct CommunityAuthorHeader: View {
    let user: User
    let date: String?
    var body: some View {
        NavigationLink { UserProfileView(username: user.username) } label: {
            HStack(spacing: 12) {
                ProfileAvatar(user: user, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(user.displayName ?? user.username).font(.headline).lineLimit(1)
                        UserRoleBadges(user: user)
                    }
                    Text("@\(user.username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let date { Text(date.prefix(10)).font(.caption2).foregroundStyle(.tertiary) }
            }
        }.buttonStyle(.plain)
    }
}

private struct CommunityBody: View {
    let text: String
    private var hasMedia: Bool {
        text.range(of: #"(?i)(?:img\d*|webm(?:-sound)?|video)\(\s*https?://|<img\b"#, options: .regularExpression) != nil
    }
    var body: some View {
        if hasMedia { RichProfileBio(text: text, mediaMaxHeight: 360) }
        else { Text(text).font(.body).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
    }
}

private struct CommunityReplyQuote: View {
    let name: String
    let text: String?
    @Environment(\.accountTheme) private var theme
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(theme.accent.opacity(0.65)).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                Label("Replying to \(name)", systemImage: "arrowshape.turn.up.left").font(.caption.bold()).foregroundStyle(theme.accent)
                if let text, !text.isEmpty { Text(text).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true).padding(12)
            .background(theme.accent.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}

private struct CommunityCommentRow: View {
    let comment: CommunityComment
    let postID: Int
    let requireSignIn: () -> Void
    let onReplied: () -> Void
    @Environment(\.accountTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var replyFocus: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let user = comment.user { CommunityAuthorHeader(user: user, date: comment.createdAt) }
            if let reference = comment.replyTo {
                CommunityReplyQuote(name: reference.user?.displayName ?? reference.user?.username ?? "comment", text: reference.body)
            } else if comment.parentId != nil {
                Label("Reply", systemImage: "arrowshape.turn.up.left").font(.caption).foregroundStyle(theme.accent)
            }
            if let text = comment.body, !text.isEmpty { CommunityBody(text: text) }
            CommunityAttachmentView(attachment: comment.attachment)
            HStack(spacing: 10) {
                SocialLikeButton(target: "activity_comment", id: comment.id, initialLiked: comment.userLiked ?? false, initialCount: comment.likeCount ?? 0)
                Button {
                    guard store.user != nil else { requireSignIn(); return }
                    setExpanded(!expanded)
                } label: {
                    Label(expanded ? "Close reply" : "Reply", systemImage: expanded ? "chevron.up" : "arrowshape.turn.up.left")
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 40)
                }.buttonStyle(.plain).foregroundStyle(expanded ? theme.accent : .secondary)
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                Spacer(minLength: 0)
            }
            if store.user != nil {
                CommunityComposer(postID: postID, reply: comment, focusToken: replyFocus,
                                  onCancelReply: { setExpanded(false) }) {
                    setExpanded(false); onReplied()
                }
                .frame(height: expanded ? nil : 0, alignment: .top)
                .clipped().opacity(expanded ? 1 : 0)
                .allowsHitTesting(expanded).accessibilityHidden(!expanded)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent.opacity(0.045), in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.accent.opacity(0.08)))
            .padding(.leading, comment.parentId == nil ? 0 : 18)
    }
    private func setExpanded(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded = value }
        replyFocus = value ? UUID() : nil
    }
}
