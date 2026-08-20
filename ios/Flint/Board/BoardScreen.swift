import SwiftUI
import WebKit

struct BoardScreen: View {
    let vault: VaultStore
    let relativePath: String

    var body: some View {
        BoardWebView(vault: vault, path: relativePath)
            .background(FlintColor.bg)
            .navigationTitle(relativePath.replacingOccurrences(of: ".canvas", with: ""))
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct BoardWebView: UIViewRepresentable {
    let vault: VaultStore
    let path: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(FlintSchemeHandler(), forURLScheme: FlintScheme.name)
        configuration.userContentController.addScriptMessageHandler(
            context.coordinator.bridge, contentWorld: .page, name: flintBridgeName
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.load(URLRequest(url: FlintScheme.url(for: "board.html")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.openedPath != path else { return }
        context.coordinator.openedPath = path
        if webView.url != nil { context.coordinator.open(path: path) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(vault: vault) }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let bridge: WebBridge
        private let vault: VaultStore
        weak var webView: WKWebView?
        var openedPath: String?

        init(vault: VaultStore) {
            self.vault = vault
            bridge = WebBridge(vault: vault)
            super.init()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let openedPath { open(path: openedPath) }
        }

        func open(path: String) {
            guard let webView else { return }
            Task {
                _ = try? await webView.callAsyncJavaScript(
                    "if (window.flintBoardOpen) { window.flintBoardOpen(path); }",
                    arguments: ["path": path], contentWorld: .page
                )
            }
        }
    }
}
