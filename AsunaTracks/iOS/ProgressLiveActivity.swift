#if os(iOS)
import ActivityKit
import SwiftUI

@MainActor enum ProgressLiveActivity {
    static func isPinned(_ entry: ListEntry) -> Bool { Activity<ProgressActivityAttributes>.activities.contains { $0.attributes.item.id == entry.id } }
    static func pin(_ entry: ListEntry, accentRGB: [Double]? = nil) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw ServiceError.message("Enable Live Activities for AsunaTracks in Settings to pin your progress.") }
        await endAll()
        let item = ProgressItem(id: entry.id, mediaID: entry.media.id, mediaType: entry.media.mediaType, title: entry.media.displayTitle, imageURL: entry.media.imageUrl, progress: entry.progress ?? 0, total: entry.media.total, unit: entry.media.unit, status: entry.status, accentRGB: accentRGB)
        _ = await ProgressCache.cacheCover(item)
        let state = ProgressActivityAttributes.ContentState(progress: entry.progress ?? 0, total: entry.media.total, status: entry.status, updatedAt: .now)
        _ = try Activity.request(attributes: ProgressActivityAttributes(item: item), content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(3600)), pushType: nil)
    }
    static func update(entries: [ListEntry]) async {
        for activity in Activity<ProgressActivityAttributes>.activities {
            guard let entry = entries.first(where: { $0.id == activity.attributes.item.id }), entry.active else {
                await activity.end(nil, dismissalPolicy: .immediate); continue
            }
            let state = ProgressActivityAttributes.ContentState(progress: entry.progress ?? 0, total: entry.media.total, status: entry.status, updatedAt: .now)
            await activity.update(ActivityContent(state: state, staleDate: .now.addingTimeInterval(3600)))
        }
    }
    static func endAll() async { for activity in Activity<ProgressActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) } }
}
struct LiveProgressButton: View {
    let entry: ListEntry
    @State private var pinned = false
    @State private var busy = false
    @Environment(AppStore.self) private var store
    var body: some View {
        Button(pinned ? "Unpin Lock Screen progress" : "Pin progress to Lock Screen", systemImage: pinned ? "pin.slash" : "pin") {
            Task {
                busy = true
                defer { busy = false }
                do {
                    if ProgressLiveActivity.isPinned(entry) { await ProgressLiveActivity.endAll() }
                    else { try await ProgressLiveActivity.pin(entry, accentRGB: store.user?.accountTheme.accentRGB) }
                    pinned = ProgressLiveActivity.isPinned(entry)
                } catch { store.message = error.localizedDescription }
            }
        }.buttonStyle(.glass).disabled(busy).task { pinned = ProgressLiveActivity.isPinned(entry) }
    }
}

#if DEBUG
/// Explicit simulator preview path. Uses public artwork and never calls list mutation APIs.
struct ProgressPreviewView: View {
    @State private var entry: ListEntry?
    @State private var error: String?
    @State private var started = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Text("Progress preview").font(.largeTitle.bold())
                Text("Preview data only. Your AsunaTracks list is unchanged.").font(.caption).foregroundStyle(.secondary)
                if let entry {
                    Poster(media: entry.media).frame(width: 100, height: 145).clipShape(.rect(cornerRadius: 14))
                    Text(entry.media.displayTitle).font(.headline)
                    Text("\(entry.progress ?? 0) / \(entry.media.total)")
                    Button("Start preview Live Activity") {
                        Task { do { try await ProgressLiveActivity.pin(entry, accentRGB: [0.22, 0.74, 0.97]); started = true } catch { self.error = error.localizedDescription } }
                    }.buttonStyle(.glassProminent)
                    if started {
                        Button("Advance preview progress") {
                            Task {
                                var next = entry; next.progress = (next.progress ?? 0) + 1; self.entry = next
                                ProgressPublisher.publish(entries: [next], user: User(id: 0, username: "Preview", displayName: "Widget preview"))
                                await ProgressLiveActivity.update(entries: [next])
                            }
                        }.buttonStyle(.glass)
                        Button("End preview") { Task { await ProgressLiveActivity.endAll(); ProgressPublisher.clear(); started = false } }.buttonStyle(.glass)
                    }
                } else { AsunaLoadingView(title: "Loading preview…") }
                if let error { Text(error).foregroundStyle(.red) }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).asunaSurface()
        }.task {
            do {
                let response: DetailResponse = try await APIClient.shared.request("public/api/anime/32")
                let entry = ListEntry(media: response.media, status: "watching", progress: 3)
                self.entry = entry
                ProgressPublisher.publish(entries: [entry], user: User(id: 0, username: "Preview", displayName: "Widget preview"))
            } catch { self.error = error.localizedDescription }
        }
    }
}
#endif
#endif
