import Foundation
import Observation

protocol WatchServing: Sendable {
    func sessionUser() async throws -> UserResponse
    func settingsUser() async throws -> UserResponse
    func loadList() async throws -> ListResponse
    func login(username: String, password: String) async throws -> UserResponse
    func logout() async throws
    func forgetSession() async
    func advance(_ entry: ListEntry) async throws
}

extension APIClient: WatchServing {
    func sessionUser() async throws -> UserResponse { try await request("api/me") }
    func settingsUser() async throws -> UserResponse { try await request("api/account/settings") }
    func loadList() async throws -> ListResponse { try await request("api/list") }
    func forgetSession() { SessionVault.clear() }
}

/// All Watch reads and writes go directly to AsunaTracks. No WCSession dependency.
@MainActor @Observable
final class WatchStore {
    private(set) var entries: [ListEntry] = []
    private(set) var user: User?
    private(set) var theme = AccountTheme()
    private(set) var loading = false
    private(set) var accountLoaded = false
    private(set) var needsRefresh = false
    var message: String?
    private(set) var lastUpdated: Date?
    private let api: any WatchServing
    private let defaults: UserDefaults
    private var cachedAccountID: Int?

    init(api: any WatchServing = APIClient.shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        // Legacy phone snapshots have no owner and are intentionally not restored.
        cachedAccountID = defaults.object(forKey: "watchAccountID") as? Int
        if cachedAccountID != nil, let data = defaults.data(forKey: "cachedList"),
           let list = try? Coding.decoder.decode(ListResponse.self, from: data) {
            entries = list.items
            theme = list.theme ?? AccountTheme()
            lastUpdated = defaults.object(forKey: "lastUpdated") as? Date
        }
    }
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false; accountLoaded = true }
        do {
            guard let current = try await api.sessionUser().user else {
                await api.forgetSession()
                user = nil; clearCache(); needsRefresh = false
                return
            }
            if cachedAccountID != current.id { clearCache() }
            user = current
            cachedAccountID = current.id
            theme = current.accountTheme
            do {
                if let settings = try await api.settingsUser().user, settings.id == current.id {
                    user = settings; theme = settings.accountTheme
                }
            } catch ServiceError.authenticationRequired { throw ServiceError.authenticationRequired }
            catch { /* List refresh still works if only the theme endpoint is unavailable. */ }
            apply(try await api.loadList())
            needsRefresh = false
        } catch { await handle(error) }
    }
    func login(username: String, password: String) async {
        guard !loading else { return }
        loading = true
        defer { loading = false; accountLoaded = true }
        do {
            guard let signedIn = try await api.login(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password).user else {
                throw ServiceError.authenticationRequired
            }
            clearCache()
            user = signedIn; cachedAccountID = signedIn.id; theme = signedIn.accountTheme
            apply(try await api.loadList())
            needsRefresh = false
        } catch { await handle(error) }
    }
    func advance(id: String) async {
        guard !loading, !needsRefresh, user != nil,
              let displayed = entries.first(where: { $0.id == id }), displayed.canAdvance else { return }
        loading = true
        defer { loading = false }
        do {
            // Re-read before writing; cached or changed progress must never be blindly advanced.
            let freshList = try await api.loadList()
            apply(freshList)
            guard let fresh = freshList.items.first(where: { $0.id == id }), fresh.canAdvance,
                  fresh.progress == displayed.progress, fresh.status == displayed.status else {
                message = "This title changed on AsunaTracks. Your list is refreshed; check it before logging again."
                return
            }
            do { try await api.advance(fresh) }
            catch {
                needsRefresh = true
                if case ServiceError.authenticationRequired = error { await handle(error) }
                else { message = "Couldn’t confirm the update. Refresh your list before trying again." }
                return
            }
            do { apply(try await api.loadList()); needsRefresh = false }
            catch {
                needsRefresh = true
                if case ServiceError.authenticationRequired = error { await handle(error) }
                else { message = "Update sent to AsunaTracks. Refresh to see the latest progress." }
            }
        } catch { await handle(error) }
    }
    func signOut() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do { try await api.logout() }
        catch { message = "Signed out on this Watch. The server couldn’t be reached to end the session." }
        await api.forgetSession()
        user = nil; clearCache(); needsRefresh = false
    }
    private func handle(_ error: Error) async {
        if case ServiceError.authenticationRequired = error {
            await api.forgetSession()
            user = nil; clearCache(); needsRefresh = false
            message = "Sign in on this Watch to update your AsunaTracks list."
        } else { message = error.localizedDescription }
    }
    private func apply(_ list: ListResponse) {
        entries = list.items.filter(\.active)
        lastUpdated = Date()
        ProgressPublisher.publish(entries: entries, user: user)
        if let data = try? Coding.encoder.encode(ListResponse(items: entries, theme: theme)) {
            defaults.set(data, forKey: "cachedList")
            defaults.set(lastUpdated, forKey: "lastUpdated")
            defaults.set(cachedAccountID, forKey: "watchAccountID")
        }
    }
    private func clearCache() {
        ProgressPublisher.clear()
        entries = []; theme = AccountTheme(); lastUpdated = nil; cachedAccountID = nil
        for key in ["cachedList", "lastUpdated", "watchAccountID"] { defaults.removeObject(forKey: key) }
    }
}
