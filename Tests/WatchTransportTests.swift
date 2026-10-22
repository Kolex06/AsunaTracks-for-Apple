import Foundation

/// Exercises the real URLSession client with intercepted HTTP responses, never a live account.
final class WatchHTTPStub: URLProtocol, @unchecked Sendable {
    struct Response {
        let method: String
        let path: String
        let data: Data
        var status = 200
    }
    static var responses: [Response] = []
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(!Self.responses.isEmpty)
        let next = Self.responses.removeFirst()
        precondition(request.url?.host == "asunatracks.space")
        precondition(request.url?.scheme == "https")
        precondition(request.url?.path == next.path && request.httpMethod == next.method)
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main enum WatchTransportTests {
    @MainActor static func main() async throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        let media = try Coding.decoder.decode(MediaPage.self, from: Data(contentsOf: fixtures.appendingPathComponent("search.json"))).items[0]
        let entry = ListEntry(media: media, status: "watching", progress: 3)
        var nextEntry = entry; nextEntry.progress = 4
        let old = try Coding.encoder.encode(ListResponse(items: [entry]))
        let updated = try Coding.encoder.encode(ListResponse(items: [nextEntry]))
        let account = Data(##"{"user":{"id":42,"username":"watch-http-test","ui_theme":"green","ui_accent_color":"#34d399","ui_color_intensity":80}}"##.utf8)
        let detail = try Data(contentsOf: fixtures.appendingPathComponent("detail.json"))
        WatchHTTPStub.responses = [
            .init(method: "GET", path: "/api/me", data: account),
            .init(method: "GET", path: "/api/account/settings", data: account),
            .init(method: "GET", path: "/api/list", data: old),
            .init(method: "GET", path: "/api/list", data: old),
            .init(method: "POST", path: "/api/media/anime/\(media.id)/episodes/4/watched", data: detail),
            .init(method: "GET", path: "/api/list", data: updated),
            .init(method: "GET", path: "/api/list", data: Data(#"{"error":"Unauthorized"}"#.utf8), status: 401)
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WatchHTTPStub.self]
        let api = APIClient(configuration: configuration, restoreSession: false)
        let suite = "AsunaTracks-WatchHTTPTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WatchStore(api: api, defaults: defaults)
        await store.refresh()
        precondition(store.user?.id == 42 && store.entries[0].progress == 3 && store.theme.name == "green")
        await store.advance(id: entry.id)
        precondition(store.entries[0].progress == 4)
        precondition(WatchHTTPStub.requests.filter { $0.httpMethod == "POST" }.count == 1)
        do { _ = try await api.loadList(); preconditionFailure("401 must require sign-in") }
        catch ServiceError.authenticationRequired { }
        precondition(WatchHTTPStub.responses.isEmpty)
        print("PASS: real Watch URLSession client uses direct HTTPS API routes, refreshes after writes, and recognizes expired sessions without a phone transport")
    }
}
