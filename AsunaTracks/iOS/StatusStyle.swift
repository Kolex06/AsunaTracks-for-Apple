import SwiftUI

enum StatusStyle {
    static func color(_ status: String) -> Color {
        switch status {
        case "watching", "reading", "rewatching", "rereading": Color(red: 56/255, green: 189/255, blue: 248/255)
        case "completed", "rewatched", "reread": Color(red: 34/255, green: 197/255, blue: 94/255)
        case "planning", "planned": Color(red: 234/255, green: 179/255, blue: 8/255)
        case "dropped": Color(red: 239/255, green: 68/255, blue: 68/255)
        default: Color(red: 148/255, green: 163/255, blue: 184/255)
        }
    }
    static func label(_ status: String) -> String {
        switch status { case "planning": "Planned"; case "paused": "On hold"; default: status.replacingOccurrences(of: "_", with: " ").capitalized }
    }
}
struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(StatusStyle.label(status)).font(.caption2.bold())
            .foregroundStyle(StatusStyle.color(status)).padding(.horizontal, 9).padding(.vertical, 5)
            .background(StatusStyle.color(status).opacity(0.12), in: Capsule())
    }
}

struct StatusProgress: View {
    let value: Double
    let total: Double
    let status: String
    private var fraction: Double { max(0, min(1, total > 0 ? value / total : 0)) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(StatusStyle.color(status).opacity(0.14))
                Capsule().fill(StatusStyle.color(status)).frame(width: geometry.size.width * fraction)
            }
        }.frame(height: 5).accessibilityElement(children: .ignore)
            .accessibilityLabel(StatusStyle.label(status))
            .accessibilityValue("\(Int(value)) of \(Int(total))")
    }
}
