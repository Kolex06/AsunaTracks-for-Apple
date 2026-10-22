import SwiftUI
import WebKit

struct RichProfileBio: View {
    let text: String
    var mediaMaxHeight: CGFloat? = nil
    @State private var height: CGFloat = 80
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    var body: some View {
        BioWebView(text: text, mediaMaxHeight: mediaMaxHeight, dark: scheme == .dark, height: $height, openExternal: { openURL($0) })
            .frame(height: height).frame(maxWidth: .infinity)
    }
}
@MainActor private struct BioWebView {
    let text: String
    let mediaMaxHeight: CGFloat?
    let dark: Bool
    @Binding var height: CGFloat
    let openExternal: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(height: $height, openExternal: openExternal) }
    func makeView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.add(context.coordinator, name: "bioHeight")
        #if os(macOS)
        let view = BioContentWebView(frame: .zero, configuration: config)
        #else
        let view = WKWebView(frame: .zero, configuration: config)
        #endif
        view.navigationDelegate = context.coordinator
        view.underPageBackgroundColor = .clear
        #if os(macOS)
        view.setValue(false, forKey: "drawsBackground")
        #else
        view.isOpaque = false; view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        #endif
        load(view, coordinator: context.coordinator)
        return view
    }
    func load(_ view: WKWebView, coordinator: Coordinator) {
        let key = "\(dark):\(mediaMaxHeight ?? 0):\(text)"
        guard coordinator.key != key else { return }
        coordinator.key = key
        let nonce = UUID().uuidString
        let mediaSizing = mediaMaxHeight.map { "img,video{max-height:\(Int($0))px;object-fit:contain}" } ?? ""
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http:; media-src https: http:; style-src 'unsafe-inline'; script-src 'nonce-\(nonce)';">
        <style>:root{color-scheme:\(dark ? "dark" : "light")}*{box-sizing:border-box}html,body{margin:0;background:transparent;color:\(dark ? "#e9eaf2" : "#202332");font:16px -apple-system;overflow:hidden} .copy{white-space:pre-wrap;line-height:1.6;margin:0 0 12px;overflow-wrap:anywhere}figure{margin:10px auto;max-width:100%;}img,video{display:block;max-width:100%;width:auto;height:auto;margin:auto;border-radius:10px}video{width:100%;max-height:520px;aspect-ratio:auto 16/9}.play-sound[hidden]{display:none}.play-sound{display:block;margin:12px auto;padding:10px 18px;border:1px solid #38bdf855;border-radius:24px;background:#38bdf822;color:inherit;font:600 14px -apple-system;cursor:pointer}a{color:#38bdf8}.fallback{display:none}figure.failed .fallback{display:block}figcaption{font-size:12px;margin-top:8px;text-align:center}\(mediaSizing)</style></head><body>
        \(ProfileBio.fragment(text))
        <script nonce="\(nonce)">const report=()=>window.webkit.messageHandlers.bioHeight.postMessage(document.body.scrollHeight);new ResizeObserver(report).observe(document.body);document.querySelectorAll('img').forEach(i=>{i.onload=report;i.onerror=()=>{i.parentElement.classList.add('failed');i.alt='Image unavailable';report();};});document.querySelectorAll('video').forEach(v=>{v.onloadedmetadata=report;v.onerror=report;const b=v.parentElement.querySelector('.play-sound');if(b){b.onclick=()=>{v.muted=false;v.volume=1;v.play().catch(()=>{b.hidden=false;});};v.onplaying=()=>{b.hidden=true;report();};v.onpause=()=>{b.hidden=false;report();};}});report();</script>
        </body></html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://asunatracks.space"))
    }
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var key: String?
        var height: Binding<CGFloat>
        let openExternal: (URL) -> Void
        init(height: Binding<CGFloat>, openExternal: @escaping (URL) -> Void) { self.height = height; self.openExternal = openExternal }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "bioHeight", let value = message.body as? Double, value.isFinite else { return }
            let next = max(40, min(20000, value))
            if abs(height.wrappedValue - next) > 1 { height.wrappedValue = next }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                if let url = action.request.url, ProfileBio.safeURL(url.absoluteString) != nil { openExternal(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(action.request.url?.scheme == "about" || action.navigationType == .other ? .allow : .cancel) }
        }
    }
}
#if os(macOS)
// Embedded media has no independent scroll position; the native page owns scrolling.
@MainActor private final class BioContentWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
}
extension BioWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeView(context: context) }
    func updateNSView(_ nsView: WKWebView, context: Context) { load(nsView, coordinator: context.coordinator) }
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) { nsView.evaluateJavaScript("document.querySelectorAll('video').forEach(v=>v.pause())"); nsView.configuration.userContentController.removeScriptMessageHandler(forName: "bioHeight") }
}
#else
extension BioWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeView(context: context) }
    func updateUIView(_ uiView: WKWebView, context: Context) { load(uiView, coordinator: context.coordinator) }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) { uiView.evaluateJavaScript("document.querySelectorAll('video').forEach(v=>v.pause())"); uiView.configuration.userContentController.removeScriptMessageHandler(forName: "bioHeight") }
}
#endif
