// EditorHost — the WKWebView that hosts the web runtime (T3.1).
//
// Serves the bundled web runtime (Resources/web) over a custom `flint://` scheme
// via WKURLSchemeHandler — not file:// (cleaner asset serving, tighter origin;
// locked in TASKS.md). The Swift side of the bridge (WebBridge) is registered
// here. T3.1 loads a placeholder runtime that proves the bridge round-trip;
// CodeMirror + doc load/save arrive in T3.2.
import SwiftUI
import WebKit

/// SwiftUI host for the editor's WKWebView. One instance is reused across note
/// switches (UIViewRepresentable reuses the underlying view).
struct EditorWebView: UIViewRepresentable {
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

        if let start = FlintScheme.url(for: "index.html") {
            webView.load(URLRequest(url: start))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        // Held here so it outlives makeUIView; the webview keeps a weak ref.
        let bridge = WebBridge()
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
