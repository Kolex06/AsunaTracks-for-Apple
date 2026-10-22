import SwiftUI

struct ContinueWatchingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accountTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reading = false
    @State private var notices: [String: String] = [:]
    @State private var blocked: Set<String> = []
    @State private var actionError: String?
    @State private var viewportWidth: CGFloat = 350
    @State private var focusedEntry: String?
    private var watching: [ListEntry] { ContinueQueue.entries(store.entries, reading: false) }
    private var books: [ListEntry] { ContinueQueue.entries(store.entries, reading: true) }
    private var showingReading: Bool { watching.isEmpty || reading }
    private var entries: [ListEntry] { showingReading ? books : watching }
    private var focusedIndex: Int { entries.firstIndex { $0.id == focusedEntry } ?? 0 }
    private var cardWidth: CGFloat {
        if typeSize.isAccessibilitySize { return max(250, min(420, viewportWidth)) }
        if viewportWidth < 600 { return max(250, min(320, viewportWidth * 0.88)) }
        if viewportWidth < 1000 { return min(340, (viewportWidth - 14) / 2) }
        return min(340, (viewportWidth - 28) / 3)
    }
    var body: some View {
        if store.user != nil, !watching.isEmpty || !books.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(showingReading ? "Continue reading" : "Continue watching").font(.title2.bold())
                    Spacer(minLength: 8)
                    NavigationLink { LibraryView(initialCategory: showingReading ? "books" : "anime", initialStatus: "active") } label: {
                        Text("View all").font(.subheadline.bold())
                    }.buttonStyle(.plain).foregroundStyle(theme.accent)
                }
                HStack(spacing: 8) {
                    if !watching.isEmpty, !books.isEmpty {
                        kindButton("Watching", reading: false, count: watching.count)
                        kindButton("Reading", reading: true, count: books.count)
                    } else {
                        Text("\(entries.count) in progress · Recently updated").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if entries.count > 1, !typeSize.isAccessibilitySize {
                        railButton("chevron.left", label: "Previous title", step: -1, disabled: focusedIndex == 0)
                        railButton("chevron.right", label: "Next title", step: 1, disabled: focusedIndex == entries.count - 1)
                    }
                }
                if let actionError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(actionError, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                        Button("Refresh list") { Task { await refresh() } }.buttonStyle(.glass).disabled(store.loadingList)
                    }
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(entries) { entry in
                            ContinueWatchingCard(entry: entry, busy: store.busyIDs.contains(entry.id), blocked: blocked.contains(entry.id), notice: notices[entry.id]) {
                                Task { await advance(entry) }
                            }.frame(width: cardWidth).id(entry.id)
                        }
                    }.scrollTargetLayout().padding(.vertical, 3)
                }
                .scrollPosition(id: $focusedEntry, anchor: .leading)
                .scrollTargetBehavior(.viewAligned)
                .appRailScrollIndicators()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
            }
            .onChange(of: showingReading) { _, _ in focusedEntry = entries.first?.id }
            .onChange(of: store.user?.id) { _, _ in notices = [:]; blocked = []; actionError = nil; reading = false; focusedEntry = nil }
        }
    }
    private func railButton(_ image: String, label: String, step: Int, disabled: Bool) -> some View {
        Button {
            let next = min(max(0, focusedIndex + step), entries.count - 1)
            withAnimation(reduceMotion ? nil : .snappy) { focusedEntry = entries[next].id }
        } label: { Image(systemName: image).font(.caption.bold()).frame(width: 30, height: 30) }
            .buttonStyle(.glass).disabled(disabled).accessibilityLabel(label)
    }
    private func kindButton(_ title: String, reading value: Bool, count: Int) -> some View {
        Button { reading = value } label: {
            Text("\(title) · \(count)").font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 8)
                .foregroundStyle(reading == value ? theme.accent : .secondary)
                .background(theme.accent.opacity(reading == value ? 0.16 : 0.04), in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(reading == value ? .isSelected : [])
    }
    private func advance(_ entry: ListEntry) async {
        guard let accountID = store.user?.id, !store.busyIDs.contains(entry.id), !blocked.contains(entry.id), entry.canAdvance else { return }
        store.busyIDs.insert(entry.id)
        defer { store.busyIDs.remove(entry.id) }
        do {
            let result = try await ContinueProgressClient().advance(entry, accountID: accountID, accountStillCurrent: { store.user?.id == accountID })
            guard store.user?.id == accountID else { return }
            // Publish only confirmed server data, including widgets and a pinned Live Activity.
            await store.applyList(result.list, accountID: accountID)
            notices[entry.id] = result.message
            actionError = nil
        } catch {
            guard store.user?.id == accountID else { return }
            blocked.insert(entry.id)
            actionError = error.localizedDescription
        }
    }
    private func refresh() async {
        let accountID = store.user?.id
        do {
            try await store.refreshList()
            guard store.user?.id == accountID else { return }
            blocked = []; actionError = nil; notices = [:]
        } catch { if store.user?.id == accountID { actionError = error.localizedDescription } }
    }
}

private struct ContinueWatchingCard: View {
    @Environment(\.accountTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: ListEntry
    let busy: Bool
    let blocked: Bool
    let notice: String?
    let advance: () -> Void
    private var progress: Int { ContinueQueue.progress(entry) }
    private var unit: String { entry.media.mediaType == "anime" ? "episode" : "chapter" }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink { MediaDetailView(initial: entry.media) } label: {
                Poster(media: entry.media)
                    .frame(width: typeSize.isAccessibilitySize ? 66 : 70, height: typeSize.isAccessibilitySize ? 98 : 104)
                    .clipShape(.rect(cornerRadius: 10))
            }.buttonStyle(.plain).accessibilityLabel("Open \(entry.media.displayTitle)")
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink { MediaDetailView(initial: entry.media) } label: {
                    Text(entry.media.displayTitle).font(.subheadline.bold())
                        .lineLimit(typeSize.isAccessibilitySize ? 5 : 2, reservesSpace: true)
                        .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Text("\(unit.capitalized) \(progress)\(entry.media.total > 0 ? " / \(entry.media.total)" : " logged")")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                if let fraction = ContinueQueue.fraction(entry) {
                    ProgressView(value: fraction).tint(StatusStyle.color(entry.status))
                        .frame(height: 4)
                        .accessibilityLabel("\(progress) of \(entry.media.total) \(entry.media.unit) logged")
                } else { Color.clear.frame(height: 4).accessibilityHidden(true) }
                Button(action: advance) {
                    Group {
                        if busy { AsunaLoadingView(title: "Saving…", accent: theme.accent, compact: true) }
                        else { Label(blocked ? "Refresh list" : entry.canAdvance ? "+1 \(unit)" : "Up to date", systemImage: entry.canAdvance ? "checkmark" : "checkmark.circle.fill") }
                    }.font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 30)
                }.buttonStyle(.glass).disabled(busy || blocked || !entry.canAdvance)
                    .accessibilityLabel(entry.canAdvance ? "Mark \(unit) \(progress + 1) \(entry.media.mediaType == "anime" ? "watched" : "read") for \(entry.media.displayTitle)" : "All \(entry.media.unit) logged for \(entry.media.displayTitle)")
                if let notice {
                    Text(notice).font(.caption2).foregroundStyle(theme.accent).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12)
            .background(scheme == .dark ? AsunaStyle.panel : .white, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(StatusStyle.color(entry.status).opacity(0.25)) }
    }
}
