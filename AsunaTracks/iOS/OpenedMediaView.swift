import SwiftUI

struct OpenedMedia: Identifiable {
    let type: String
    let mediaID: Int
    var id: String { "\(type):\(mediaID)" }
    init?(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard url.scheme == "asunatracks", url.host == "media", parts.count == 2, ["anime", "manga"].contains(parts[0]), let id = Int(parts[1]), id > 0 else { return nil }
        type = parts[0]; mediaID = id
    }
}
struct OpenedMediaView: View {
    let route: OpenedMedia
    @State private var media: Media?
    @State private var error: String?
    @Environment(\.accountTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let media { MediaDetailView(initial: media) }
            else if let error { FailureView(message: error) { Task { await load() } } }
            else { AsunaLoadingPage(title: "Opening your story…") }
        }.asunaSurface().task { await load() }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
    private func load() async {
        error = nil
        do { let result: DetailResponse = try await APIClient.shared.request("public/api/\(route.type)/\(route.mediaID)"); media = result.media }
        catch { self.error = error.localizedDescription }
    }
}
