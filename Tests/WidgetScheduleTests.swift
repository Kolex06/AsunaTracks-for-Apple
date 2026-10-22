import Foundation

@main struct WidgetScheduleTests {
    static func main() throws {
        if CommandLine.arguments.count > 1 {
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            let live = try decoder.decode(WidgetScheduleResponse.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            precondition(live.configured != false)
            print("PASS: live schedule decoded \(live.items.count) releases")
        }
        let now = WidgetDate.parse("2026-10-21T12:00:00Z")!
        precondition(WidgetDate.parse("2026-10-21T12:00:00.123Z") != nil)
        precondition(WidgetDate.parse("unknown") == nil)
        let sample = """
        {"configured":true,"items":[
          {"id":"first","title":"Future","title_english":"My next release","episode_date":"2026-10-21T14:00:00Z","episode_number":4,"air_type":"sub","media":{"id":32,"media_type":"anime","image_url":"https://example.com/cover.png"}},
          {"id":"duplicate","title":"Future","episode_date":"2026-10-21T14:00:00Z","episode_number":4,"air_type":"sub","media":{"id":32,"media_type":"anime"}},
          {"id":"past","title":"Already aired","episode_date":"2026-10-21T10:00:00Z","media":{"id":32,"media_type":"anime"}},
          {"id":"other","title":"Not in my list","episode_date":"2026-10-21T15:00:00Z","media":{"id":71,"media_type":"anime"}},
          {"id":"break","title":"On break","episode_date":"2026-10-21T16:00:00Z","is_on_break":true,"media":{"id":32,"media_type":"anime"}}
        ]}
        """
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(WidgetScheduleResponse.self, from: Data(sample.utf8))
        let upcoming = UpcomingWidgetSchedule.select(response.items, libraryIDs: ["anime:32"], now: now)
        precondition(upcoming.count == 1)
        precondition(upcoming[0].title == "My next release" && upcoming[0].episodeNumber == 4)
        precondition(upcoming[0].imageURL == "https://example.com/cover.png")
        precondition(upcoming[0].url.absoluteString == "asunatracks://media/anime/32")
        precondition(UpcomingWidgetSchedule.select(response.items, libraryIDs: [], now: now).isEmpty)
        precondition(UpcomingWidgetSchedule.select(response.items, libraryIDs: ["anime:32"], now: now.addingTimeInterval(3 * 3600)).isEmpty)
        var item = upcoming[0]
        precondition(item.fraction == nil, "Unknown totals must not display a completed ring")
        item = ProgressItem(id: "test", mediaID: 32, mediaType: "anime", title: "Test", imageURL: nil, progress: 99, total: 12, unit: "episodes", status: "watching")
        precondition(item.fraction == 1 && item.statusLabel == "Watching")
        let legacy = Data(#"{"username":"legacy","updatedAt":100,"items":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(ProgressSnapshot.self, from: legacy)
        precondition(snapshot.listItems == nil && snapshot.libraryIDs == nil)
        print("PASS: personal releases, dates, duplicates, aired episodes, breaks, deep links, unknown totals, and legacy snapshots")
    }
}
