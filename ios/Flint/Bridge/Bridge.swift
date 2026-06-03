// Bridge — the typed JS → Swift message channel (T3.1).
//
// Uses WKScriptMessageHandlerWithReply: a JS `postMessage` returns a Promise that
// resolves with Swift's reply (or rejects with its error string), so each call is
// async request/response over a typed envelope `{ id, method, payload }`. This is
// the SECURITY BOUNDARY — when plugins arrive, every `Flint.*` call is checked
// against declared capabilities here. APIs are coarse and async, never chatty
// (see AGENTS.md).
//
// T3.2 wires the editor's vault methods (`doc.current` / `doc.load` / `doc.save`)
// to the VaultStore → SyncProvider. Paths cross the bridge vault-relative.
import Foundation
import WebKit

/// Handler name the JS side posts to: `window.webkit.messageHandlers.flint`.
let flintBridgeName = "flint"

@MainActor
final class WebBridge: NSObject, WKScriptMessageHandlerWithReply {
    private let vault: VaultStore

    init(vault: VaultStore) {
        self.vault = vault
        super.init()
    }

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
        let payload = body["payload"] as? [String: Any]

        switch method {
        case "ping":
            // Echo straight back: proves JS → Swift → JS end to end.
            return (["pong": true, "echo": body["payload"] as Any], nil)

        case "doc.current":
            // Which note should the editor show on boot? (nil → empty.)
            return (["path": vault.selectedRelativePath as Any], nil)

        case "doc.load":
            guard let path = payload?["path"] as? String else {
                return (nil, "doc.load: missing path")
            }
            do {
                let text = try await vault.editorLoad(path)
                return (["text": text], nil)
            } catch {
                return (nil, "doc.load failed: \(error.localizedDescription)")
            }

        case "doc.save":
            guard let path = payload?["path"] as? String,
                  let text = payload?["text"] as? String else {
                return (nil, "doc.save: missing path/text")
            }
            do {
                try await vault.editorSave(path, text)
                return (["ok": true], nil)
            } catch {
                return (nil, "doc.save failed: \(error.localizedDescription)")
            }

        default:
            return (nil, "Unknown bridge method: \(method)")
        }
    }
}
