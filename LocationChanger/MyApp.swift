import SwiftUI

@main
struct MyApp: App {
    // Connect our delegate to the macOS application lifecycle.
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        WindowGroup {
            // Give the screen the connection owned by the app delegate.
            ContentView(deviceConnection: appDelegate.deviceConnection)
        }
    }
}
