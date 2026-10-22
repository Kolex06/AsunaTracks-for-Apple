import Foundation

private final class MemoryState: WidgetProgressState, @unchecked Sendable {
    private let lock = NSLock()
    private var value = ProgressSnapshot(username: "widget-test", updatedAt: .now, items: [])
    var notices: [String] = []
    func read() -> ProgressSnapshot { lock.lock(); defer { lock.unlock() }; return value }
    func notice(_ message: String, username: String) { lock.lock(); defer { lock.unlock() }; notices.append(message) }
    func publish(_ list: ListResponse, user: User) {
        lock.lock(); defer { lock.unlock() }
        value = .init(username: user.username, updatedAt: .now, items: list.items.map {
            .init(id: $0.id, mediaID: $0.media.id, mediaType: $0.media.mediaType, title: $0.media.title,
                imageURL: nil, progress: $0.progress ?? 0, total: $0.media.total, unit: $0.media.unit, status: $0.status)
        })
    }
    func reload() {}
}
private actor FakeAPI: WidgetProgressServing {
    var entry: ListEntry
    var writes = 0
    var owner = "widget-test"
    var failRead = false
    var failAfterWrite = false
    init(entry: ListEntry, owner: String = "widget-test", failRead: Bool = false, failAfterWrite: Bool = false) {
        self.entry = entry; self.owner = owner; self.failRead = failRead; self.failAfterWrite = failAfterWrite
    }
    func widgetUser() async throws -> UserResponse { .init(user: User(id: 99, username: owner, displayName: nil)) }
    func widgetList() async throws -> ListResponse {
        if failRead || (failAfterWrite && writes > 0) { throw URLError(.notConnectedToInternet) }
        return .init(items: [entry])
    }
    func advance(_ entry: ListEntry) async throws { writes += 1; self.entry.progress = (entry.progress ?? 0) + 1 }
}
@main struct WidgetProgressActionTests {
    static func main() async throws {
        let media = try Coding.decoder.decode(Media.self, from: Data(#"{"id":32,"media_type":"anime","title":"Sample","episodes":25}"#.utf8))
        let entry = ListEntry(media: media, status: "watching", progress: 3)
        let state = MemoryState(), api = FakeAPI(entry: entry)
        let action = WidgetProgressAction(state: state)
        await action.advance(mediaID: 32, expectedProgress: 3, username: "widget-test", api: api)
        let writes = await api.writes
        precondition(writes == 1 && state.read().items.first?.progress == 4)
        await action.advance(mediaID: 32, expectedProgress: 3, username: "widget-test", api: api)
        let repeatedWrites = await api.writes
        precondition(repeatedWrites == 1, "A stale/repeated button must not log an extra episode")
        for (status, count) in [("watching", 25), ("completed", 3), ("planning", 3), ("dropped", 3)] {
            let blocked = FakeAPI(entry: ListEntry(media: media, status: status, progress: count))
            await action.advance(mediaID: 32, expectedProgress: count, username: "widget-test", api: blocked)
            let blockedWrites = await blocked.writes
            precondition(blockedWrites == 0)
        }
        let wrongAccount = FakeAPI(entry: entry, owner: "another-account")
        await action.advance(mediaID: 32, expectedProgress: 3, username: "widget-test", api: wrongAccount)
        let wrongWrites = await wrongAccount.writes
        precondition(wrongWrites == 0)
        let offlineState = MemoryState(), offline = FakeAPI(entry: entry, failRead: true)
        await WidgetProgressAction(state: offlineState).advance(mediaID: 32, expectedProgress: 3, username: "widget-test", api: offline)
        let offlineWrites = await offline.writes
        precondition(offlineWrites == 0 && !offlineState.notices.isEmpty)
        let uncertainState = MemoryState(), uncertain = FakeAPI(entry: entry, failAfterWrite: true)
        await WidgetProgressAction(state: uncertainState).advance(mediaID: 32, expectedProgress: 3, username: "widget-test", api: uncertain)
        precondition(uncertainState.notices.last?.contains("Episode sent") == true)
        print("PASS: confirmed progress, repeated taps, completed/planned/dropped titles, account mismatch, offline failure, and uncertain refresh")
    }
}
