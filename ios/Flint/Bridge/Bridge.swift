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

        case "attachment.data":
            guard let path = payload?["path"] as? String else {
                return (nil, "attachment.data: missing path")
            }
            do {
                let result = try await vault.attachmentData(path)
                return ([
                    "data": result.data.base64EncodedString(),
                    "mimeType": result.mimeType
                ], nil)
            } catch {
                return (nil, "attachment.data failed: \(error.localizedDescription)")
            }

        case "ai.context":
            let query = payload?["query"] as? String ?? ""
            let currentNoteText = payload?["currentNoteText"] as? String
            let context = await vault.aiContext(query: query, currentNoteText: currentNoteText)
            return ([
                "query": context.query,
                "currentNote": context.currentNote,
                "sources": context.sources.map {
                    ["path": $0.path, "title": $0.title, "excerpt": $0.excerpt]
                }
            ], nil)

        case "doc.links":
            return (["targets": vault.linkTargets()], nil)

        case "note.open":
            guard let target = payload?["target"] as? String else {
                return (nil, "note.open: missing target")
            }
            return (["opened": await vault.openOrCreateNoteTarget(target)], nil)

        case "ink.thumbnail":
            guard let target = payload?["target"] as? String else {
                return (nil, "ink.thumbnail: missing target")
            }
            let data = await vault.inkThumbnailPNG(target)
            return (["png": data?.base64EncodedString() ?? "", "found": data != nil], nil)

        case "ink.open":
            guard let target = payload?["target"] as? String else {
                return (nil, "ink.open: missing target")
            }
            vault.requestInk(target)
            return (["ok": true], nil)

        case "board.load":
            guard let path = payload?["path"] as? String else { return (nil, "board.load: missing path") }
            do {
                let document = try await vault.boardLoad(path)
                return try boardReply(document)
            } catch { return (nil, "board.load failed: \(error.localizedDescription)") }

        case "board.save":
            guard let path = payload?["path"] as? String,
                  let raw = payload?["document"] as? String,
                  let data = raw.data(using: .utf8) else {
                return (nil, "board.save: missing path/document")
            }
            do {
                let document = try BoardDocument.decode(data)
                try await vault.boardSave(path, document)
                return (["ok": true], nil)
            } catch { return (nil, "board.save failed: \(error.localizedDescription)") }

        case "board.notes":
            return (["notes": vault.boardNotes()], nil)

        default:
            return (nil, "Unknown bridge method: \(method)")
        }
    }

    private func boardReply(_ document: BoardDocument) throws -> (Any?, String?) {
        let data = try document.encoded()
        guard let json = String(data: data, encoding: .utf8) else {
            return (nil, "board.load: encoding failed")
        }
        return (["document": json], nil)
    }
}
