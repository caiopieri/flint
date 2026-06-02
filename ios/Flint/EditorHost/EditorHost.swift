// EditorHost — the WKWebView that hosts the CodeMirror editor.
//
// Serves the bundled web runtime (web/dist, copied into Resources/web) over a
// custom `flint://` scheme via WKURLSchemeHandler. The Swift side of the bridge
// lives alongside it. Implemented in T3 (see docs/TASKS.md).
import Foundation

enum EditorHost {
    // WKWebView + flint:// scheme handler land in T3.
}
