import SwiftUI

struct ScheduleView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accountTheme) private var theme
    @State private var week = Date()
    @State private var airType = "sub"
    @State private var listOnly = false
    @State private var items: [ScheduleRelease] = []
    @State private var loading = true
    @State private var error: String?
    @State private var warning: String?
    private var calendar: Calendar { var calendar = Calendar(identifier: .iso8601); calendar.timeZone = .current; return calendar }
    private var key: String { "\(calendar.component(.yearForWeekOfYear, from: week)):\(calendar.component(.weekOfYear, from: week)):\(airType)" }
    private var visible: [ScheduleRelease] { items.filter { release in !listOnly || release.media.map { store.entry(for: $0) != nil } == true }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) } }
    private var days: [Date] { Array(Set(visible.compactMap { $0.date.map { calendar.startOfDay(for: $0) } })).sorted() }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Release schedule").font(.largeTitle.bold())
                Text("Times shown in \(TimeZone.current.identifier.replacingOccurrences(of: "_", with: " ")).").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Button { moveWeek(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous week")
                    Spacer()
                    Text("Week \(calendar.component(.weekOfYear, from: week)), \(String(calendar.component(.yearForWeekOfYear, from: week)))").font(.headline)
                    Spacer()
                    Button { moveWeek(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next week")
                    Button("This week") { week = Date() }
                }.buttonStyle(.glass)
                Picker("Release type", selection: $airType) { Text("All").tag("all"); Text("Sub").tag("sub"); Text("Dub").tag("dub"); Text("Raw").tag("raw") }.pickerStyle(.segmented)
                if store.user != nil { Toggle("Only titles in my list", isOn: $listOnly).tint(theme.accent) }
                if loading { AsunaLoadingView(title: "Loading releases…", accent: theme.accent).frame(maxWidth: .infinity).padding(24) }
                if let error { FailureView(message: error) { Task { await load() } } }
                if let warning, !warning.isEmpty { Label(warning, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                if !loading && visible.isEmpty && error == nil { ContentUnavailableView("No releases this week", systemImage: "calendar", description: Text("Try another week, release type, or list filter.")) }
                ForEach(days, id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.wide).month().day())).font(.title2.bold())
                    ForEach(visible.filter { $0.date.map { calendar.isDate($0, inSameDayAs: day) } == true }, id: \.identity) { release in
                        if let media = release.media {
                            NavigationLink { MediaDetailView(initial: media) } label: { releaseRow(release) }.buttonStyle(.plain)
                        } else { releaseRow(release) }
                    }
                }
            }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.asunaSurface().navigationTitle("Schedule").task(id: key) { await load() }
    }
    private func moveWeek(_ offset: Int) { if let date = calendar.date(byAdding: .weekOfYear, value: offset, to: week) { week = date } }
    private func releaseRow(_ item: ScheduleRelease) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AsunaArtwork(path: item.imageUrl ?? item.media?.imageUrl, accent: theme.accent).frame(width: 62, height: 90).clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 7) {
                Text(item.displayTitle).font(.headline)
                Text([item.episodeNumber.map { "Episode \($0.formatted(.number.precision(.fractionLength(0...1))))" }, item.airType?.uppercased()].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(theme.accent)
                if let title = item.episodeTitle, !title.isEmpty { Text(title).font(.caption).foregroundStyle(.secondary) }
                if let delay = item.delayedText, !delay.isEmpty { Text(delay).font(.caption).foregroundStyle(.orange) }
                if item.isOnBreak == true { Text("On break").font(.caption).foregroundStyle(.orange) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let date = item.date { Text(date.formatted(date: .omitted, time: .shortened)).font(.subheadline.monospacedDigit()).foregroundStyle(theme.accent) }
        }.padding(16).background(theme.accent.opacity(0.06), in: .rect(cornerRadius: 18))
    }
    private func load() async {
        let requestKey = key
        loading = true; error = nil; warning = nil; items = []
        defer { if requestKey == key && !Task.isCancelled { loading = false } }
        do {
            let response: ScheduleResponse = try await APIClient.shared.request("public/api/schedule", query: ["type": airType, "year": "\(calendar.component(.yearForWeekOfYear, from: week))", "week": "\(calendar.component(.weekOfYear, from: week))", "tz": TimeZone.current.identifier])
            try Task.checkCancellation(); guard requestKey == key else { return }
            items = response.items; warning = response.warning ?? (response.stale == true ? "Showing a cached schedule. Release times may have changed." : nil)
            if response.configured == false { error = "The schedule service is not configured. Please try again later." }
        } catch is CancellationError {} catch { if requestKey == key && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
