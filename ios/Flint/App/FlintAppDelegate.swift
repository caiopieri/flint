import UIKit

final class FlintAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == ModelStore.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor in
            if let store = ModelStore.activeStore {
                store.setBackgroundCompletionHandler(completionHandler)
            } else {
                ModelStore.pendingBackgroundCompletion = completionHandler
            }
        }
    }
}
