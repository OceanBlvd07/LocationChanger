import SwiftUI
import MapKit
import AppKit

struct ContentView: View {
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var status = "Search, click the map, or enter coordinates"

    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var isCheckingDevices = false

    // Change this to request centering on the selected coordinates.
    @State private var mapFocusRequest = UUID()

    @State private var hasSimulationSession = false
    @State private var isStarting = false
    @State private var isStopping = false
    
    // Store all discovered connections, including USB and Wi-Fi entries.
    @State private var discoveredDevices: [ConnectedDevice] = []

    // A timestamp makes it clear that discovery is a snapshot.
    @State private var lastDeviceCheck: Date?

    let deviceConnection: DeviceConnection

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

    private var sessionStatus: String {
        if isStopping {
            return "Stopping"
        }

        if isStarting {
            return "Starting"
        }

        return hasSimulationSession ? "Session launched" : "Ready"
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Leave the map visible behind the glass sidebar.
            locationMap

            sidebar
                .padding(16)
        }
        .frame(minWidth: 900, minHeight: 660)
        .onAppear {
            registerExitCallback()
        }
    }

    // MARK: - Glass sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    searchControls

                    Divider()

                    coordinateFields

                    Button {
                        centerOnSelection()
                    } label: {
                        Label(
                            "Center on selection",
                            systemImage: "scope"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedCoordinate == nil)

                    Divider()

                    simulationControls

                    Text(
                        "Click the map to place a marker. "
                        + "Select and drag it to adjust the location."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                // Leave space inside the scroll area for field focus rings.
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            // Keep scrolling content inside its allocated area.
            .scrollClipDisabled(false)
            .padding(.horizontal, -6)

            Divider()
                .padding(.top, 16)
                .padding(.bottom, 16)

            // The device section stays outside the scrolling content.
            deviceControls
        }
        .padding(20)
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .textFieldStyle(.roundedBorder)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 26)
        )
    }

    private var sidebarHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "location.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Location Changer")
                    .font(.headline)

                Text(sessionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                chooseBackend()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Choose backend")
            .disabled(
                hasSimulationSession ||
                isStarting ||
                isStopping ||
                isCheckingDevices
            )
        }
    }

    // MARK: - Search controls

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search")
                .font(.subheadline.weight(.semibold))

            TextField(
                "Place or address",
                text: $searchQuery
            )
            .onSubmit {
                beginSearch()
            }

            Button {
                beginSearch()
            } label: {
                HStack(spacing: 8) {
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }

                    Text(isSearching ? "Searching…" : "Search")
                }
                .frame(maxWidth: .infinity)
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
        LocationMapView(
            latitude: $latitude,
            longitude: $longitude,
            focusRequest: mapFocusRequest
        )
        // Reserve room for the sidebar so centered markers aren't hidden.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Coordinate fields

    private var coordinateFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Selected coordinates")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Latitude")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("−90 to 90", text: $latitude)
                    .monospacedDigit()
                    .onSubmit {
                        centerOnSelection()
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Longitude")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("−180 to 180", text: $longitude)
                    .monospacedDigit()
                    .onSubmit {
                        centerOnSelection()
                    }
            }
        }
    }

    private func updateCoordinates(
        _ coordinate: CLLocationCoordinate2D
    ) {
        // Always use a decimal point when formatting coordinates.
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

        mapFocusRequest = UUID()
    }

    // MARK: - Simulation controls

    private var simulationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Simulation")
                .font(.subheadline.weight(.semibold))

            Button {
                guard let coordinate = selectedCoordinate else {
                    status = "Enter valid coordinates"
                    return
                }

                // Capture the selection before checking the device.
                isStarting = true

                Task {
                    await startSimulation(at: coordinate)
                }
            } label: {
                Label(
                    isStarting ? "Starting…" : "Start simulation",
                    systemImage: "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                hasSimulationSession ||
                isStarting ||
                isStopping ||
                isCheckingDevices ||
                selectedCoordinate == nil
            )

            Button {
                isStopping = true

                Task {
                    await stopSimulation()
                }
            } label: {
                Label(
                    isStopping ? "Stopping…" : "Stop / restore location",
                    systemImage: "stop.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(!hasSimulationSession || isStopping)

            if hasSimulationSession {
                Text("Changing the selection won't update this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Device and status

    private var deviceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let checkedAt = lastDeviceCheck {
                if discoveredDevices.isEmpty {
                    Label(
                        "No device found",
                        systemImage: "iphone.slash"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    // Show each discovered connection without assuming
                    // that discovery confirms an active simulation transport.
                    ForEach(discoveredDevices.indices, id: \.self) { index in
                        let device = discoveredDevices[index]

                        HStack(spacing: 10) {
                            Image(systemName: device.connectionSymbol)
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .help(device.name)

                                Text("iOS \(device.version)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 4)

                            Text(device.connectionLabel)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    Color.accentColor.opacity(0.12),
                                    in: Capsule()
                                )
                        }
                    }
                }

                HStack(spacing: 4) {
                    Text("Last checked")
                    Text(checkedAt, style: .time)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Connection not checked",
                    systemImage: "iphone"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                isCheckingDevices = true

                Task {
                    await listDevices()
                }
            } label: {
                Label(
                    isCheckingDevices ? "Checking…" : "Refresh connection",
                    systemImage: "arrow.clockwise"
                )
                .frame(maxWidth: .infinity)
            }
            .disabled(isCheckingDevices || isStarting || isStopping)

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        defer { isCheckingDevices = false }
        status = "Looking for an iPhone…"

        do {
            let devices = try await deviceConnection.listDevices()

            // Refresh the displayed discovery snapshot.
            discoveredDevices = devices
            lastDeviceCheck = Date()

            if devices.isEmpty {
                status = "No devices found. Check USB or Wi-Fi connectivity."
            } else {
                status = "Device discovery completed"
            }
        } catch {
            // Don't leave an older connection displayed as a fresh result.
            discoveredDevices = []
            lastDeviceCheck = nil
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
            discoveredDevices = devices
            lastDeviceCheck = Date()

            guard !devices.isEmpty else {
                status = "No device connected"
                return
            }

            guard Set(devices.map(\.identifier)).count == 1 else {
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
            // Keep recovery available if clearing fails.
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
