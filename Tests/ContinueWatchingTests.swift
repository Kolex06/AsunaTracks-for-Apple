import Foundation

private final class ContinueStub: URLProtocol, @unchecked Sendable {
    static var mode = "normal"
    static var progress = 3
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let path = request.url!.path
        let body: String
        if path == "/api/me" { body = "{\"user\":{\"id\":\(Self.mode == "other-account" ? 99 : 10),\"username\":\"test\"}}" }
        else if request.httpMethod == "POST" { Self.progress = 4; body = "{\"media\":{\"id\":7,\"media_type\":\"anime\",\"title\":\"Test anime\"}}" }
        else {
            let reading = Self.mode == "reading"
            body = "{\"items\":[{\"media\":{\"id\":7,\"media_type\":\"\(reading ? "manga" : "anime")\",\"title\":\"Test title\",\"episodes\":12,\"chapters\":20},\"status\":\"\(reading ? "reading" : Self.mode == "planned" ? "planning" : "watching")\",\"progress\":\(Self.progress),\"notes\":\"Fresh server notes\",\"rating\":8,\"favorite\":true}]}"
        }
        let failure = Self.mode == "refresh-fails" && Self.progress == 4 && path == "/api/list"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: failure ? 503 : 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ContinueWatchingTests {
    static func entry(_ id: Int, type: String = "anime", status: String = "watching", progress: Int = 3, total: Int = 12, date: String? = nil) throws -> ListEntry {
        var row: [String: Any] = ["media": ["id":id,"media_type":type,"title":"Test title", "episodes":total,"chapters":total], "status":status,"progress":progress]
        if let date { row["updated_at"] = date }
        return try Coding.decoder.decode(ListEntry.self, from: JSONSerialization.data(withJSONObject: row))
    }
    @MainActor static func main() async throws {
        let old = try entry(1, date: "2026-05-01T00:00:00Z"), recent = try entry(2, status:"rewatching", date:"2026-06-01T00:00:00Z")
        let unknown = try entry(3), book = try entry(4, type:"manga",status:"reading"), dropped = try entry(5,status:"dropped"), completed = try entry(6,status:"completed")
        precondition(ContinueQueue.entries([unknown,old,book,recent,dropped,completed,recent],reading:false).map(\.id) == [recent.id,old.id,unknown.id])
        precondition(ContinueQueue.entries([old,book],reading:true).map(\.id) == [book.id])
        let beyond = try entry(9,progress:20), noTotal = try entry(10,total:0), negative = try entry(11,progress:-2)
        precondition(ContinueQueue.fraction(beyond) == 1 && ContinueQueue.fraction(noTotal) == nil && ContinueQueue.progress(negative) == 0)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ContinueStub.self]
        let api = APIClient(configuration:config,restoreSession:false), service = ContinueProgressClient(api:api)
        let displayed = try entry(7)
        let result = try await service.advance(displayed,accountID:10)
        precondition(result.list.items.first?.progress == 4)
        precondition(ContinueStub.requests.filter { $0.httpMethod == "POST" }.map { $0.url!.path } == ["/api/media/anime/7/episodes/4/watched"])
        let posted = ContinueStub.requests.count
        _ = try await service.advance(displayed,accountID:10)
        precondition(ContinueStub.requests.count == posted + 2 && ContinueStub.requests.suffix(2).allSatisfy { $0.httpMethod == "GET" }, "Stale cards must refresh without logging another episode")
        ContinueStub.mode = "planned"; ContinueStub.progress = 3
        let beforePlanned = ContinueStub.requests.count
        _ = try await service.advance(displayed,accountID:10)
        precondition(ContinueStub.requests.count == beforePlanned + 2)
        ContinueStub.mode = "other-account"
        do { _ = try await service.advance(displayed,accountID:10); fatalError("Cross-account write accepted") } catch {}
        ContinueStub.mode = "normal"
        var checks = 0
        let beforeSwitch = ContinueStub.requests.filter { $0.httpMethod == "POST" }.count
        do { _ = try await service.advance(displayed,accountID:10, accountStillCurrent: { checks += 1; return checks == 1 }); fatalError("Write after logout accepted") } catch {}
        precondition(ContinueStub.requests.filter { $0.httpMethod == "POST" }.count == beforeSwitch)
        ContinueStub.mode = "reading"; ContinueStub.progress = 3
        let reading = try entry(7, type:"manga", status:"reading", total:20)
        let readingResult = try await service.advance(reading, accountID:10)
        precondition(readingResult.list.items.first?.progress == 4)
        let chapterWrite = ContinueStub.requests.last { $0.httpMethod == "POST" }!
        precondition(chapterWrite.url!.path == "/api/list")
        let payload: Data
        if let data = chapterWrite.httpBody { payload = data }
        else {
            let stream = chapterWrite.httpBodyStream!; stream.open(); defer { stream.close() }
            var data = Data(); var bytes = [UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable { let n = stream.read(&bytes,maxLength:bytes.count); if n <= 0 { break }; data.append(bytes,count:n) }
            payload = data
        }
        let fields = try JSONSerialization.jsonObject(with:payload) as! [String:Any]
        precondition(fields["progress"] as? Int == 4 && fields["notes"] as? String == "Fresh server notes" && fields["favorite"] as? Bool == true)
        ContinueStub.mode = "refresh-fails"; ContinueStub.progress = 3
        do { _ = try await service.advance(displayed,accountID:10); fatalError("Unconfirmed refresh treated as success") } catch { precondition(error.localizedDescription.contains("Update sent")) }
        print("PASS: active anime/reading queues, recent sorting, deduplication, unknown totals, episode endpoint, stale taps, planned entries, account changes, and uncertain refresh; no live writes")
    }
}
