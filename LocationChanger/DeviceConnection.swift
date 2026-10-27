import Foundation

final class DeviceConnection {
    // The executable inside our project's Python environment.
    let executableURL: URL
    
    // Keep the simulation process alive so Stop can end it later.
    private var simulationProcess: Process?

    // Keep its input open while the simulation is running.
    private var simulationInput: Pipe?

    // Classes need an explicit initializer for this stored property.
    init(executableURL: URL) {
        self.executableURL = executableURL
    }

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
    func startSimulation(latitude: Double, longitude: Double) throws {
        // Reject invalid coordinates before contacting the phone.
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            throw NSError(
                domain: "DeviceConnection",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid coordinates."
                ]
            )
        }

        // End the existing session before starting another.
        guard simulationProcess == nil else {
            throw NSError(
                domain: "DeviceConnection",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Stop the current session first."
                ]
            )
        }

        let process = Process()
        let input = Pipe()

        process.executableURL = executableURL
        process.arguments = [
            "developer", "dvt", "simulate-location", "set",
            "--", String(latitude), String(longitude)
        ]

        // The tool waits for input while maintaining the simulation.
        process.standardInput = input
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        
        // Report when the command exits, including failed connection attempts.
        process.terminationHandler = { finishedProcess in
            print(
                "SIMULATION EXIT:",
                finishedProcess.terminationStatus,
                "REASON:",
                finishedProcess.terminationReason
            )
        }
        try process.run()

        // Retain both objects for the lifetime of the session.
        simulationProcess = process
        simulationInput = input
    }
    func stopSimulation() async throws {
        let activeProcess = simulationProcess
        let toolURL = executableURL

        try await Task.detached {
            // First request an interrupt, similar to Control-C in Terminal.
            if let activeProcess, activeProcess.isRunning {
                activeProcess.interrupt()

                // If it doesn't exit promptly, request termination.
                if !Self.waitForExit(activeProcess, timeout: 3) {
                    activeProcess.terminate()
                    _ = Self.waitForExit(activeProcess, timeout: 3)
                }
            }

            // Attempt to clear the location even if the original process
            // hasn't exited. Never leave this behind an unlimited wait.
            let clearProcess = Process()
            clearProcess.executableURL = toolURL
            clearProcess.arguments = [
                "developer", "dvt", "simulate-location", "clear"
            ]
            clearProcess.standardOutput = FileHandle.standardOutput
            clearProcess.standardError = FileHandle.standardError

            print("STOP: launching clear")
            try clearProcess.run()

            guard Self.waitForExit(clearProcess, timeout: 20) else {
                clearProcess.terminate()

                throw NSError(
                    domain: "DeviceConnection",
                    code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Clear timed out. Location restoration is unconfirmed."
                    ]
                )
            }

            // An exited command can still report failure.
            guard clearProcess.terminationStatus == 0 else {
                throw NSError(
                    domain: "DeviceConnection",
                    code: Int(clearProcess.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Clear failed. Check the console and verify Maps."
                    ]
                )
            }

            // Don't report a fully stopped session if its process remains alive.
            guard activeProcess?.isRunning != true else {
                throw NSError(
                    domain: "DeviceConnection",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Clear completed, but the simulation process is still running. Retry Stop."
                    ]
                )
            }

            print("STOP: session exited and clear completed")
        }.value

        // Reset only after both checks succeed.
        simulationProcess = nil
        simulationInput = nil
    }
    // Wait for a process, but stop waiting after the specified time.
    // Call this from a background task because it briefly blocks its thread.
    nonisolated private static func waitForExit(
        _ process: Process,
        timeout: TimeInterval
    ) -> Bool {
        // System uptime measures elapsed time without relying on the clock.
        let deadline = ProcessInfo.processInfo.systemUptime + timeout

        while process.isRunning {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                return false
            }

            // Avoid continuously checking and wasting CPU.
            Thread.sleep(forTimeInterval: 0.05)
        }

        return true
    }
}
