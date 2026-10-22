import Foundation

private final class SocialStub: URLProtocol, @unchecked Sendable {
    static var received: [URLRequest] = []
    static var reject = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.received.append(request)
        let data = Data((Self.reject ? "{\"error\":\"Not allowed\"}" : request.url!.path.contains("/like/") ? "{\"user_liked\":true,\"like_count\":7}" : "{\"ok\":true}").utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.reject ? 403 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct CommunityAPITests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SocialStub.self]
        let api = APIClient(configuration: config, restoreSession: false)
        let result = try await api.setSocialLike(target: "activity", id: 19, liked: true)
        precondition(result.userLiked && result.likeCount == 7)
        _ = try await api.setSocialLike(target: "activity_comment", id: 6, liked: false)
        try await api.publishCommunity(body: "Reply text", attachment: "https://example.com/animated.gif", postID: 19, parentID: 6)
        try await api.publishCommunity(body: "Post text", attachment: "", postID: nil, parentID: nil)
        let requests = SocialStub.received
        precondition(requests.map { $0.url!.path } == ["/api/social/like/activity/19", "/api/social/like/activity_comment/6", "/api/activity/19/comments", "/api/activity"])
        precondition(requests.allSatisfy { $0.httpMethod == "POST" })
        func body(_ r: URLRequest) throws -> [String: Any] {
            let data: Data
            if let value = r.httpBody { data = value }
            else {
                let stream = r.httpBodyStream!; stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096); var value = Data()
                while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; value.append(bytes, count: n) }
                data = value
            }
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        let likeBody = try body(requests[0]), unlikeBody = try body(requests[1])
        precondition(likeBody["liked"] as? Bool == true)
        precondition(unlikeBody["liked"] as? Bool == false)
        let reply = try body(requests[2])
        precondition(reply["parent_id"] as? Int == 6 && reply["attachment_url"] as? String == "https://example.com/animated.gif")
        let postBody = try body(requests[3])
        precondition(postBody["parent_id"] == nil)
        do { _ = try await api.setSocialLike(target: "unsupported", id: 1, liked: true); fatalError("Unsupported target accepted") } catch {}
        precondition(SocialStub.received.count == 4)
        SocialStub.reject = true
        do { _ = try await api.setSocialLike(target: "activity", id: 19, liked: false); fatalError("Rejected write succeeded") } catch {}
        print("PASS: explicit like/unlike, server counts, comment replies, GIF attachments, post creation, and rejected writes using a local URLProtocol stub; no live mutations")
    }
}
