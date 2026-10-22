import SwiftUI

struct LibraryView: View {
    @Environment(\.accountTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var filter = "all"
    @State private var category = "all"
    @State private var sort = "recent"
    @State private var query = ""
    @State private var favoritesOnly = false
    private var filtered: [ListEntry] {
        let result = store.entries.filter { entry in
            (filter == "all" || (LibraryStatus(rawValue: filter)?.matches(entry) ?? false)) &&
            (category == "all" || (category == "novels" ? (entry.media.type ?? "").localizedCaseInsensitiveContains("novel") : category == "manga" ? entry.media.mediaType == "manga" && !(entry.media.type ?? "").localizedCaseInsensitiveContains("novel") : entry.media.mediaType == category)) &&
            (!favoritesOnly || entry.favorite == true) &&
            (query.isEmpty || entry.media.displayTitle.localizedCaseInsensitiveContains(query))
        }
        switch sort {
        case "title": return result.sorted { $0.media.displayTitle.localizedStandardCompare($1.media.displayTitle) == .orderedAscending }
        case "score": return result.sorted { ($0.rating ?? -1) > ($1.rating ?? -1) }
        case "progress": return result.sorted { ($0.progress ?? 0) > ($1.progress ?? 0) }
        default: return result.enumerated().sorted {
            let a = WidgetDate.parse($0.element.updatedAt), b = WidgetDate.parse($1.element.updatedAt)
            return a == b ? $0.offset < $1.offset : (a ?? .distantPast) > (b ?? .distantPast)
        }.map(\.element)
        }
    }
    var body: some View {
        Group {
            if !store.accountLoaded { AsunaLoadingPage(title: "Connecting…") }
            else if store.user == nil { SignInPrompt() }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Your stories").font(.largeTitle.bold())
                                Text("\(store.entries.count) tracked · \(store.entries.filter(\.active).count) in progress").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { favoritesOnly.toggle() } label: { Image(systemName: favoritesOnly ? "heart.fill" : "heart") }
                                .buttonStyle(.glass).tint(favoritesOnly ? .pink : theme.accent).accessibilityLabel("Only favorites")
                                .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
                        }
                        HStack {
                            Picker("Category", selection: $category) {
                                Text("All titles").tag("all"); Text("Anime").tag("anime"); Text("Manga").tag("manga"); Text("Novels").tag("novels")
                            }
                            Spacer()
                            Picker("Sort", selection: $sort) {
                                Text("Recently updated").tag("recent"); Text("Title").tag("title"); Text("Your score").tag("score"); Text("Progress").tag("progress")
                            }
                        }.pickerStyle(.menu)
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                Button("All · \(store.entries.count)") { filter = "all" }.buttonStyle(.glass).tint(filter == "all" ? theme.accent : .secondary)
                                ForEach(LibraryStatus.allCases) { status in
                                    Button("\(status.label) · \(store.entries.filter { status.matches($0) }.count)") { filter = status.rawValue }
                                        .buttonStyle(.glass).tint(StatusStyle.color(status.rawValue))
                                        .overlay(Capsule().strokeBorder(filter == status.rawValue ? StatusStyle.color(status.rawValue) : .clear, lineWidth: 2))
                                        .accessibilityAddTraits(filter == status.rawValue ? .isSelected : [])
                                }
                            }.padding(.vertical, 3)
                        }.appRailScrollIndicators()
                        if filtered.isEmpty {
                            ContentUnavailableView("No titles here", systemImage: "books.vertical", description: Text("Try another filter, or add titles from Browse."))
                        }
                        ForEach(filtered) { entry in
                            HStack(spacing: 14) {
                                NavigationLink { MediaDetailView(initial: entry.media) } label: {
                                    HStack(spacing: 14) {
                                        Poster(media: entry.media).frame(width: 66, height: 96).clipShape(.rect(cornerRadius: 12))
                                        VStack(alignment: .leading, spacing: 7) {
                                            Text(entry.media.displayTitle).font(.headline).lineLimit(2)
                                            StatusBadge(status: entry.status)
                                            Text("\(entry.progress ?? 0) / \(entry.media.total > 0 ? String(entry.media.total) : "?") \(entry.media.unit)").font(.caption).foregroundStyle(.secondary)
                                            if entry.media.total > 0 { StatusProgress(value: Double(min(entry.progress ?? 0, entry.media.total)), total: Double(entry.media.total), status: entry.status) }
                                            if let rating = entry.rating { Text(String(format: "Your score %.1f / 10", rating)).font(.caption2).foregroundStyle(.secondary) }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if entry.canAdvance {
                                    Button { Task { do { try await store.advance(entry) } catch { store.message = error.localizedDescription } } } label: {
                                        Group { if store.busyIDs.contains(entry.id) { AsunaLoadingView(title: "Updating…", accent: theme.accent, compact: true) } else { Image(systemName: "plus") } }.frame(width: 44, height: 44)
                                    }.buttonStyle(.glass).disabled(store.busyIDs.contains(entry.id))
                                        .accessibilityLabel("Log next \(entry.media.mediaType == "manga" ? "chapter" : "episode") of \(entry.media.displayTitle)")
                                }
                            }.padding(14).background(theme.accent.opacity(0.05), in: .rect(cornerRadius: 20))
                                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(StatusStyle.color(entry.status).opacity(0.4)))
                                .appCardInteraction()
                        }
                    }.padding(20).frame(maxWidth: 1100).frame(maxWidth: .infinity)
                }
                .searchable(text: $query, prompt: "Filter your list")
                .refreshable { do { try await store.refreshList() } catch { store.message = error.localizedDescription } }
                .toolbar { ToolbarItem(placement: .primaryAction) {
                    Button { Task { do { try await store.refreshList() } catch { store.message = error.localizedDescription } } } label: {
                        if store.loadingList { AsunaLoadingView(title: "Syncing list…", accent: theme.accent, compact: true) }
                        else { Image(systemName: "arrow.clockwise") }
                    }.disabled(store.loadingList).accessibilityLabel("Refresh list")
                } }
            }
        }.asunaSurface().navigationTitle("My List")
    }
}

struct SignInPrompt: View {
    var body: some View {
        ContentUnavailableView {
            Label("Your stories, in sync", systemImage: "rectangle.stack.badge.person.crop")
        } description: { Text("Sign in to AsunaTracks to see your list and update your progress across devices.") }
        actions: { NavigationLink("Sign in") { AccountView() }.buttonStyle(.glassProminent) }
    }
}

struct AccountView: View {
    @Environment(\.accountTheme) private var theme
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "dark"
    private enum LoginField: Hashable { case username, password }
    @FocusState private var loginField: LoginField?
    @State private var username = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        Form {
            if let user = store.user {
                Section {
                    Label(user.displayName ?? user.username, systemImage: "person.crop.circle.fill").font(.title2.bold())
                    Text("@\(user.username)").foregroundStyle(.secondary)
                }
                Section("Your collection") {
                    LabeledContent("Titles tracked", value: "\(store.entries.count)")
                    LabeledContent("In progress", value: "\(store.entries.filter(\.active).count)")
                    Text("Sign in once on your Apple Watch to update progress directly from your wrist. Your iPhone app can stay closed.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button(role: .destructive) { Task { loading = true; defer { loading = false }; do { try await store.signOut() } catch { self.error = error.localizedDescription } } } label: { if loading { AsunaLoadingView(title: "Signing out…", accent: theme.accent, compact: true) } else { Text("Sign out") } }.disabled(loading)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image.asunaLogo.resizable().scaledToFit().frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 20))
                        Text("Welcome back.").font(.largeTitle.bold())
                        Text("One home for every story you love.").foregroundStyle(.secondary)
                    }.padding(.vertical, 16)
                    TextField("Username", text: $username).keyboardType(.asciiCapable).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($loginField, equals: .username).submitLabel(.next)
                        .onSubmit { loginField = .password }.disabled(loading)
                    HStack {
                        Group {
                            if passwordVisible { TextField("Password", text: $password) }
                            else { SecureField("Password", text: $password) }
                        }
                        .keyboardType(.asciiCapable).textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($loginField, equals: .password).submitLabel(.go).disabled(loading)
                        .onSubmit { Task { await login() } }
                        Button {
                            passwordVisible.toggle()
                            loginField = .password
                        } label: {
                            Image(systemName: passwordVisible ? "eye.slash" : "eye")
                        }.buttonStyle(.borderless)
                            .accessibilityLabel(passwordVisible ? "Hide password" : "Show password")
                            .disabled(loading)
                    }
                    if let error { Text(error).foregroundStyle(.red).accessibilityLabel("Sign-in error: \(error)") }
                    Button { Task { await login() } } label: {
                        HStack { Text("Sign in"); Spacer(); if loading { AsunaLoadingView(title: "Signing in…", accent: theme.accent, compact: true) } else { Image(systemName: "arrow.right") } }
                    }.disabled(loading || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                } footer: { Text("Connects securely to your existing AsunaTracks account. Your password is never saved.") }
                Section {
                    Link("Create an account", destination: URL(string: "https://asunatracks.space")!)
                    Text("Use the website if you sign in through an external provider. Native provider login is not available in this version.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let error, store.user != nil { Section { Text(error).foregroundStyle(.red).accessibilityLabel("Error: \(error)") } }
            if let user = store.user {
                Section("Account preferences") {
                    LabeledContent("Explicit catalog items", value: user.showNsfw == true ? "Shown" : "Hidden")
                    LabeledContent("Profile visibility", value: user.profilePrivate == true ? "Private" : "Public")
                    LabeledContent("Watching now", value: user.watchingNowPrivate == true ? "Private" : "Public")
                    LabeledContent("Playback progress", value: user.playbackListPrivate == true ? "Private" : "Public")
                    Text("These preferences are managed by your AsunaTracks account and shared with the website.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Appearance") {
                Text("Accent colors follow your AsunaTracks account settings.").font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Circle().fill(theme.accent).frame(width: 24, height: 24)
                    VStack(alignment: .leading) {
                        Text("\((theme.name ?? "pink").capitalized) · \(Int(theme.intensity ?? 74))% intensity")
                        Text(store.user == nil ? "Sign in to sync your colors" : "Synced from your account").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") { Task { await store.refreshAccountTheme() } }.disabled(store.user == nil)
                }
                NavigationLink { SiteFeatureView(title: "Account settings", path: "/settings", forceWebsite: true) } label: {
                    Label("Profile, colors & account preferences", systemImage: "slider.horizontal.3")
                }
                Picker("Light / Dark", selection: $appearance) {
                    Text("AsunaTracks Dark").tag("dark")
                    Text("Light").tag("light")
                    Text("Follow system").tag("system")
                }
            }
            Section("AsunaTracks") {
                Link("Visit AsunaTracks", destination: URL(string: "https://asunatracks.space")!)
                Text("Made for iPhone, iPad, Mac & Apple Watch").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .asunaSurface().navigationTitle(store.user == nil ? "Sign in" : "Account")
        .task { await store.refreshAccountTheme() }
    }
    private func login() async {
        guard !loading, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else { return }
        loginField = nil
        loading = true; error = nil
        defer { loading = false }
        do {
            let response = try await APIClient.shared.login(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            guard let user = response.user else { throw ServiceError.message("Sign in did not complete. Please try again.") }
            store.user = user; password = ""; passwordVisible = false
            await store.refreshAccountTheme()
            do { try await store.refreshList() }
            catch { store.message = "Signed in successfully, but your list could not load. \(error.localizedDescription)" }
        } catch { self.error = error.localizedDescription }
    }
}

struct TrackingEditor: View {
    @Environment(\.accountTheme) private var theme
    let media: Media
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var status: LibraryStatus = .planning
    @State private var progress = 0
    @State private var rating = 0.0
    @State private var notes = ""
    @State private var favorite = false
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        Form {
            Section(media.displayTitle) {
                Picker("Status", selection: $status) { ForEach(LibraryStatus.allCases) { Text($0.label).tag($0) } }
                Stepper("\(progress) \(media.unit)", value: $progress, in: 0...(media.total > 0 ? media.total : 100_000))
                Toggle("Favorite", isOn: $favorite)
                if status == .completed {
                    VStack(alignment: .leading) {
                        Text(rating == 0 ? "Unrated" : String(format: "Score: %.1f / 10", rating))
                        Slider(value: $rating, in: 0...10, step: 0.1).accessibilityLabel("Score")
                    }
                }
            }
            Section("Notes") { TextEditor(text: $notes).frame(minHeight: 110).accessibilityLabel("Personal notes") }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.asunaSurface().navigationTitle("My progress").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button { Task { await save() } } label: { if saving { AsunaLoadingView(title: "Saving…", accent: theme.accent, compact: true) } else { Text("Save") } }.disabled(saving) }
            }
            .interactiveDismissDisabled(saving)
            .onAppear {
                if let entry = store.entry(for: media) {
                    status = LibraryStatus.allCases.first { $0.matches(entry) } ?? .planning
                    progress = entry.progress ?? 0; rating = entry.rating ?? 0; notes = entry.notes ?? ""; favorite = entry.favorite ?? false
                }
            }
    }
    private func save() async {
        saving = true; error = nil
        defer { saving = false }
        let old = store.entry(for: media)
        do {
            try await APIClient.shared.save(media, fields: TrackingFields(status: status.value(for: media), progress: progress,
                progressVolumes: old?.progressVolumes, rating: status == .completed && rating > 0 ? rating : nil,
                favorite: favorite, notes: notes, repeatCount: old?.repeatCount ?? 0, startDate: old?.startDate, finishDate: old?.finishDate))
            try await store.refreshList(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
