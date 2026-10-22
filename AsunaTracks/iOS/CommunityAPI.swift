import Foundation

extension APIClient {
    func setSocialLike(target: String, id: Int, liked: Bool) async throws -> SocialLikeResponse {
        guard ["activity", "activity_comment"].contains(target) else { throw ServiceError.message("Unsupported like target.") }
        return try await request("api/social/like/\(target)/\(id)", method: "POST",
                                 body: JSONSerialization.data(withJSONObject: ["liked": liked]))
    }
    func publishCommunity(body: String, attachment: String, postID: Int?, parentID: Int?) async throws {
        var payload: [String: Any] = ["body": body, "attachment_url": attachment]
        if let parentID { payload["parent_id"] = parentID }
        let path = postID.map { "api/activity/\($0)/comments" } ?? "api/activity"
        let _: MutationAcknowledgement = try await request(path, method: "POST", body: JSONSerialization.data(withJSONObject: payload))
    }
}
