import Foundation

struct DeviceConnection {
    // The executable inside our project's Python environment.
    let executableURL: URL

    func listDevices() async throws -> [ConnectedDevice] {
        let toolURL = executableURL

        // Run the command away from the UI so the window stays responsive.
        return try await Task.detached {
            let process = Process()
            let output = Pipe()

            process.executableURL = toolURL
            process.arguments = ["usbmux", "list"]

            // Capture JSON output; keep diagnostic errors in Xcode's console.
            process.standardOutput = output
            process.standardError = FileHandle.standardError

            var environment = ProcessInfo.processInfo.environment
            environment["NO_COLOR"] = "1"
            environment["TERM"] = "dumb"
            process.environment = environment

            try process.run()

            // Read output while the command runs, then wait for it to finish.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "DeviceConnection",
                    code: Int(process.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Device discovery failed. Check Xcode's console."
                    ]
                )
            }

            // Convert the JSON array into our Swift device objects.
            return try JSONDecoder().decode(
                [ConnectedDevice].self,
                from: data
            )
        }.value
    }
}
