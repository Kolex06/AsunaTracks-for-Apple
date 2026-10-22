import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum ProgressPublisher {
    static func publish(entries: [ListEntry], user: User?) {
        // Preserve server order when timestamps are absent; newest real updates come first.
        let sorted = entries.enumerated().sorted { left, right in
            let a = WidgetDate.parse(left.element.updatedAt), b = WidgetDate.parse(right.element.updatedAt)
            if a == b { return left.offset < right.offset }
            return (a ?? .distantPast) > (b ?? .distantPast)
        }.map(\.element)
        func item(_ entry: ListEntry) -> ProgressItem {
            ProgressItem(id: entry.id, mediaID: entry.media.id, mediaType: entry.media.mediaType,
                title: entry.media.displayTitle, imageURL: entry.media.imageUrl, progress: entry.progress ?? 0,
                total: entry.media.total, unit: entry.media.unit, status: entry.status, accentRGB: user?.accountTheme.accentRGB,
                lastUpdated: WidgetDate.parse(entry.updatedAt))
        }
        let items = sorted.filter(\.active).prefix(8).map(item)
        // Upcoming needs membership in the full library, rather than just the eight visible titles.
        ProgressCache.write(.init(username: user?.username, updatedAt: .now, items: Array(items),
            accentRGB: user?.accountTheme.accentRGB, listItems: sorted.prefix(12).map(item), libraryIDs: sorted.map(\.id)))
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    static func clear() {
        ProgressCache.clear()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
