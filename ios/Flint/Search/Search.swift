// Search — full-text search index.
//
// SQLite FTS5 (via GRDB) indexing path/title/body of every `.md`. The index is
// DISPOSABLE and rebuildable from the vault — never the source of truth.
// Implemented in T4 (see docs/TASKS.md).
import Foundation

enum Search {
    // FTS5 index + query land in T4.
}
