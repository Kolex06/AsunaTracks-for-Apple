import Foundation
import Observation

struct RecommendationContext: Hashable {
    let accountID: Int?
    let libraryRevision: String
    let showNsfw: Bool?
    init(accountID: Int?, libraryRevision: String, showNsfw: Bool?) {
        self.accountID = accountID; self.libraryRevision = libraryRevision; self.showNsfw = showNsfw
    }
    init(user: User?, entries: [ListEntry]) {
        self.init(accountID: user?.id, libraryRevision: entries.map {
            "\($0.id):\($0.status):\($0.progress ?? 0):\($0.rating ?? -1):\($0.favorite ?? false):\($0.repeatCount ?? 0):\($0.updatedAt ?? "")"
        }.sorted().joined(separator: "|"), showNsfw: user?.showNsfw)
    }
}

/// Account-scoped, in-memory results. A late response can never replace a newer account/list.
@MainActor @Observable
final class RecommendationFeed {
    private(set) var response: DiscoverRecommendationResponse?
    private(set) var context: RecommendationContext?
    private(set) var loading = false
    private(set) var error: String?
    @ObservationIgnored private var requestID = UUID()

    func load(context next: RecommendationContext, api: APIClient = .shared) async {
        let request = UUID()
        requestID = request
        if context != next { response = nil }
        context = next
        error = nil
        guard next.accountID != nil else { response = nil; loading = false; return }
        loading = true
        defer { if request == requestID { loading = false } }
        do {
            let result: DiscoverRecommendationResponse = try await api.request("api/discover/section", query: ["section": "for-you"])
            try Task.checkCancellation()
            guard request == requestID, context == next else { return }
            response = result
        } catch {
            guard request == requestID, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
