#if os(macOS)
import SwiftUI

struct MacRootView: View {
    @State private var selected: AppSection? = .discover
    @State private var openedTitle: OpenedMedia?
    @Environment(AppStore.self) private var store
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        if section == .account {
                            HStack(spacing: 10) {
                                ProfileAvatar(user: store.user, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Profile").font(.headline)
                                    Text(store.user.map { "@\($0.username)" } ?? "Sign in").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 5).tag(section)
                        } else { Label(section.rawValue, systemImage: section.icon).tag(section) }
                    }
                }
                Section("Explore AsunaTracks") {
                    ForEach(SiteFeature.all) { feature in
                        NavigationLink { SiteFeatureView(title: feature.title, path: feature.path) } label: { Label(feature.title, systemImage: feature.icon) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
            .safeAreaInset(edge: .top) { BrandMark().padding(20) }
        } detail: {
            NavigationStack {
                Group {
                    switch selected ?? .discover {
                    case .discover: DiscoverView()
                    case .library: LibraryView()
                    case .season: BrowseView()
                    case .top: BrowseView(isTop: true)
                    case .account: ProfileView()
                    }
                }.asunaSurface()
            }.id("\(selected?.rawValue ?? "Discover"):\(store.user?.id ?? 0):\(store.user?.showNsfw ?? false)")
        }
        .overlay {
            if !store.accountLoaded {
                AsunaLoadingPage(title: "Your next story awaits…")
            }
        }
        .onOpenURL { url in
            if url.scheme == "asunatracks", url.host == "library" { selected = .library }
            else if let title = OpenedMedia(url: url) { openedTitle = title }
        }
        .sheet(item: $openedTitle) { item in NavigationStack { OpenedMediaView(route: item) }.frame(minWidth: 700, minHeight: 650) }
        .focusedSceneValue(\.asunaNavigation, { section in selected = section })
        .alert("AsunaTracks", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
}
#endif
