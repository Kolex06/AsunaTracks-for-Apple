import Foundation

struct Genre: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let kind: String?
}

struct CommunityScore: Codable, Hashable {
    let score10: Double?
    let count: Int?
    var rating: Double? = nil
    var displayRating: Double? { rating ?? score10 }
    enum CodingKeys: String, CodingKey { case score10, count, rating }
}

struct Media: Codable, Identifiable, Hashable {
    let id: Int
    let mediaType: String
    let title: String
    let titleEnglish: String?
    let synopsis: String?
    let imageUrl: String?
    let bannerImageUrl: String?
    let score: Double?
    let episodes: Int?
    let chapters: Int?
    let year: Int?
    let status: String?
    let type: String?
    let genres: [Genre]?
    let asunatracksScore: CommunityScore?
    let releasedEpisodes: Int?
    let listEntry: TrackingFields?
    var characters: [AsunaCharacter]? = nil
    var trackedCount: Int? = nil
    var favoriteCount: Int? = nil
    var searchCount: Int? = nil
    var titleJapanese: String? = nil
    var volumes: Int? = nil
    var ageRating: String? = nil
    var startDate: String? = nil
    var endDate: String? = nil
    var season: String? = nil
    var displayTitle: String { titleEnglish.flatMap { $0.isEmpty ? nil : $0 } ?? title }
    var total: Int { (mediaType == "manga" ? chapters : episodes) ?? 0 }
    var unit: String { mediaType == "manga" ? "chapters" : "episodes" }
    var totalLabel: String { "\(total) \(total == 1 ? String(unit.dropLast()) : unit)" }
    var identity: String { "\(mediaType):\(id)" }
}

struct TrackingFields: Codable, Hashable {
    var status: String?
    var progress: Int?
    var progressVolumes: Int?
    var rating: Double?
    var favorite: Bool?
    var notes: String?
    var repeatCount: Int?
    var startDate: String?
    var finishDate: String?
}

struct ListEntry: Codable, Identifiable, Hashable {
    let media: Media
    var status: String
    var progress: Int?
    var progressVolumes: Int?
    var rating: Double?
    var favorite: Bool?
    var notes: String?
    var repeatCount: Int?
    var startDate: String?
    var finishDate: String?
    var updatedAt: String? = nil
    var id: String { media.identity }
    var active: Bool { ["watching", "reading", "rewatching", "rereading"].contains(status) }
    var canAdvance: Bool { active && (media.total == 0 || (progress ?? 0) < media.total) }
}

struct User: Codable, Identifiable {
    let id: Int
    let username: String
    let displayName: String?
    var avatarUrl: String? = nil
    var bannerUrl: String? = nil
    var bio: String? = nil
    var role: String? = nil
    var isSponsor: Bool? = nil
    var showNsfw: Bool? = nil
    var profilePrivate: Bool? = nil
    var watchingNowPrivate: Bool? = nil
    var playbackListPrivate: Bool? = nil
    var malSyncInterval: String? = nil
    var activityProgressWindow: Int? = nil
    var uiTheme: String? = nil
    var uiAccentColor: String? = nil
    var uiColorIntensity: Double? = nil
    var accountTheme: AccountTheme { AccountTheme(name: uiTheme, hex: uiAccentColor, intensity: uiColorIntensity) }
}
struct MediaPage: Decodable { let items: [Media]; let pagination: Pagination? }
struct Pagination: Decodable { let hasNextPage: Bool? }
struct DetailResponse: Decodable { let media: Media }
struct ListResponse: Codable { let items: [ListEntry]; var theme: AccountTheme? = nil }
struct UserResponse: Decodable { let user: User? }
struct GenreResponse: Decodable { let genres: [Genre] }
struct APIMessage: Decodable { let error: String? }

enum LibraryStatus: String, CaseIterable, Identifiable {
    case watching, planning, completed, onHold = "paused", dropped, rewatching
    var id: String { rawValue }
    var label: String {
        switch self {
        case .watching: "In progress"
        case .planning: "Planned"
        case .completed: "Completed"
        case .onHold: "On hold"
        case .dropped: "Dropped"
        case .rewatching: "Revisiting"
        }
    }
    func value(for media: Media) -> String {
        if media.mediaType == "manga" {
            if self == .watching { return "reading" }
            if self == .rewatching { return "rereading" }
        }
        return rawValue
    }
    func matches(_ entry: ListEntry) -> Bool { value(for: entry.media) == entry.status }
}

enum Coding {
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }
    static var encoder: JSONEncoder { let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; return e }
}

/// Matches the website's preset/custom-color selection and intensity calculation.
struct AccountTheme: Codable, Equatable {
    var name: String? = nil
    var hex: String? = nil
    var intensity: Double? = nil
    static let presets = ["pink": "ff3f8d", "blue": "38bdf8", "green": "34d399", "gold": "f59e0b", "red": "ef4444", "mono": "cbd5e1"]
    static func normalized(_ value: String?) -> String? {
        var text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard [3, 6].contains(text.count), text.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        return text
    }
    var accentRGB: [Double] {
        let preset = Self.presets[name ?? "pink"] ?? Self.presets["pink"]!
        let custom = Self.normalized(hex)
        let selected = custom.map { Self.presets.values.contains($0) && $0 != preset ? preset : $0 } ?? preset
        let value = UInt32(selected, radix: 16)!
        let raw = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)]
        let amount = min(100, max(15, intensity == nil || intensity == 0 || !(intensity!.isFinite) ? 74 : intensity!)) / 100
        return zip([148.0, 163, 184], raw).map { ($0 + ($1 - $0) * amount) / 255 }
    }
    var secondaryRGB: [Double] {
        let rgb = accentRGB
        let r = rgb[0], g = rgb[1], b = rgb[2]
        let high = rgb.max()!, low = rgb.min()!, d = high - low
        let lightness = (high + low) / 2
        var hue = 0.0, saturation = 0.0
        if d != 0 {
            saturation = lightness > 0.5 ? d / (2 - high - low) : d / (high + low)
            if high == r { hue = (g - b) / d + (g < b ? 6 : 0) }
            else if high == g { hue = (b - r) / d + 2 }
            else { hue = (r - g) / d + 4 }
            hue /= 6
        }
        let h = (hue + 28 / 360).truncatingRemainder(dividingBy: 1)
        let s = min(1, saturation + 0.08), l = min(0.78, max(0.18, lightness + 0.04))
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, a = 2 * l - q
        func channel(_ input: Double) -> Double {
            var t = input
            if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1 / 6 { return a + (q - a) * 6 * t }
            if t < 0.5 { return q }
            if t < 2 / 3 { return a + (q - a) * (2 / 3 - t) * 6 }
            return a
        }
        return [channel(h + 1 / 3), channel(h), channel(h - 1 / 3)]
    }
}

struct AsunaCharacter: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let nameKanji: String?
    let imageUrl: String?
    let about: String?
    let aliases: [String]?
    let favoriteCount: Int?
    let appearanceCount: Int?
    let media: [Media]?
    let voiceActors: [CharacterVoice]?
    var imageFallbacks: [String]? = nil
}
struct CharacterVoice: Codable, Hashable {
    let person: VoicePerson?
    let language: String?
}
struct VoicePerson: Codable, Hashable {
    let name: String?
}
struct CharacterPage: Decodable { let items: [AsunaCharacter]; let pagination: Pagination?; var hasNext: Bool? = nil }
struct CharacterResponse: Decodable { let character: AsunaCharacter }

struct NovelCatalogPage: Decodable {
    let items: [Media]
    let hasNext: Bool
    let total: Int?
}
