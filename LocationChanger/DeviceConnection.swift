import Foundation

struct DeviceConnection {
    // The executable inside our project's Python environment.
    let executableURL: URL

    func listDevices() throws -> Process {
        let process = Process()

        // Run the executable directly, without a shell.
        process.executableURL = executableURL

        // Each argument is passed separately.
        process.arguments = ["usbmux", "list"]

        // Output goes to Xcode's console for this first version.
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        
        // Ask command-line libraries to output plain text without ANSI colors.
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        process.environment = environment
        
        // Starts the command and throws if it cannot launch.
        try process.run()

        return process
    }
}
