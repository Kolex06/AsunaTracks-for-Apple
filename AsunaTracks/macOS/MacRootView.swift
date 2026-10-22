#if os(macOS)
import SwiftUI

private enum MacDestination: Hashable {
    case section(AppSection)
    case feature(SiteFeature)
}

struct MacRootView: View {
    @State private var selected: MacDestination? = .section(.discover)
    @State private var openedTitle: OpenedMedia?
    @Environment(AppStore.self) private var store
    @Environment(\.accountTheme) private var theme
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                Section {
                    ForEach(AppSection.allCases.filter { $0 != .account }) { section in
                        Label(section.rawValue, systemImage: section.icon).tag(MacDestination.section(section))
                    }
                }
                Section("Explore AsunaTracks") {
                    ForEach(SiteFeature.all) { feature in
                        Label(feature.title, systemImage: feature.icon).tag(MacDestination.feature(feature))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
            .safeAreaInset(edge: .top) { BrandMark().padding(20) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { selected = .section(.account) } label: {
                    HStack(spacing: 10) {
                        ProfileAvatar(user: store.user, size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.user?.displayName ?? store.user?.username ?? "Profile")
                                .font(.headline).lineLimit(1)
                                .foregroundStyle(selected == .section(.account) ? theme.accent : .primary)
                            Text(store.user.map { "@\($0.username)" } ?? "Sign in to AsunaTracks")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile")
                .accessibilityValue(store.user.map { "@\($0.username)" } ?? "Sign in")
                .accessibilityAddTraits(selected == .section(.account) ? .isSelected : [])
            }
        } detail: {
            NavigationStack {
                Group {
                    switch selected ?? .section(.discover) {
                    case .section(.discover): DiscoverView()
                    case .section(.library): LibraryView()
                    case .section(.season): BrowseView()
                    case .section(.top): BrowseView(isTop: true)
                    case .section(.account): ProfileView()
                    case .feature(let feature): SiteFeatureView(title: feature.title, path: feature.path)
                    }
                }.asunaSurface()
            }.id("\(String(describing: selected)):\(store.user?.id ?? 0):\(store.user?.showNsfw ?? false)")
        }
        .containerBackground(.ultraThinMaterial, for: .window)
        .overlay {
            if !store.accountLoaded {
                AsunaLoadingPage(title: "Your next story awaits…")
            }
        }
        .onOpenURL { url in
            if url.scheme == "asunatracks", url.host == "library" { selected = .section(.library) }
            else if let title = OpenedMedia(url: url) { openedTitle = title }
        }
        .sheet(item: $openedTitle) { item in NavigationStack { OpenedMediaView(route: item) }.frame(minWidth: 700, minHeight: 650) }
        .focusedSceneValue(\.asunaNavigation, { section in selected = .section(section) })
        .alert("AsunaTracks", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
}
#endif
