import SwiftUI
import MapKit
import AppKit

struct ContentView: View {
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var status = "Search, click the map, or enter coordinates"

    @State private var searchQuery = ""
    @State private var isSearching = false

    // Changing this requests that the native map center on the selection.
    @State private var mapFocusRequest = UUID()

    @State private var hasSimulationSession = false
    @State private var isStarting = false
    @State private var isStopping = false

    let deviceConnection: DeviceConnection

    // The fields remain the source of truth for the selected location.
    private var selectedCoordinate: CLLocationCoordinate2D? {
        guard let lat = Double(latitude),
              let lon = Double(longitude),
              lat.isFinite,
              lon.isFinite,
              (-90...90).contains(lat),
              (-180...180).contains(lon) else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: lat,
            longitude: lon
        )
    }

    var body: some View {
        ZStack {
            // The map fills the window behind the floating controls.
            locationMap

            GlassEffectContainer(spacing: 24) {
                VStack(spacing: 20) {
                    searchPanel

                    // This area stays open for interacting with the map.
                    Spacer(minLength: 100)

                    selectionPanel
                }
                .padding(20)
            }
        }
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 640, minHeight: 720)
        .onAppear {
            registerExitCallback()
        }
    }

    // MARK: - Glass panels

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(
                    "Location Changer",
                    systemImage: "location.fill"
                )
                .font(.headline)

                Spacer()

                Button {
                    chooseBackend()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Choose backend")
                .disabled(
                    hasSimulationSession ||
                    isStarting ||
                    isStopping
                )
            }

            searchControls
        }
        .padding(18)
        // Apply glass after padding so it surrounds the entire panel.
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Selected location")
                    .font(.headline)

                Spacer()

                Button {
                    centerOnSelection()
                } label: {
                    Image(systemName: "scope")
                }
                .help("Center on selected location")
                .disabled(selectedCoordinate == nil)
            }

            coordinateFields

            HStack {
                simulationControls

                Spacer()

                Button {
                    Task {
                        await listDevices()
                    }
                } label: {
                    Image(systemName: "iphone")
                }
                .help("Check connected iPhone")
                .disabled(isStarting || isStopping)
            }

            Divider()

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    // MARK: - Search controls

    private var searchControls: some View {
        HStack {
            TextField(
                "Search for a place or address",
                text: $searchQuery
            )
            .onSubmit {
                beginSearch()
            }

            Button(isSearching ? "Searching…" : "Search") {
                beginSearch()
            }
            .disabled(
                isSearching ||
                searchQuery.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            )
        }
    }

    private func beginSearch() {
        guard !isSearching,
              !searchQuery.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            return
        }

        Task {
            await searchLocation()
        }
    }

    // MARK: - Native map

    private var locationMap: some View {
        // The native component handles marker dragging and map navigation.
        LocationMapView(
            latitude: $latitude,
            longitude: $longitude,
            focusRequest: mapFocusRequest
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Coordinate fields

    private var coordinateFields: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Latitude")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("−90 to 90", text: $latitude)
                    .onSubmit {
                        centerOnSelection()
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Longitude")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("−180 to 180", text: $longitude)
                    .onSubmit {
                        centerOnSelection()
                    }
            }
        }
    }

    private func updateCoordinates(
        _ coordinate: CLLocationCoordinate2D
    ) {
        // Keep decimal-point formatting independent of the Mac's region.
        let locale = Locale(identifier: "en_US_POSIX")

        latitude = String(
            format: "%.7f",
            locale: locale,
            coordinate.latitude
        )

        longitude = String(
            format: "%.7f",
            locale: locale,
            coordinate.longitude
        )
    }

    private func centerOnSelection() {
        guard selectedCoordinate != nil else {
            status = "Enter valid coordinates using a decimal point"
            return
        }

        // Ask the map to center without resetting it on every field edit.
        mapFocusRequest = UUID()
    }

    // MARK: - Simulation controls

    private var simulationControls: some View {
        HStack {
            Button(isStarting ? "Starting…" : "Start simulation") {
                guard let coordinate = selectedCoordinate else {
                    status = "Enter valid coordinates"
                    return
                }

                // Capture the selected location before the device check.
                isStarting = true

                Task {
                    await startSimulation(at: coordinate)
                }
            }
            .disabled(
                hasSimulationSession ||
                isStarting ||
                isStopping ||
                selectedCoordinate == nil
            )

            Button(
                isStopping ? "Stopping…" : "Stop / restore location"
            ) {
                isStopping = true

                Task {
                    await stopSimulation()
                }
            }
            .disabled(!hasSimulationSession || isStopping)
        }
    }

    // MARK: - Backend selection

    @MainActor
    private func chooseBackend() {
        let panel = NSOpenPanel()
        panel.title = "Choose pymobiledevice3"
        panel.message = """
        Select the executable inside your project's .venv/bin folder.
        """
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

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

    // MARK: - Address search

    @MainActor
    private func searchLocation() async {
        isSearching = true
        defer { isSearching = false }

        let searchService = LocationSearchService()

        do {
            guard let result = try await searchService.search(
                query: searchQuery
            ) else {
                status = "No places found"
                return
            }

            updateCoordinates(result.location.coordinate)
            mapFocusRequest = UUID()

            status = "Selected: \(result.name ?? searchQuery)"
        } catch {
            status = "Search failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Device discovery

    @MainActor
    private func listDevices() async {
        status = "Looking for an iPhone…"

        do {
            let devices = try await deviceConnection.listDevices()

            if let device = devices.first {
                status = "\(device.name) — iOS \(device.version)"
            } else {
                status = "No devices found. Connect and unlock your iPhone."
            }
        } catch {
            status = "Device check failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Session actions

    @MainActor
    private func startSimulation(
        at coordinate: CLLocationCoordinate2D
    ) async {
        defer { isStarting = false }
        status = "Checking connected device…"

        do {
            let devices = try await deviceConnection.listDevices()

            guard !devices.isEmpty else {
                status = "No device connected"
                return
            }

            guard devices.count == 1 else {
                status = "Connect only one device"
                return
            }

            try deviceConnection.startSimulation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )

            hasSimulationSession = true
            status = "Simulation launched — verify in Maps"
        } catch {
            status = "Couldn't start: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func stopSimulation() async {
        defer { isStopping = false }
        status = "Stopping simulation…"

        do {
            try await deviceConnection.stopSimulation()

            hasSimulationSession = false
            status = "Clear completed — verify real location in Maps"
        } catch {
            // Keep Stop available when cleanup needs to be retried.
            status = "Couldn't restore: \(error.localizedDescription)"
        }
    }

    private func registerExitCallback() {
        deviceConnection.onSimulationExit = { exitCode in
            guard hasSimulationSession, !isStopping else {
                return
            }

            status = """
            Simulation process ended (code \(exitCode)). \
            Press Stop to attempt location cleanup.
            """

            hasSimulationSession = true
        }
    }
}

#Preview {
    ContentView(deviceConnection: AppDelegate().deviceConnection)
}
