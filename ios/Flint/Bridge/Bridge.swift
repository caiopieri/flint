// Bridge — the typed JS <-> Swift message channel.
//
// Uses WKScriptMessageHandlerWithReply for async request/response with a typed
// envelope { id, method, payload }. It is the SECURITY BOUNDARY: every Flint.*
// call from a plugin is checked against declared capabilities here.
// APIs are coarse and async — never chatty (see AGENTS.md). Implemented in T3.
import Foundation

enum Bridge {
    // Message envelope + handler land in T3.
}
