// VaultPresenter — watches the vault folder for external changes (T1.3).
//
// An edit synced from another device, or made in Obsidian/Finder while Flint is
// open, fires `onChange`. The callback arrives on a private operation queue; the
// store hops it back to the main actor to refresh the tree.
import Foundation

final class VaultPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.presentedItemURL = url
        self.onChange = onChange
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        self.presentedItemOperationQueue = queue
        super.init()
    }

    func presentedItemDidChange() { onChange() }
    func presentedSubitemDidChange(at url: URL) { onChange() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { onChange() }
    func accommodatePresentedSubitemDeletion(at url: URL) async throws { onChange() }
}
