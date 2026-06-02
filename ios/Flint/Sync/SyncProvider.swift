// Sync — the SyncProvider abstraction.
//
// One consistency model (files-as-truth), multiple transports behind a protocol:
//   - iCloudDriveProvider (default, T2): zero-server file sync + .conflict handling
//   - ServerProvider (future): opt-in replication hub (NOT in Phase 1)
//
// All disk access goes through a provider — no raw FileManager calls leak out.
// The protocol is defined in T2 (see docs/TASKS.md). Placeholder for now.
import Foundation

enum Sync {
    // SyncProvider protocol + iCloudDriveProvider land in T2.
}
