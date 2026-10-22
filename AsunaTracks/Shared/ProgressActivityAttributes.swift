#if os(iOS)
import ActivityKit
import Foundation

struct ProgressActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Int
        var total: Int
        var status: String
        var updatedAt: Date
    }
    let item: ProgressItem
}
#endif
