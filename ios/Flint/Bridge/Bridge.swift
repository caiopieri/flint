// Bridge — the typed JS → Swift message channel (T3.1).
//
// Uses WKScriptMessageHandlerWithReply: a JS `postMessage` returns a Promise that
// resolves with Swift's reply (or rejects with its error string), so each call is
// async request/response over a typed envelope `{ id, method, payload }`. This is
// the SECURITY BOUNDARY — when plugins arrive, every `Flint.*` call is checked
// against declared capabilities here. APIs are coarse and async, never chatty
// (see AGENTS.md).
//
// T3.1 proves the round-trip with a single `ping` echo. The real vault methods
// (`doc.load`, `doc.save`) wired to the SyncProvider land in T3.2.
import Foundation
import WebKit

/// Handler name the JS side posts to: `window.webkit.messageHandlers.flint`.
let flintBridgeName = "flint"

@MainActor
final class WebBridge: NSObject, WKScriptMessageHandlerWithReply {
    /// Returns `(result, nil)` to fulfil the JS Promise, or `(nil, errorString)`
    /// to reject it. (The SDK imports the reply-handler method as async on iOS 26.)
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String else {
            return (nil, "Malformed bridge envelope")
        }
        let payload = body["payload"]

        switch method {
        case "ping":
            // Echo the payload straight back: proves JS → Swift → JS end to end.
            return (["pong": true, "echo": payload as Any], nil)
        default:
            return (nil, "Unknown bridge method: \(method)")
        }
    }
}
