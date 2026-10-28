import Foundation
import Observation

// Own the session state in one shared, observable object.
@MainActor
@Observable
final class DeviceConnection {
    private(set) var state: SimulationState = .idle

    // Selected locally and restored between launches.
    private(set) var executableURL: URL?

    private var simulationProcess: Process?
    private var simulationInput: Pipe?

    // Cleanup requirements come from state, not a separate stored flag.
    var needsCleanup: Bool {
        switch state {
        case .running, .stopping, .cleanupRequired:
            return true
        default:
            return false
        }
    }

    // MARK: - Initialization

    init() {
        if let path = UserDefaults.standard.string(
            forKey: "backendExecutablePath"
        ) {
            executableURL = URL(fileURLWithPath: path)
        }
    }

    // MARK: - Backend selection

    func selectExecutable(_ url: URL) throws {
        // Keep the backend fixed during startup, a session, or cleanup.
        guard state.canStart else {
            throw NSError(
                domain: "DeviceConnection",
                code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Finish the current operation or cleanup before changing the backend."
                ]
            )
        }

        guard FileManager.default.isExecutableFile(
            atPath: url.path
        ) else {
            throw NSError(
                domain: "DeviceConnection",
                code: 6,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Choose an executable pymobiledevice3 file."
                ]
            )
        }

        executableURL = url

        UserDefaults.standard.set(
            url.path,
            forKey: "backendExecutablePath"
        )
    }

    private func requireExecutable() throws -> URL {
        guard let url = executableURL,
              FileManager.default.isExecutableFile(
                atPath: url.path
              ) else {
            throw NSError(
                domain: "DeviceConnection",
                code: 7,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Choose your pymobiledevice3 executable first."
                ]
            )
        }

        return url
    }

    // MARK: - Device discovery

    func listDevices() async throws -> [ConnectedDevice] {
        let toolURL = try requireExecutable()

        // Read process output away from the main actor.
        return try await Task.detached {
            let process = Process()
            let output = Pipe()

            process.executableURL = toolURL
            process.arguments = ["usbmux", "list"]

            process.standardOutput = output
            process.standardError = FileHandle.standardError

            // Request plain output suitable for JSON decoding.
            var environment = ProcessInfo.processInfo.environment
            environment["NO_COLOR"] = "1"
            environment["TERM"] = "dumb"
            process.environment = environment

            try process.run()

            // Drain stdout while the command runs.
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

            return try JSONDecoder().decode(
                [ConnectedDevice].self,
                from: data
            )
        }.value
    }

    // MARK: - Start simulation

    func startSimulation(
        latitude: Double,
        longitude: Double
    ) async throws -> [ConnectedDevice] {
        // This guard runs before any await, preventing overlapping starts.
        guard state.canStart, simulationProcess == nil else {
            throw NSError(
                domain: "DeviceConnection",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Finish the current operation or cleanup first."
                ]
            )
        }

        state = .starting

        do {
            guard latitude.isFinite,
                  longitude.isFinite,
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude) else {
                throw NSError(
                    domain: "DeviceConnection",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Invalid coordinates."
                    ]
                )
            }

            // Discovery belongs to the starting operation.
            let devices = try await listDevices()

            guard !devices.isEmpty else {
                throw NSError(
                    domain: "DeviceConnection",
                    code: 9,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "No device connected."
                    ]
                )
            }

            // USB and Wi-Fi entries can refer to the same physical phone.
            guard Set(devices.map(\.identifier)).count == 1 else {
                throw NSError(
                    domain: "DeviceConnection",
                    code: 10,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Connect only one device."
                    ]
                )
            }

            let process = Process()
            let input = Pipe()

            process.executableURL = try requireExecutable()
            process.arguments = [
                "developer", "dvt", "simulate-location", "set",
                "--", String(latitude), String(longitude)
            ]

            // Retain a dedicated stdin pipe. Shutdown uses signals,
            // because this backend version doesn't stop on Return.
            process.standardInput = input
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError

            process.terminationHandler = { [weak self] finishedProcess in
                let exitCode = finishedProcess.terminationStatus

                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    // Ignore a delayed notification from an older session.
                    guard self.simulationProcess === finishedProcess else {
                        return
                    }

                    // Stop owns expected process termination and cleanup.
                    guard self.state != .stopping else {
                        return
                    }

                    // Process exit does not prove real GPS was restored.
                    self.state = .cleanupRequired(
                        """
                        Simulation process exited with code \(exitCode). \
                        Reconnect if needed and retry Stop.
                        """
                    )
                }
            }

            try process.run()

            simulationProcess = process
            simulationInput = input

            // Process launched; the phone's location must be verified separately.
            state = .running

            return devices
        } catch {
            // Startup failed before an active session was retained.
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Stop simulation

    func stopSimulation() async throws {
        // A second Stop cannot enter while the first is awaiting cleanup.
        guard state.canStop else {
            throw NSError(
                domain: "DeviceConnection",
                code: 8,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No stoppable session, or another operation is in progress."
                ]
            )
        }

        state = .stopping

        do {
            let activeProcess = simulationProcess
            let toolURL = try requireExecutable()

            try await Task.detached {
                // Match the terminal's Control-C behavior first.
                if let activeProcess, activeProcess.isRunning {
                    activeProcess.interrupt()

                    // Fall back to a termination request after a bounded wait.
                    if !Self.waitForExit(activeProcess, timeout: 3) {
                        activeProcess.terminate()
                        _ = Self.waitForExit(activeProcess, timeout: 3)
                    }
                }

                // Attempt clear even if the original process hasn't exited.
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

                guard activeProcess?.isRunning != true else {
                    throw NSError(
                        domain: "DeviceConnection",
                        code: 4,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                """
                                Clear completed, but the simulation process \
                                is still running. Retry Stop.
                                """
                        ]
                    )
                }

                print("STOP: session exited and clear completed")
            }.value

            // Reset only after the shutdown checks succeed.
            simulationProcess = nil
            simulationInput = nil
            state = .idle
        } catch {
            // Preserve recovery controls and the actual failure message.
            state = .cleanupRequired(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Process waiting

    // Call only from a background task: this blocks its thread briefly.
    nonisolated private static func waitForExit(
        _ process: Process,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout

        while process.isRunning {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                return false
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        return true
    }
}
