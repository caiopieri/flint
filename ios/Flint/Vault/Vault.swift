// Vault — files-as-truth I/O.
//
// Responsibility: enumerate and read/write `.md` files in the user-chosen vault
// folder via NSFileCoordinator/NSFilePresenter, accessed through a security-scoped
// bookmark (see ADR-011) and routed behind the SyncProvider abstraction.
//
// The files ARE the source of truth — never a database. Implemented in T1/T2.
import Foundation

enum Vault {
    // Implementation lands in T1 (see docs/TASKS.md).
}
