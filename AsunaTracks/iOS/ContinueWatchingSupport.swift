import Foundation

/// Keep continuation separate from discovery: only active list entries, newest server updates first.
enum ContinueQueue {
    static func entries(_ entries: [ListEntry], reading: Bool) -> [ListEntry] {
        var seen = Set<String>()
        var rows: [(offset: Int, entry: ListEntry, date: Date)] = []
        for (offset, entry) in entries.enumerated() {
            let matchesKind = reading ? entry.media.mediaType == "manga" : entry.media.mediaType == "anime"
            guard entry.active, matchesKind, seen.insert(entry.id).inserted else { continue }
            rows.append((offset, entry, WidgetDate.parse(entry.updatedAt) ?? .distantPast))
        }
        rows.sort { a, b in
            if a.date == b.date { return a.offset < b.offset }
            return a.date > b.date
        }
        return rows.map { $0.entry }
    }

    static func progress(_ entry: ListEntry) -> Int { max(0, entry.progress ?? 0) }
    static func fraction(_ entry: ListEntry) -> Double? {
        entry.media.total > 0 ? min(1, Double(progress(entry)) / Double(entry.media.total)) : nil
    }
}

struct ContinueProgressResult {
    let list: ListResponse
    let message: String
}

/// Use fresh account/list data before a quick action; never queue or retry a write automatically.
struct ContinueProgressClient {
    let api: APIClient
    init(api: APIClient = .shared) { self.api = api }
    func advance(_ displayed: ListEntry, accountID: Int, accountStillCurrent: @MainActor () -> Bool = { true }) async throws -> ContinueProgressResult {
        guard await accountStillCurrent() else { throw ServiceError.authenticationRequired }
        let account: UserResponse = try await api.request("api/me")
        guard account.user?.id == accountID else { throw ServiceError.authenticationRequired }
        let list: ListResponse = try await api.request("api/list")
        guard await accountStillCurrent() else { throw ServiceError.authenticationRequired }
        guard let current = list.items.first(where: { $0.id == displayed.id }), current.canAdvance,
              current.status == displayed.status, current.progress == displayed.progress else {
            return ContinueProgressResult(list: list, message: "Progress refreshed. Check the next \(displayed.media.mediaType == "anime" ? "episode" : "chapter") before updating again.")
        }
        // Explicit episode/absolute chapter progress makes a repeated tap on the same displayed count safe.
        try await api.advance(current)
        do {
            let updated: ListResponse = try await api.request("api/list")
            return ContinueProgressResult(list: updated, message: "\(current.media.mediaType == "anime" ? "Episode" : "Chapter") \(ContinueQueue.progress(current) + 1) logged")
        } catch {
            throw ServiceError.message("Update sent, but progress couldn’t refresh. Refresh your list before trying again.")
        }
    }
}
