import Foundation

@main struct NativeFeaturesTests {
    static func main() throws {
        let bio = """
        Hello <script>alert('unsafe')</script>
        img(https://example.com/line.gif)
        img520(https://example.com/discord.png)
        <a href="https://example.com/spotify?user=1&x=2"><img src="https://example.com/card.png" alt="Spotify"></a>
        webm(https://example.com/video.webm)
        <img src="javascript:alert(1)">
        """
        let html = ProfileBio.fragment(bio)
        precondition(html.contains("&lt;script&gt;") && !html.contains("<script>"))
        precondition(html.components(separatedBy: "<figure").count - 1 == 4)
        precondition(html.contains("max-width:520px"))
        precondition(html.contains("<video controls playsinline"))
        precondition(html.contains("<a href=\"https://example.com/spotify?user=1&amp;x=2\">"))
        precondition(!html.contains("src=\"javascript:"))
        precondition(ProfileBio.safeURL("file:///tmp/private") == nil)
        precondition(ProfileBio.safeURL("data:text/html,unsafe") == nil)
        let sound = ProfileBio.fragment("Before webm-sound(https://files.catbox.moe/up7ppk.webm?test=1&other=2) after")
        precondition(sound.contains("data-sound-webm") && sound.contains("Play with sound"))
        precondition(!sound.contains(" muted") && !sound.contains("webm-sound("))
        precondition(sound.contains("test=1&amp;other=2"))
        precondition(ProfileBio.fragment("WEBM-SOUND(https://example.com/audio.webm)").contains("data-sound-webm"))
        precondition(ProfileBio.fragment("webm(https://example.com/muted.webm)").contains(" muted"))
        precondition(!ProfileBio.fragment("webm-sound(https://example.com/file.html)").contains("<video"))
        let item = ProgressItem(id: "manga:29", mediaID: 29, mediaType: "manga", title: "A story", imageURL: nil, progress: 12, total: 100, unit: "chapters", status: "reading")
        precondition(item.url.absoluteString == "asunatracks://media/manga/29")
        let snapshot = ProgressSnapshot(username: "tester", updatedAt: Date(timeIntervalSince1970: 100), items: [item])
        let decoded = try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(snapshot))
        precondition(decoded.items == [item] && decoded.username == "tester")
        let encoder = JSONEncoder()
        let encoded = String(data: try encoder.encode(snapshot), encoding: .utf8)!
        precondition(!encoded.contains("password") && !encoded.contains("cookie") && !encoded.contains("token"))
        print("Rich profile rendering and widget snapshot tests passed")
    }
}
