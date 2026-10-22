import Foundation

enum TestError: Error { case offline, unauthorized }
enum ListStep: Sendable { case list(ListResponse), failure(TestError) }

actor FakeWatchAPI: WatchServing {
    var current: User?
    var steps: [ListStep]
    var written: [ListEntry] = []
    var forgotten = false
    var failWrite = false
    var logoutCalled = false
    init(user: User?, steps: [ListStep]) { current = user; self.steps = steps }
    func sessionUser() async throws -> UserResponse { UserResponse(user: current) }
    func settingsUser() async throws -> UserResponse { UserResponse(user: current) }
    func loadList() async throws -> ListResponse {
        precondition(!steps.isEmpty, "Unexpected server request")
        switch steps.removeFirst() {
        case .list(let list): return list
        case .failure(.offline): throw URLError(.notConnectedToInternet)
        case .failure(.unauthorized): throw ServiceError.authenticationRequired
        }
    }
    func login(username: String, password: String) async throws -> UserResponse { UserResponse(user: current) }
    func logout() async throws { logoutCalled = true }
    func forgetSession() async { forgotten = true }
    func advance(_ entry: ListEntry) async throws {
        if failWrite { throw URLError(.networkConnectionLost) }
        written.append(entry)
    }
    func setFailWrite() { failWrite = true }
}

@main enum WatchStoreTests {
    @MainActor static func main() async throws {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("search.json")
        let media = try Coding.decoder.decode(MediaPage.self, from: Data(contentsOf: fixture)).items[0]
        let account = User(id: 7, username: "watch-test", displayName: nil, uiTheme: "blue", uiAccentColor: "#38bdf8", uiColorIntensity: 100)
        let original = ListEntry(media: media, status: "watching", progress: 3, progressVolumes: 2,
            rating: nil, favorite: true, notes: "Preserve this note", repeatCount: 2, startDate: "2026-10-01", finishDate: nil)
        var changed = original; changed.progress = 4
        func response(_ entry: ListEntry) -> ListStep { .list(ListResponse(items: [entry])) }
        var suites: [String] = []
        func defaults() -> UserDefaults {
            let name = "AsunaTracks-WatchTests-\(UUID().uuidString)"
            suites.append(name)
            return UserDefaults(suiteName: name)!
        }
        defer { for name in suites { UserDefaults(suiteName: name)!.removePersistentDomain(forName: name) } }

        // No phone/session transport exists in this test: every action uses the direct API.
        let api = FakeWatchAPI(user: account, steps: [response(original), response(original), response(changed)])
        let cache = defaults()
        let store = WatchStore(api: api, defaults: cache)
        await store.refresh()
        precondition(store.user?.id == 7 && store.entries[0].progress == 3)
        precondition(store.theme == account.accountTheme)
        await store.advance(id: original.id)
        precondition(store.entries[0].progress == 4 && !store.loading && !store.needsRefresh)
        let writes = await api.written
        precondition(writes.count == 1 && writes[0].notes == original.notes && writes[0].repeatCount == 2)
        let offlineStore = WatchStore(api: api, defaults: cache)
        precondition(offlineStore.entries[0].progress == 4 && offlineStore.theme == account.accountTheme)

        let staleAPI = FakeWatchAPI(user: account, steps: [response(original), response(changed)])
        let stale = WatchStore(api: staleAPI, defaults: defaults())
        await stale.refresh(); await stale.advance(id: original.id)
        let staleWrites = await staleAPI.written
        precondition(staleWrites.isEmpty && stale.entries[0].progress == 4 && stale.message != nil)

        let offlineAPI = FakeWatchAPI(user: account, steps: [response(original), .failure(.offline)])
        let offline = WatchStore(api: offlineAPI, defaults: defaults())
        await offline.refresh(); await offline.advance(id: original.id)
        let offlineWrites = await offlineAPI.written
        precondition(offlineWrites.isEmpty && offline.entries[0].progress == 3 && !offline.loading)

        let expiredAPI = FakeWatchAPI(user: account, steps: [response(original), .failure(.unauthorized)])
        let expiredCache = defaults()
        let expired = WatchStore(api: expiredAPI, defaults: expiredCache)
        await expired.refresh(); await expired.advance(id: original.id)
        let cleared = await expiredAPI.forgotten
        precondition(cleared && expired.user == nil && expired.entries.isEmpty)
        precondition(expiredCache.data(forKey: "cachedList") == nil)

        // If the write response is uncertain, require a refresh and never silently retry.
        let uncertainAPI = FakeWatchAPI(user: account, steps: [response(original), response(original)])
        await uncertainAPI.setFailWrite()
        let uncertain = WatchStore(api: uncertainAPI, defaults: defaults())
        await uncertain.refresh(); await uncertain.advance(id: original.id)
        precondition(uncertain.needsRefresh && uncertain.message != nil)
        await uncertain.advance(id: original.id) // Guarded: no extra network request.

        // A successful write followed by a failed refresh must not invite another increment.
        let refreshFailureAPI = FakeWatchAPI(user: account, steps: [response(original), response(original), .failure(.offline), response(changed)])
        let refreshFailure = WatchStore(api: refreshFailureAPI, defaults: defaults())
        await refreshFailure.refresh(); await refreshFailure.advance(id: original.id)
        precondition(refreshFailure.needsRefresh && refreshFailure.message?.contains("Update sent") == true)
        await refreshFailure.advance(id: original.id)
        let singleWrite = await refreshFailureAPI.written
        precondition(singleWrite.count == 1)
        await refreshFailure.refresh()
        precondition(!refreshFailure.needsRefresh && refreshFailure.entries[0].progress == 4)

        await store.signOut()
        let loggedOut = await api.logoutCalled
        precondition(loggedOut && store.user == nil && store.entries.isEmpty && cache.data(forKey: "cachedList") == nil)

        let loginAPI = FakeWatchAPI(user: account, steps: [response(original)])
        let loginStore = WatchStore(api: loginAPI, defaults: defaults())
        await loginStore.login(username: "watch-test", password: "test-only")
        precondition(loginStore.user?.id == account.id && loginStore.entries.count == 1)

        print("PASS: direct Watch refresh/login/update; theme/cache; stale progress; offline and expired sessions; uncertain writes; post-write refresh; sign-out cleanup")
    }
}
