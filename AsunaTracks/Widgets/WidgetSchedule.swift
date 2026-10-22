import Foundation

struct WidgetScheduledRelease: Codable, Sendable {
    let id: String
    let title: String
    let titleEnglish: String?
    let imageUrl: String?
    let episodeNumber: Double?
    let episodeDate: String?
    let airType: String?
    let isOnBreak: Bool?
    let media: WidgetScheduledMedia?
    var date: Date? { WidgetDate.parse(episodeDate) }
}
struct WidgetScheduledMedia: Codable, Sendable {
    let id: Int
    let mediaType: String
    let imageUrl: String?
}
struct WidgetScheduleResponse: Decodable {
    let configured: Bool?
    let items: [WidgetScheduledRelease]
    let stale: Bool?
}
struct WidgetScheduleCache: Codable {
    let fetchedAt: Date
    let items: [WidgetScheduledRelease]
    let stale: Bool
}
enum UpcomingWidgetSchedule {
    /// Public release data is cached separately from account membership. No session is shared.
    private static var cacheFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ProgressCache.group)?.appendingPathComponent("release-schedule.json")
    }
    static func select(_ releases: [WidgetScheduledRelease], libraryIDs: Set<String>, now: Date) -> [ProgressItem] {
        var seen: Set<String> = []
        return releases.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }.compactMap { release in
            guard let media = release.media, libraryIDs.contains("\(media.mediaType):\(media.id)"),
                  let date = release.date, date > now, release.isOnBreak != true else { return nil }
            let id = "\(media.mediaType):\(media.id):\(date.timeIntervalSince1970):\(release.episodeNumber ?? 0):\(release.airType ?? "")"
            guard seen.insert(id).inserted else { return nil }
            return ProgressItem(id: id, mediaID: media.id, mediaType: media.mediaType,
                title: release.titleEnglish.flatMap { $0.isEmpty ? nil : $0 } ?? release.title,
                imageURL: release.imageUrl ?? media.imageUrl, progress: 0, total: 0, unit: "episodes", status: "upcoming",
                releaseDate: date, episodeNumber: release.episodeNumber, airType: release.airType)
        }
    }
    static func cachedItems(libraryIDs: Set<String>, now: Date = .now) -> [ProgressItem]? {
        guard let file = cacheFile, let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(WidgetScheduleCache.self, from: data) else { return nil }
        return select(cached.items, libraryIDs: libraryIDs, now: now)
    }
    static func load(libraryIDs: Set<String>) async -> (items: [ProgressItem], notice: String?) {
        guard !libraryIDs.isEmpty else { return ([], nil) }
        let now = Date()
        let cached = cacheFile.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(WidgetScheduleCache.self, from: $0) }
        if let cached, now.timeIntervalSince(cached.fetchedAt) < 900 {
            return (select(cached.items, libraryIDs: libraryIDs, now: now), cached.stale ? "Cached schedule" : nil)
        }
        do {
            let calendar = Calendar(identifier: .iso8601)
            let dates = [now, calendar.date(byAdding: .weekOfYear, value: 1, to: now)!]
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.timeoutIntervalForRequest = 12
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            let result = try await withThrowingTaskGroup(of: WidgetScheduleResponse.self) { group in
                for date in dates {
                    group.addTask {
                        var url = URLComponents(string: "https://asunatracks.space/public/api/schedule")!
                        url.queryItems = [URLQueryItem(name: "type", value: "all"), URLQueryItem(name: "week", value: String(calendar.component(.weekOfYear, from: date))), URLQueryItem(name: "year", value: String(calendar.component(.yearForWeekOfYear, from: date))), URLQueryItem(name: "tz", value: TimeZone.current.identifier)]
                        let (data, response) = try await session.data(from: url.url!)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
                        let result = try decoder.decode(WidgetScheduleResponse.self, from: data)
                        guard result.configured != false else { throw URLError(.resourceUnavailable) }
                        return result
                    }
                }
                var all: [WidgetScheduledRelease] = []; var stale = false
                for try await response in group { all += response.items; stale = stale || response.stale == true }
                return WidgetScheduleCache(fetchedAt: now, items: all, stale: stale)
            }
            if let file = cacheFile, let data = try? JSONEncoder().encode(result) { try? data.write(to: file, options: .atomic) }
            return (select(result.items, libraryIDs: libraryIDs, now: now), result.stale ? "Cached schedule" : nil)
        } catch {
            if let cached { return (select(cached.items, libraryIDs: libraryIDs, now: now), "Cached schedule") }
            return ([], "Open AsunaTracks to retry the release schedule.")
        }
    }
}
