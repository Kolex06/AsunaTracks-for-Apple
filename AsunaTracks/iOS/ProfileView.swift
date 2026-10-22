import SwiftUI
import WebKit

struct ProfileAvatar: View {
    let user: User?
    var size: CGFloat = 44
    @Environment(\.accountTheme) private var theme
    var body: some View {
        Group {
            if let path = user?.avatarUrl, !path.isEmpty { AsunaArtwork(path: path, accent: theme.accent) }
            else { Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(theme.accent) }
        }.frame(width: size, height: size).clipShape(Circle())
            .overlay(Circle().strokeBorder(theme.accent.opacity(0.4)))
            .accessibilityLabel("Profile picture")
    }
}

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Group {
            if let user = store.user { UserProfileView(username: user.username) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 16) { ProfileAvatar(user: nil, size: 72); Text("Your AsunaTracks profile").font(.title2.bold()) }
                        Text("Sign in to see your profile, collection, and account colors.").foregroundStyle(.secondary)
                        NavigationLink { AccountView() } label: { Label("Sign in", systemImage: "person.crop.circle") }.buttonStyle(.glassProminent)
                        NavigationLink { CommunityView() } label: { Label("Explore the community", systemImage: "person.2") }.buttonStyle(.glass)
                        WebsiteFeatureLinks()
                    }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
                }.asunaSurface().navigationTitle("Profile")
            }
        }
    }
}

struct SiteFeature: Identifiable, Hashable {
    let title: String
    let path: String
    let icon: String
    var id: String { path }
    static let all: [SiteFeature] = [
        .init(title: "Community", path: "/home", icon: "person.2"),
        .init(title: "Collections", path: "/collections", icon: "rectangle.stack"),
        .init(title: "Schedule", path: "/schedule", icon: "calendar"),
        .init(title: "Seasons", path: "/season", icon: "leaf"),
        .init(title: "Genres", path: "/genres", icon: "tag"),
        .init(title: "Messages", path: "/messages", icon: "bubble.left.and.bubble.right"),
        .init(title: "Wrapped", path: "/wrapped", icon: "gift"),
        .init(title: "Playback Progress", path: "/playback-progress", icon: "play.rectangle"),
        .init(title: "My Edits", path: "/suggestions", icon: "pencil"),
        .init(title: "Map", path: "/map", icon: "map"),
        .init(title: "AI", path: "/AI", icon: "sparkles"),
        .init(title: "Streaming", path: "https://streaming.asunatracks.space", icon: "play.tv"),
        .init(title: "AMVs", path: "/amvs", icon: "film"),
        .init(title: "Store", path: "/store", icon: "bag"),
        .init(title: "Announcements", path: "/announcements", icon: "megaphone"),
        .init(title: "Apps & Integrations", path: "/apps", icon: "app.connected.to.app.below.fill"),
        .init(title: "Website settings", path: "/settings", icon: "gearshape"),
        .init(title: "Info & help", path: "/info", icon: "info.circle")
    ]
}

struct WebsiteFeatureLinks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore AsunaTracks").font(.title2.bold())
            Text("People, profiles, activity, collections, and schedules are available here.").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(SiteFeature.all) { feature in
                    NavigationLink { SiteFeatureView(title: feature.title, path: feature.path) } label: {
                        Label(feature.title, systemImage: feature.icon).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }.buttonStyle(.glass)
                }
            }
        }
    }
}

@MainActor final class SitePageState: ObservableObject {
    @Published var loading = true
    @Published var error: String?
    weak var webView: WKWebView?
}

struct SiteFeatureView: View {
    let title: String
    let path: String
    var forceWebsite = false
    @StateObject private var page = SitePageState()
    @State private var showSiteMenus = false
    @Environment(AppStore.self) private var store
    @Environment(\.accountTheme) private var theme
    @Environment(\.openURL) private var openURL
    @ViewBuilder var body: some View {
        if !forceWebsite && path == "/collections" { CollectionsView() }
        else if !forceWebsite && path == "/schedule" { ScheduleView() }
        else if !forceWebsite && path == "/home" { CommunityView() }
        else { websiteBody }
    }
    private var websiteBody: some View {
        SiteWebView(path: path, accountID: store.user?.id, showSiteMenus: showSiteMenus, state: page, openExternal: { openURL($0) }).id("\(path):\(store.user?.id ?? 0)")
            .overlay {
                if page.loading { AsunaLoadingPage(title: "Loading \(title)…") }
                if let error = page.error { FailureView(message: error) { page.error = nil; page.webView?.reload() }.background(.regularMaterial) }
            }
            .navigationTitle(title)
            .task(id: page.loading) {
                if !page.loading { await store.refreshAccountTheme() }
            }
            .onDisappear { Task { await store.refreshAccountTheme() } }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { page.webView?.goBack() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous page")
                    Button { page.webView?.goForward() } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next page")
                    Menu {
                        Toggle("Show site menus", isOn: $showSiteMenus)
                        Button("Reload page") { page.webView?.reload() }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Page options")
                    Link(destination: URL(string: path, relativeTo: APIClient.origin)!.absoluteURL) { Image(systemName: "safari") }.accessibilityLabel("Open in browser")
                }
            }
    }
}

@MainActor private enum SiteSession {
    private static var identity: Int?
    private static var storage = WKWebsiteDataStore.nonPersistent()
    static func dataStore(accountID: Int?) -> WKWebsiteDataStore {
        if identity != accountID { storage = .nonPersistent(); identity = accountID }
        return storage
    }
}

@MainActor private struct SiteWebView {
    let path: String
    let accountID: Int?
    let showSiteMenus: Bool
    let state: SitePageState
    let openExternal: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(state: state, openExternal: openExternal) }
    @MainActor func makeView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Site sections share in-memory preferences within this native account only.
        configuration.websiteDataStore = SiteSession.dataStore(accountID: accountID)
        configuration.userContentController.addUserScript(WKUserScript(source: Self.focusedPageScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.underPageBackgroundColor = .clear
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        state.webView = view
        let url = URL(string: path, relativeTo: APIClient.origin)!.absoluteURL
        Task { @MainActor in
            for cookie in HTTPCookieStorage.shared.cookies(for: APIClient.origin) ?? [] {
                await configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            }
            view.load(URLRequest(url: url))
        }
        context.coordinator.showSiteMenus = showSiteMenus
        return view
    }
    private static let focusedPageScript = """
    (() => {
      const style = document.createElement('style');
      style.textContent = `
        html.asuna-native { --site-topbar-space: 0px !important; }
        html.asuna-native .topbar, html.asuna-native .sidebar,
        html.asuna-native .site-footer, html.asuna-native .site-page-menu,
        html.asuna-native .mobile-bottom-nav { display: none !important; }
        html.asuna-native .app-shell { display: block !important; padding: 0 !important; grid-template-columns: minmax(0,1fr) !important; }
        html.asuna-native .main { margin: 0 !important; padding: 0 !important; min-width: 0 !important; }
        html.asuna-native #view { padding: 20px !important; margin: 0 !important; width: 100% !important; max-width: none !important; }
        html.asuna-native body { font-family: -apple-system, BlinkMacSystemFont, sans-serif !important; }
        html.asuna-native .button, html.asuna-native .input, html.asuna-native .select { min-height: 44px; border-radius: 12px; }
      `;
      document.head.appendChild(style);
      document.documentElement.classList.add('asuna-native');
    })();
    """
    func updateView(_ view: WKWebView) {
        let script = "document.documentElement.classList.toggle('asuna-native', \(showSiteMenus ? "false" : "true"));"
        view.evaluateJavaScript(script, completionHandler: nil)
        (view.navigationDelegate as? Coordinator)?.showSiteMenus = showSiteMenus
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var showSiteMenus = false
        let state: SitePageState
        let openExternal: (URL) -> Void
        init(state: SitePageState, openExternal: @escaping (URL) -> Void) { self.state = state; self.openExternal = openExternal }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { state.loading = true; state.error = nil }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.loading = false
            webView.evaluateJavaScript("document.documentElement.classList.toggle('asuna-native', \(showSiteMenus ? "false" : "true"));", completionHandler: nil)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        private func fail(_ error: Error) { guard (error as NSError).code != NSURLErrorCancelled else { return }; state.loading = false; state.error = error.localizedDescription }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            let host = url.host?.lowercased() ?? ""
            if host == "asunatracks.space" || host.hasSuffix(".asunatracks.space") { decisionHandler(.allow) }
            else if navigationAction.targetFrame?.isMainFrame != false { decisionHandler(.cancel); openExternal(url) }
            else { decisionHandler(.allow) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { openExternal(url) }; return nil
        }
    }
}

#if os(macOS)
extension SiteWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeView(context: context) }
    func updateNSView(_ nsView: WKWebView, context: Context) { updateView(nsView) }
}
#else
extension SiteWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeView(context: context) }
    func updateUIView(_ uiView: WKWebView, context: Context) { updateView(uiView) }
}
#endif
