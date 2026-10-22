import Foundation

struct ProgressItem: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let mediaID: Int
    let mediaType: String
    let title: String
    let imageURL: String?
    let progress: Int
    let total: Int
    let unit: String
    let status: String
    var accentRGB: [Double]? = nil
    var lastUpdated: Date? = nil
    var releaseDate: Date? = nil
    var episodeNumber: Double? = nil
    var airType: String? = nil
    var fraction: Double? { total > 0 ? min(1, max(0, Double(progress) / Double(total))) : nil }
    var progressLabel: String { total > 0 ? "\(max(0, progress)) / \(total)" : "\(max(0, progress)) logged" }
    var statusLabel: String {
        switch status {
        case "watching": "Watching"
        case "reading": "Reading"
        case "planning": "Planned"
        case "completed", "rewatched", "reread": "Completed"
        case "paused": "On hold"
        case "dropped": "Dropped"
        case "rewatching": "Rewatching"
        case "rereading": "Rereading"
        default: status.capitalized
        }
    }
    var url: URL { URL(string: "asunatracks://media/\(mediaType)/\(mediaID)")! }
}
struct ProgressSnapshot: Codable, Sendable {
    let username: String?
    let updatedAt: Date
    let items: [ProgressItem]
    var accentRGB: [Double]? = nil
    var listItems: [ProgressItem]? = nil
    var libraryIDs: [String]? = nil
    var actionNotice: String? = nil
    static var empty: Self { .init(username: nil, updatedAt: .now, items: []) }
}
/// Only display data is stored here. Session cookies stay in the shared Keychain.
enum ProgressCache {
    #if os(macOS)
    static let group = "B6NP2879G2.space.asunatracks.apple"
    #else
    static let group = "group.space.asunatracks.apple"
    #endif
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: group) ?? .standard
    }
    static func read() -> ProgressSnapshot {
        guard let data = defaults.data(forKey: "progressWidgetSnapshot"), let result = try? JSONDecoder().decode(ProgressSnapshot.self, from: data) else { return .empty }
        return result
    }
    static func write(_ snapshot: ProgressSnapshot) {
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: "progressWidgetSnapshot")
    }
    static func setActionNotice(_ message: String?, username: String) {
        var snapshot = read()
        guard snapshot.username == username else { return }
        snapshot.actionNotice = message
        write(snapshot)
    }
    static func imageFile(for item: ProgressItem) -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("cover-\(item.mediaType)-\(item.mediaID).data")
    }
    static func cacheCover(_ item: ProgressItem) async -> Data? {
        if let file = imageFile(for: item), let cached = try? Data(contentsOf: file) { return cached }
        guard let raw = item.imageURL, let url = URL(string: raw, relativeTo: URL(string: "https://asunatracks.space")), url.scheme == "https" else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 12))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else { return nil }
            if let file = imageFile(for: item) { try? data.write(to: file, options: .atomic) }
            return data
        } catch { return nil }
    }
    static func clear() {
        write(.empty)
        if let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group), let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("cover-") && file.pathExtension == "data" { try? FileManager.default.removeItem(at: file) }
        }
    }
}

/// Server timestamps may include fractional seconds; missing times stay unknown.
enum WidgetDate {
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
