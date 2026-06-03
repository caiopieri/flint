// EditorHost — the WKWebView that hosts the web runtime (T3.1).
//
// Serves the bundled web runtime (Resources/web) over a custom `flint://` scheme
// via WKURLSchemeHandler — not file:// (cleaner asset serving, tighter origin;
// locked in TASKS.md). The Swift side of the bridge (WebBridge) is registered
// here. The web runtime hosts CodeMirror and pulls/pushes note text over the
// bridge (`doc.load` / `doc.save`). Native owns *which* note is open and pushes
// the path in via `flintOpen`; the editor owns the live buffer.
import SwiftUI
import WebKit

/// SwiftUI host for the editor's WKWebView. One instance is reused across note
/// switches (UIViewRepresentable reuses the underlying view); switching notes is
/// a `flintOpen(path)` push, not a reload.
struct EditorWebView: UIViewRepresentable {
    let vault: VaultStore
    /// Vault-relative path of the selected note (nil → nothing selected).
    let path: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(FlintSchemeHandler(), forURLScheme: FlintScheme.name)
        config.userContentController.addScriptMessageHandler(
            context.coordinator.bridge, contentWorld: .page, name: flintBridgeName)

        let webView = WKWebView(frame: .zero, configuration: config)
        // Let the page's own background show (avoids a white flash over the warm
        // app chrome before the runtime paints).
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let start = FlintScheme.url(for: "index.html") {
            webView.load(URLRequest(url: start))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Push the selected note to the editor when it changes. The editor also
        // pulls the initial note itself on boot (doc.current), so an early push
        // before the runtime is ready is a harmless no-op (guarded in JS).
        let coordinator = context.coordinator
        if !coordinator.didOpen || coordinator.openedPath != path {
            coordinator.didOpen = true
            coordinator.openedPath = path
            coordinator.open(path: path)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(vault: vault) }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let bridge: WebBridge
        weak var webView: WKWebView?
        var openedPath: String?
        var didOpen = false
        /// Held strongly so the custom keyboard bar outlives each install.
        private var accessory: FlintKeyboardAccessory?

        init(vault: VaultStore) {
            bridge = WebBridge(vault: vault)
            super.init()
        }

        // The inner content view exists once the page has loaded — swap in the
        // transparent keyboard bar then.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let bar = accessory ?? FlintKeyboardAccessory(webView: webView)
            accessory = bar
            webView.installFlintKeyboardAccessory(bar)
        }

        /// Tell the editor which note to show (or `null` to clear).
        func open(path: String?) {
            guard let webView else { return }
            Task {
                _ = try? await webView.callAsyncJavaScript(
                    "if (window.flintOpen) { window.flintOpen(path); }",
                    arguments: ["path": path ?? NSNull()],
                    contentWorld: .page
                )
            }
        }
    }
}

/// The `flint://` custom scheme. Pages load from `flint://app/<path>`.
enum FlintScheme {
    static let name = "flint"
    static func url(for path: String) -> URL? { URL(string: "flint://app/\(path)") }
}

/// Serves the bundled web runtime over `flint://`. Maps `flint://app/<path>` to
/// `<bundle>/web/<path>`. No mutable state → safe to use from WebKit's callback.
final class FlintSchemeHandler: NSObject, WKURLSchemeHandler {
    private let webRoot = Bundle.main.resourceURL?.appendingPathComponent("web", isDirectory: true)

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let webRoot else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        var relative = url.path
        if relative.hasPrefix("/") { relative.removeFirst() }
        if relative.isEmpty { relative = "index.html" }

        let fileURL = webRoot.appendingPathComponent(relative)
        guard let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: Self.mimeType(for: fileURL.pathExtension),
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json", "map": return "application/json"
        case "svg": return "image/svg+xml"
        default: return "application/octet-stream"
        }
    }
}
