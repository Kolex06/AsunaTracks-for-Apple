import SwiftUI
import Observation

@MainActor @Observable
final class AppStore {
    var user: User?
    var entries: [ListEntry] = []
    var accountLoaded = false
    var loadingList = false
    var message: String?
    var busyIDs: Set<String> = []
    private var refreshingPreferences = false
    func bootstrap() async {
        do {
            let response: UserResponse = try await APIClient.shared.request("api/me")
            user = response.user
            accountLoaded = true
            if user != nil { await refreshAccountTheme(); try await refreshList() }
            else {
                ProgressPublisher.clear()
                #if os(iOS)
                await ProgressLiveActivity.endAll()
                #endif
            }
        } catch { message = error.localizedDescription }
        accountLoaded = true
    }
    func refreshAccountTheme() async {
        guard let accountID = user?.id, !refreshingPreferences else { return }
        refreshingPreferences = true
        defer { refreshingPreferences = false }
        do {
            let response: UserResponse = try await APIClient.shared.request("api/account/settings")
            guard user?.id == accountID, response.user?.id == accountID else { return }
            let widgetAppearanceChanged = user?.accountTheme != response.user?.accountTheme || user?.username != response.user?.username
            user = response.user
            if widgetAppearanceChanged { ProgressPublisher.publish(entries: entries, user: user) }
        } catch { /* Keep the last valid account theme when offline. */ }
    }
    func refreshList() async throws {
        guard let accountID = user?.id else { entries = []; ProgressPublisher.clear(); return }
        loadingList = true
        defer { loadingList = false }
        let response: ListResponse = try await APIClient.shared.request("api/list")
        await applyList(response, accountID: accountID)
    }
    func applyList(_ response: ListResponse, accountID: Int) async {
        guard user?.id == accountID else { return }
        entries = response.items
        ProgressPublisher.publish(entries: entries, user: user)
        #if os(iOS)
        await ProgressLiveActivity.update(entries: entries)
        #endif
    }
    func entry(for media: Media) -> ListEntry? { entries.first { $0.id == media.identity } }
    func advance(_ entry: ListEntry) async throws {
        guard !busyIDs.contains(entry.id) else { return }
        busyIDs.insert(entry.id)
        defer { busyIDs.remove(entry.id) }
        try await APIClient.shared.advance(entry)
        try await refreshList()
    }
    func signOut() async throws {
        try await APIClient.shared.logout()
        user = nil; entries = []
        ProgressPublisher.clear()
        #if os(iOS)
        await ProgressLiveActivity.endAll()
        #endif
    }
}

#if !os(macOS)
@main
struct AsunaTracksApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "dark"
    var body: some Scene {
        WindowGroup { Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-progress") { ProgressPreviewView() }
            else { RootView() }
            #else
            RootView()
            #endif
        }.environment(store).environment(\.accountTheme, store.user?.accountTheme ?? AccountTheme()).tint((store.user?.accountTheme ?? AccountTheme()).accent)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark).task {
                    #if DEBUG
                    guard !ProcessInfo.processInfo.arguments.contains("--preview-progress") else { return }
                    #endif
                    await store.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active && store.accountLoaded { Task { await store.refreshAccountTheme(); try? await store.refreshList() } } } }
    }
}

#endif
