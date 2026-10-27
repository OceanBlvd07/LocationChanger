import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // One connection shared by the app and its main screen.
    // The connection restores its saved backend selection.
    let deviceConnection = DeviceConnection()

    // Prevent duplicate cleanup tasks from repeated quit requests.
    private var isHandlingQuit = false

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        // Quit immediately when no cleanup is needed.
        guard deviceConnection.needsCleanup else {
            return .terminateNow
        }

        guard !isHandlingQuit else {
            return .terminateLater
        }

        isHandlingQuit = true

        Task { @MainActor in
            do {
                // Delay quitting while location cleanup runs.
                try await deviceConnection.stopSimulation()

                isHandlingQuit = false
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                // Keep the app open if cleanup fails.
                isHandlingQuit = false
                sender.reply(toApplicationShouldTerminate: false)

                let alert = NSAlert()
                alert.messageText = "Location cleanup failed"
                alert.informativeText = """
                \(error.localizedDescription)

                The app will stay open. Connect your iPhone and retry Stop \
                before quitting. Location restoration is unconfirmed.
                """
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }

        // macOS waits for our reply above.
        return .terminateLater
    }
}
