import Foundation
import WidgetKit
import AppIntents

struct AdvanceEpisodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark next episode watched"
    static var description = IntentDescription("Log one episode on your AsunaTracks list without opening the app.")
    static var supportedModes: IntentModes {
        #if os(macOS)
        [.background, .foreground(.dynamic)]
        #else
        [.background]
        #endif
    }
    #if os(macOS)
    @available(macOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }
    #endif
    static var isDiscoverable: Bool = false
    @Parameter(title: "Anime ID") var mediaID: Int
    @Parameter(title: "Displayed progress") var expectedProgress: Int
    @Parameter(title: "Account") var username: String

    init() {}
    init(item: ProgressItem, username: String) {
        self.mediaID = item.mediaID
        self.expectedProgress = item.progress
        self.username = username
    }
    func perform() async throws -> some IntentResult {
        await WidgetProgressAction.shared.advance(mediaID: mediaID, expectedProgress: expectedProgress, username: username)
        return .result()
    }
}

protocol WidgetProgressServing: Sendable {
    func widgetUser() async throws -> UserResponse
    func widgetList() async throws -> ListResponse
    func advance(_ entry: ListEntry) async throws
}
extension APIClient: WidgetProgressServing {
    func widgetUser() async throws -> UserResponse { try await request("api/me") }
    func widgetList() async throws -> ListResponse { try await request("api/list") }
}

protocol WidgetProgressState: Sendable {
    func read() -> ProgressSnapshot
    func notice(_ message: String, username: String)
    func publish(_ list: ListResponse, user: User)
    func reload()
}
struct SystemWidgetProgressState: WidgetProgressState {
    func read() -> ProgressSnapshot { ProgressCache.read() }
    func notice(_ message: String, username: String) { ProgressCache.setActionNotice(message, username: username) }
    func publish(_ list: ListResponse, user: User) { ProgressPublisher.publish(entries: list.items, user: user) }
    func reload() { WidgetCenter.shared.reloadAllTimelines() }
}

/// An explicit episode endpoint makes repeat taps on the same rendered button idempotent.
actor WidgetProgressAction {
    static let shared = WidgetProgressAction()
    private var updating = false
    private let state: any WidgetProgressState
    init(state: any WidgetProgressState = SystemWidgetProgressState()) { self.state = state }
    func advance(mediaID: Int, expectedProgress: Int, username: String,
                 api: any WidgetProgressServing = APIClient.shared) async {
        guard !updating, state.read().username == username else { return }
        updating = true
        defer { updating = false; state.reload() }
        do {
            guard let user = try await api.widgetUser().user, user.username == username else {
                state.notice("Open AsunaTracks to sign in again", username: username)
                return
            }
            let list = try await api.widgetList()
            guard state.read().username == username else { return }
            guard let entry = list.items.first(where: { $0.media.mediaType == "anime" && $0.media.id == mediaID }),
                  entry.canAdvance, (entry.progress ?? 0) == expectedProgress else {
                state.publish(list, user: user)
                state.notice("Progress refreshed · Tap +1 again if needed", username: username)
                return
            }
            // Never change ratings, notes, or other tracking fields to log an episode.
            try await api.advance(entry)
            do {
                let refreshed = try await api.widgetList()
                guard state.read().username == username else { return }
                state.publish(refreshed, user: user)
            } catch {
                state.notice("Episode sent · Open the app to refresh", username: username)
            }
        } catch {
            // The displayed count stays unchanged until the API confirms it.
            state.notice(error is URLError ? "Couldn’t connect · Tap +1 to retry" : "Couldn’t update · Open the app to check", username: username)
        }
    }
}
