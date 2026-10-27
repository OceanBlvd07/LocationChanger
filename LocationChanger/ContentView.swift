import SwiftUI
import MapKit
import AppKit

struct ContentView: View {
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var status = "Enter coordinates"
    
    // Stores the address or place name entered in the search field.
    @State private var searchQuery = ""

    // Controls which area the map displays.
    @State private var cameraPosition: MapCameraPosition = .automatic

    // Prevents multiple searches from running at once.
    @State private var isSearching = false
    
    // Tracks a launched session, not confirmation from the iPhone.
    @State private var hasSimulationSession = false

    // Prevents overlapping commands while stopping.
    @State private var isStopping = false
    
    // Prevent duplicate clicks while checking the connected device.
    @State private var isStarting = false
    
    // Use the shared connection instead of creating another one.
    let deviceConnection: DeviceConnection
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Location Changer")
                .font(.title)
            Button("Choose backend…") {
                chooseBackend()
            }
            // Keep the backend fixed while commands or cleanup are in progress.
            .disabled(hasSimulationSession || isStarting || isStopping)
            HStack {
                TextField("Search for a place or address", text: $searchQuery)

                Button(isSearching ? "Searching…" : "Search") {
                    Task {
                        await searchLocation()
                    }
                }
                .disabled(
                    isSearching ||
                    searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            // Gives us a proxy that converts screen positions into map coordinates.
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    // Show a pin only when both fields contain valid coordinates.
                    if let lat = Double(latitude),
                       let lon = Double(longitude),
                       (-90...90).contains(lat),
                       (-180...180).contains(lon) {
                        Marker(
                            "Selected location",
                            coordinate: CLLocationCoordinate2D(
                                latitude: lat,
                                longitude: lon
                            )
                        )
                    }
                }
                .onTapGesture { position in
                    // Convert the click's position within the map to GPS coordinates.
                    if let coordinate = proxy.convert(position, from: .local) {
                        // Updating @State refreshes the fields and moves the pin.
                        latitude = String(format: "%.6f", coordinate.latitude)
                        longitude = String(format: "%.6f", coordinate.longitude)
                    }
                }
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            TextField("Latitude", text: $latitude)
            TextField("Longitude", text: $longitude)
            HStack {
                Button("Start simulation") {
                    guard let lat = Double(latitude),
                          let lon = Double(longitude),
                          lat.isFinite, lon.isFinite,
                          (-90...90).contains(lat),
                          (-180...180).contains(lon) else {
                        status = "Enter valid coordinates"
                        return
                    }

                    isStarting = true
                    status = "Checking connected device…"

                    Task {
                        // Always re-enable controls when this attempt finishes.
                        defer { isStarting = false }

                        do {
                            let devices = try await deviceConnection.listDevices()

                            // Don't launch a simulation without a connected device.
                            guard !devices.isEmpty else {
                                status = "No device connected"
                                return
                            }

                            // Require one device until explicit selection is implemented.
                            guard devices.count == 1 else {
                                status = "Connect only one device"
                                return
                            }

                            try deviceConnection.startSimulation(
                                latitude: lat,
                                longitude: lon
                            )

                            hasSimulationSession = true
                            status = "Simulation launched — verify in Maps"
                        } catch {
                            status = "Couldn't start: \(error.localizedDescription)"
                        }
                    }
                }
                .disabled(hasSimulationSession || isStarting || isStopping)

                Button("Stop / restore location") {
                    // Disable both buttons while the stop command is running.
                    isStopping = true
                    status = "Stopping simulation…"

                    Task {
                        defer { isStopping = false }

                        do {
                            try await deviceConnection.stopSimulation()

                            hasSimulationSession = false
                            status = "Clear completed — verify real location in Maps"
                        } catch {
                            // Keep Stop available so the user can retry.
                            status = "Couldn't restore: \(error.localizedDescription)"
                        }
                    }
                }
                .disabled(!hasSimulationSession || isStopping)
            }
            Button("Check coordinates") {
                guard let lat = Double(latitude),
                      let lon = Double(longitude),
                      lat.isFinite,
                      lon.isFinite,
                      (-90...90).contains(lat),
                      (-180...180).contains(lon) else {
                    status = "Enter valid coordinates"
                    return
                }

                status = "Selected: \(lat), \(lon)"
            }
            Button("List connected devices") {
                // Task lets the button call an asynchronous function.
                Task {
                    status = "Looking for an iPhone…"

                    do {
                        let devices = try await deviceConnection.listDevices()

                        // Show the first device for this initial version.
                        if let device = devices.first {
                            status = "\(device.name) — iOS \(device.version)"
                        } else {
                            status = "No devices found. Connect and unlock your iPhone."
                        }
                    } catch {
                        status = "Device check failed: \(error.localizedDescription)"
                    }
                }
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 600).onAppear {
            // Register the callback when this screen appears.
            deviceConnection.onSimulationExit = { exitCode in
                // Stop handles its own status. Ignore notifications after cleanup.
                guard hasSimulationSession, !isStopping else {
                    return
                }

                // Process exit doesn't prove that the phone restored real GPS.
                status = """
                Simulation process ended (code \(exitCode)). \
                Press Stop to attempt location cleanup.
                """

                // Keep Stop available until cleanup succeeds.
                hasSimulationSession = true
            }
        }
    }
    @MainActor
    private func chooseBackend() {
        let panel = NSOpenPanel()

        panel.title = "Choose pymobiledevice3"
        panel.message = "Select the executable inside your project's .venv/bin folder."
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        // Python environments are usually inside a hidden .venv folder.
        panel.showsHiddenFiles = true

        // Opening the picker does not execute the selected file.
        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            try deviceConnection.selectExecutable(url)
            status = "Backend selected: \(url.lastPathComponent)"
        } catch {
            status = error.localizedDescription
        }
    }
    @MainActor
    private func searchLocation() async {
        isSearching = true

        // Restore the button whether the search succeeds or fails.
        defer { isSearching = false }

        let searchService = LocationSearchService()

        do {
            guard let result = try await searchService.search(query: searchQuery) else {
                status = "No places found"
                return
            }

            // Update the fields and pin using the returned location.
            let coordinate = result.location.coordinate
            latitude = String(format: "%.6f", coordinate.latitude)
            longitude = String(format: "%.6f", coordinate.longitude)

            // Move the map to the selected place.
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.02,
                        longitudeDelta: 0.02
                    )
                )
            )

            status = "Selected: \(result.name ?? searchQuery)"
        } catch {
            // Display errors passed back by the service.
            status = "Search failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView(deviceConnection: AppDelegate().deviceConnection)
}
