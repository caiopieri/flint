import SwiftUI

@main
struct FlintApp: App {
    @UIApplicationDelegateAdaptor(FlintAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
