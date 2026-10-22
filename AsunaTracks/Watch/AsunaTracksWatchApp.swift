import SwiftUI

private let watchNavy = Color(red: 0.02, green: 0.035, blue: 0.086)

extension WatchStore {
    var accent: Color { let c = theme.accentRGB; return Color(red: c[0], green: c[1], blue: c[2]) }
}

@main struct AsunaTracksWatchApp: App {
    @State private var store = WatchStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup { WatchLibraryView().environment(store).tint(store.accent)
            .task { await store.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && store.accountLoaded { Task { await store.refresh() } }
            } }
    }
}

struct WatchLibraryView: View {
    @Environment(WatchStore.self) private var store
    @State private var showSignIn = false
    @State private var openedID: String?
    var body: some View {
        NavigationStack {
            List {
                if let user = store.user {
                    Section {
                        HStack(spacing: 10) {
                            if let avatar = user.avatarUrl, !avatar.isEmpty {
                                AsunaArtwork(path: avatar, accent: store.accent).frame(width: 36, height: 36).clipShape(Circle())
                            } else { Image(systemName: "person.crop.circle.fill").font(.title).foregroundStyle(store.accent) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.displayName ?? user.username).font(.headline).lineLimit(1)
                                Text("@\(user.username)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                if store.user == nil && store.accountLoaded {
                    Section {
                        Button("Sign in", systemImage: "person.crop.circle") { showSignIn = true }
                        Text("Sign in once on your Watch. Then update your list directly from AsunaTracks.").font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if store.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkles").font(.title).foregroundStyle(store.accent)
                        Text("Every story, one place.").font(.headline)
                        Text(store.user == nil ? "Your anime and manga, on your wrist." : "Add a title to your in-progress list on AsunaTracks.").font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical)
                }
                ForEach(store.entries) { entry in
                    NavigationLink { WatchProgressView(id: entry.id) } label: {
                        HStack(spacing: 10) {
                            WatchCover(media: entry.media)
                                .frame(width: 48, height: 70)
                                .clipShape(.rect(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 6) {
                            Text(entry.media.displayTitle).font(.headline).lineLimit(2)
                            Text("\(max(0, entry.progress ?? 0)) / \(entry.media.total > 0 ? String(entry.media.total) : "?") \(entry.media.unit)")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if entry.media.total > 0 { ProgressView(value: Double(max(0, min(entry.progress ?? 0, entry.media.total))), total: Double(entry.media.total)).tint(store.accent) }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                if let user = store.user {
                    Section {
                        Text("@\(user.username)").font(.caption)
                        Button("Sign out", role: .destructive) { Task { await store.signOut() } }.disabled(store.loading)
                    }
                }
                if let date = store.lastUpdated { Text("Synced \(date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
            }.scrollContentBackground(.hidden)
                .background(LinearGradient(colors: [store.accent.opacity(0.12), watchNavy], startPoint: .topLeading, endPoint: .bottomTrailing))
                .navigationTitle("AsunaTracks")
                .navigationDestination(item: $openedID) { id in WatchProgressView(id: id) }
                .onOpenURL { url in
                    let parts = url.pathComponents.filter { $0 != "/" }
                    if url.scheme == "asunatracks", url.host == "media", parts.count == 2, Int(parts[1]) != nil {
                        Task { await store.refresh(); openedID = "\(parts[0]):\(parts[1])" }
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(store.loading) } }
                .sheet(isPresented: $showSignIn) { WatchSignInView() }
                .overlay { if store.loading { AsunaLoadingView(title: "Syncing your list…", accent: store.accent).padding().background(.regularMaterial, in: .rect(cornerRadius: 22)) } }
                .alert("AsunaTracks", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                    Button("OK") { store.message = nil }
                } message: { Text(store.message ?? "") }
        }
    }
}

private struct WatchCover: View {
    let media: Media
    @Environment(WatchStore.self) private var store
    var body: some View { AsunaArtwork(path: media.imageUrl, accent: store.accent) }
}

struct WatchProgressView: View {
    let id: String
    @Environment(WatchStore.self) private var store
    @State private var successfulUpdates = 0
    var entry: ListEntry? { store.entries.first { $0.id == id } }
    var body: some View {
        ScrollView {
            if let entry {
                VStack(spacing: 14) {
                    WatchCover(media: entry.media)
                        .frame(width: 104, height: 148)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.16)) }
                        .shadow(color: store.accent.opacity(0.25), radius: 12, y: 4)
                    Text(entry.media.displayTitle).font(.headline).multilineTextAlignment(.center)
                    if entry.media.total > 0 {
                        Gauge(value: Double(max(0, min(entry.progress ?? 0, entry.media.total))), in: 0...Double(entry.media.total)) {
                            Text(entry.media.unit.capitalized)
                        } currentValueLabel: { Text("\(entry.progress ?? 0)") }
                            .gaugeStyle(.accessoryCircular).tint(store.accent).scaleEffect(1.25).padding(12)
                    } else { Text("\(entry.progress ?? 0) \(entry.media.unit)").font(.title2.bold()) }
                    Text(store.needsRefresh ? "Refresh your list before logging again." : "Updates AsunaTracks directly. An internet connection is required.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(.horizontal, 8)
            } else { Text("All caught up! Refresh to see your current titles.").padding() }
        }
        .background(LinearGradient(colors: [store.accent.opacity(0.18), watchNavy, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
        .navigationTitle("Progress")
        .safeAreaInset(edge: .bottom, spacing: 4) {
            if let entry {
                Button {
                    Task {
                        let previous = entry.progress ?? 0
                        await store.advance(id: id)
                        if let updated = self.entry, (updated.progress ?? 0) > previous, !store.needsRefresh {
                            successfulUpdates += 1
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if store.loading { AsunaLoadingView(title: "Updating progress…", accent: store.accent, compact: true) }
                        else { Image(systemName: "plus") }
                        Text(store.needsRefresh ? "Refresh needed" : "Log \(entry.media.mediaType == "manga" ? "chapter" : "episode") \((entry.progress ?? 0) + 1)")
                            .font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                    }.frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glassProminent)
                .disabled(store.loading || store.needsRefresh || store.user == nil || !entry.canAdvance)
                .padding(.horizontal, 8).padding(.bottom, 2)
                .sensoryFeedback(.success, trigger: successfulUpdates)
            }
        }
    }
}

struct WatchSignInView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Username", text: $username)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password).textContentType(.password)
                Button {
                    Task {
                        await store.login(username: username, password: password)
                        password = ""
                        if store.user != nil { dismiss() }
                    }
                } label: {
                    if store.loading { AsunaLoadingView(title: "Signing in…", accent: store.accent, compact: true) }
                    else { Text("Sign in") }
                }.disabled(store.loading || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                Text("Use your AsunaTracks username and password. Your Watch stores a secure session, never your password.").font(.footnote).foregroundStyle(.secondary)
                if let message = store.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Sign in")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { password = ""; dismiss() } } }
                .onDisappear { password = "" }
        }
    }
}
