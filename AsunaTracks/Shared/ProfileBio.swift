import Foundation

/// Accept the site's image/video shorthand and linked images without executing profile HTML.
enum ProfileBio {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    static func safeURL(_ text: String) -> URL? {
        let decoded = text.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: decoded), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
    static func fragment(_ text: String) -> String {
        let pattern = #"(?is)<a\b[^>]*>\s*<img\b[^>]*>\s*</a>|<img\b[^>]*>|(?:img\d*|webm(?:-sound)?|video)\(\s*https?://[^\s<>]+?\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return escape(text) }
        let source = text as NSString
        var result = "", end = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += paragraph(source.substring(with: NSRange(location: end, length: match.range.location - end)))
            let raw = source.substring(with: match.range)
            if raw.hasPrefix("<") {
                if let src = attribute("src", raw), let url = safeURL(src) {
                    let image = imageHTML(url, width: nil)
                    if let href = attribute("href", raw), let link = safeURL(href) { result += "<a href=\"\(escape(link.absoluteString))\">\(image)</a>" }
                    else { result += image }
                } else { result += paragraph(raw) }
            } else if let open = raw.firstIndex(of: "("), let url = safeURL(String(raw[raw.index(after: open)..<raw.index(before: raw.endIndex)])) {
                if raw.lowercased().hasPrefix("webm") || raw.lowercased().hasPrefix("video") {
                    let sound = raw.lowercased().hasPrefix("webm-sound(")
                    let webm = raw.lowercased().hasPrefix("webm")
                    if webm && url.pathExtension.lowercased() != "webm" { result += paragraph(raw) }
                    else {
                        let flags = sound ? " data-sound-webm" : webm ? " muted" : ""
                        let button = sound ? "<button type=\"button\" class=\"play-sound\">Play with sound</button>" : ""
                        result += "<figure><video controls playsinline loop\(flags) preload=\"\(sound ? "none" : "metadata")\" src=\"\(escape(url.absoluteString))\"></video>\(button)<figcaption><a href=\"\(escape(url.absoluteString))\">Open video</a></figcaption></figure>"
                    }
                } else {
                    let width = Int(raw[..<open].dropFirst(3))
                    result += imageHTML(url, width: width)
                }
            } else { result += paragraph(raw) }
            end = NSMaxRange(match.range)
        }
        result += paragraph(source.substring(from: end))
        return result
    }
    private static func paragraph(_ text: String) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return "<div class=\"copy\">\(escape(text))</div>"
    }
    private static func imageHTML(_ url: URL, width: Int?) -> String {
        "<figure style=\"max-width:\(min(1200, max(80, width ?? 1200)))px\"><img src=\"\(escape(url.absoluteString))\" alt=\"Profile image\" loading=\"eager\"><figcaption class=\"fallback\"><a href=\"\(escape(url.absoluteString))\">Open image</a></figcaption></figure>"
    }
    private static func attribute(_ name: String, _ text: String) -> String? {
        let pattern = "(?is)\\b" + name + #"\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
