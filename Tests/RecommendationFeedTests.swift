import Foundation

private final class RecommendationStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var number = 0
    static var scenario = "personalized"
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.number += 1
        let number = Self.number, scenario = Self.scenario
        Self.requests.append(request)
        Self.lock.unlock()
        let delay = scenario == "race" && number % 2 == 1 ? 0.20 : 0.01
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            let body = scenario == "error" ? "{\"error\":\"Unavailable\"}" : "{\"items\":[],\"personalized\":\(scenario == "general" ? "false" : "true"),\"moods\":[{\"label\":\"Response \(number)\",\"reason\":\"Test recommendation\",\"items\":[]}]}"
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: scenario == "error" ? 503 : 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@main struct RecommendationFeedTests {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecommendationStub.self]
        let api = APIClient(configuration: config, restoreSession: false)
        let feed = RecommendationFeed()
        let accountA = RecommendationContext(accountID: 1, libraryRevision: "first", showNsfw: false)
        let accountB = RecommendationContext(accountID: 2, libraryRevision: "second", showNsfw: false)
        let guest = RecommendationContext(accountID: nil, libraryRevision: "", showNsfw: false)
        await feed.load(context: accountA, api: api)
        precondition(feed.response?.isPersonalized == true && !feed.loading)
        let request = RecommendationStub.requests.last!
        precondition(request.httpMethod == "GET" && request.url?.path == "/api/discover/section")
        precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "section", value: "for-you")])
        RecommendationStub.scenario = "general"
        await feed.load(context: accountA, api: api)
        precondition(feed.response?.isPersonalized == false, "A general catalog response must not claim personalization")
        let count = RecommendationStub.requests.count
        await feed.load(context: guest, api: api)
        precondition(feed.response == nil && RecommendationStub.requests.count == count, "Guests must not receive another account's recommendations")
        RecommendationStub.scenario = "race"
        let first = Task { await feed.load(context: accountA, api: api) }
        try await Task.sleep(for: .milliseconds(30))
        let second = Task { await feed.load(context: accountB, api: api) }
        await second.value; await first.value
        precondition(feed.context == accountB && feed.response?.moods?.first?.label == "Response 4", "Late responses must not overwrite a newer account")
        let revised = RecommendationContext(accountID: 2, libraryRevision: "updated-progress-and-rating", showNsfw: false)
        let oldList = Task { await feed.load(context: accountB, api: api) }
        try await Task.sleep(for: .milliseconds(30))
        let newList = Task { await feed.load(context: revised, api: api) }
        await newList.value; await oldList.value
        precondition(feed.context == revised && feed.response?.moods?.first?.label == "Response 6")
        let beforeLogout = Task { await feed.load(context: revised, api: api) }
        try await Task.sleep(for: .milliseconds(30))
        await feed.load(context: guest, api: api)
        await beforeLogout.value
        precondition(feed.context == guest && feed.response == nil, "A response arriving after logout must be discarded")
        RecommendationStub.scenario = "error"
        await feed.load(context: accountA, api: api)
        precondition(feed.response == nil && feed.error != nil && !feed.loading, "Failed account switches must clear the prior account's picks")
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let page = try Coding.decoder.decode(DiscoverRecommendationResponse.self, from: data)
        precondition(!page.isPersonalized && !page.items.isEmpty && !page.genreMixes.isEmpty)
        let labeled = try Coding.decoder.decode(DiscoverRecommendationResponse.self, from: Data("{\"items\":[{\"id\":1,\"media_type\":\"anime\",\"title\":\"Test title\",\"recommendation_label\":\"Start this series here\",\"recommendation_reason\":[\"Adventure\"],\"watch_order_adjusted\":true}],\"personalized\":true}".utf8))
        precondition(labeled.items.first?.recommendationReason == ["Adventure"] && labeled.items.first?.watchOrderAdjusted == true)
        let missingFlag = try Coding.decoder.decode(DiscoverRecommendationResponse.self, from: Data("{\"items\":[]}".utf8))
        precondition(!missingFlag.isPersonalized)
        print("PASS: live Discover response decoding, recommendation labels, honest personalization flags, session route, guest isolation, late account responses and errors; no live account mutations")
    }
}
