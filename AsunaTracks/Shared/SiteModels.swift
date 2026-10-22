import Foundation

struct DiscoverRecommendationResponse: Decodable {
    let items: [Media]
    let personalized: Bool?
    let moods: [DiscoverMood]?
    var isPersonalized: Bool { personalized == true }
    var uniqueItems: [Media] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.identity).inserted }
    }
    var genreMixes: [DiscoverMood] {
        var seen = Set<String>()
        return (moods ?? []).filter { !$0.items.isEmpty && seen.insert($0.label).inserted }
    }
}

struct DiscoverMood: Decodable, Identifiable {
    let label: String
    let reason: String?
    let items: [Media]
    var id: String { label }
}

struct CollectionPage: Decodable { let items: [TrackCollection] }
struct CollectionResponse: Decodable { let collection: TrackCollection }
struct CollectionStats: Decodable {
    let itemCount: Int?
    let likeCount: Int?
    let followerCount: Int?
    let commentCount: Int?
}
struct CollectionEntry: Decodable, Identifiable {
    let id: Int
    let position: Int?
    let noteTitle: String?
    let note: String?
    let media: Media
}
struct CollectionComment: Decodable, Identifiable {
    let id: Int
    let body: String
    let user: User?
}
struct TrackCollection: Decodable, Identifiable {
    let id: Int
    let title: String
    let shortDescription: String?
    let description: String?
    let collectionType: String?
    let tags: [String]?
    let bannerUrl: String?
    let heroImageUrl: String?
    let ranked: Bool?
    let owner: User?
    let stats: CollectionStats?
    let previewItems: [Media]?
    let items: [CollectionEntry]?
    let comments: [CollectionComment]?
    let viewerLiked: Bool?
    let viewerFollowing: Bool?
}
struct ScheduleResponse: Decodable {
    let configured: Bool?
    let items: [ScheduleRelease]
    let stale: Bool?
    let warning: String?
}
struct ScheduleRelease: Decodable {
    let id: String
    let title: String
    let titleEnglish: String?
    let imageUrl: String?
    let episodeNumber: Double?
    let episodeTitle: String?
    let episodeDate: String?
    let airType: String?
    let airingStatus: String?
    let isOnBreak: Bool?
    let delayedText: String?
    let media: Media?
    var identity: String { "\(id):\(episodeDate ?? ""): \(airType ?? ""):\(episodeNumber ?? 0)" }
    var displayTitle: String { titleEnglish.flatMap { $0.isEmpty ? nil : $0 } ?? title }
    var date: Date? {
        guard let episodeDate else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: episodeDate) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: episodeDate)
    }
}
struct MutationAcknowledgement: Decodable {}

struct PublicUserPage: Decodable { let items: [User]; let hasNext: Bool? }
struct ProfileResponse: Decodable {
    let user: User
    let items: [ListEntry]?
    let collections: [TrackCollection]?
    let follow: ProfileFollow?
    let `private`: Bool?
}
struct ProfileFollow: Decodable {
    let isFollowing: Bool?
    let followers: Int?
    let following: Int?
    let followersList: [User]?
    let followingList: [User]?
}
struct ActivityPage: Decodable { let items: [CommunityPost]; let hasNext: Bool? }
struct CommunityPost: Decodable, Identifiable {
    let id: Int
    let body: String?
    let user: User?
    let createdAt: String?
    var likeCount: Int?
    var commentCount: Int?
    let attachment: PostAttachment?
    var userLiked: Bool? = nil
    var comments: [CommunityComment]? = nil
}
struct PostAttachment: Decodable { let url: String?; let previewUrl: String?; let title: String? }
struct CommunityPostResponse: Decodable { let item: CommunityPost }
struct SocialLikeResponse: Decodable { let userLiked: Bool; let likeCount: Int }
struct CommunityComment: Decodable, Identifiable {
    let id: Int
    let body: String?
    let user: User?
    let createdAt: String?
    let parentId: Int?
    let replyTo: CommunityReplyReference?
    let attachment: PostAttachment?
    let likeCount: Int?
    let userLiked: Bool?
}
struct CommunityReplyReference: Decodable { let id: Int?; let body: String?; let user: User? }


struct EpisodePage: Decodable { let items: [MediaEpisode]; let hasNext: Bool?; let total: Int? }
struct MediaEpisode: Decodable, Identifiable {
    let id: Int
    let episodeNumber: Double?
    let title: String?
    let aired: String?
    let imageUrl: String?
    let coverImageUrl: String?
    let filler: Bool?
    let recap: Bool?
    let watchedAt: String?
    var number: String { episodeNumber.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "?" }
}
struct PicturePage: Decodable { let items: [MediaPicture] }
struct MediaPicture: Decodable, Identifiable {
    let id: Int
    let imageUrl: String?
    let thumbnailUrl: String?
    let pictureType: String?
    let sourceLabel: String?
}
struct RelationPage: Decodable { let items: [MediaRelation] }
struct MediaRelation: Decodable {
    let relation: String
    let entries: [RelatedTitle]
}
struct RelatedTitle: Decodable, Identifiable {
    let id: Int?
    let name: String?
    let titleEnglish: String?
    let mediaType: String?
    let type: String?
    let imageUrl: String?
    let route: String?
    let url: String?
    var identity: String { route ?? "\(type ?? "related"):\(id ?? 0):\(name ?? "")" }
    var displayTitle: String { titleEnglish ?? name ?? "Related title" }
}
struct ReviewPage: Decodable { let items: [MediaReview] }
struct MediaReview: Decodable, Identifiable {
    let id: Int
    let body: String?
    let user: User?
    let createdAt: String?
    let votes: ReviewVotes?
}
struct ReviewVotes: Decodable { let score: Int?; let up: Int?; let down: Int? }

// Public catalog routes use `items`, while the internal genre route uses `genres`.
struct PublicGenrePage: Decodable { let items: [Genre] }
struct SeasonPage: Decodable { let items: [CatalogSeason] }
struct CatalogSeason: Decodable, Identifiable, Hashable {
    let id: Int
    let year: Int
    let season: String
    let animeCount: Int?
    var title: String { "\(season.capitalized) \(year)" }
    var icon: String {
        switch season {
        case "winter": "snowflake"
        case "spring": "leaf"
        case "summer": "sun.max"
        default: "leaf.fill"
        }
    }
}
struct AnnouncementPage: Decodable { let items: [SiteAnnouncement] }
struct SiteAnnouncement: Decodable, Identifiable {
    let id: Int
    let title: String
    let body: String
    let category: String?
    let pinned: Bool?
    let createdAt: String?
}
